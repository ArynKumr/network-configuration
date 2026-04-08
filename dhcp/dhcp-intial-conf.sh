#!/bin/bash
set -euo pipefail

# =============================================================================
# Kea DHCP Server Setup Script
# =============================================================================

KEA_DB_HOST=${KEA_DB_HOST:-localhost}
KEA_DB_PORT=${KEA_DB_PORT:-3306}
KEA_DB_NAME=${KEA_DB_NAME:-kea_dhcp}
KEA_DB_USER=${KEA_DB_USER:-kea_user}
KEA_DB_PASSWORD=${KEA_DB_PASSWORD:-kea@123}
DB_ROOT_PASSWORD=${DB_ROOT_PASSWORD:-}

info() { echo "[INFO]  $*"; }
skip() { echo "[SKIP]  $*"; }
warn() { echo "[WARN]  $*" >&2; }
die()  { echo "[ERROR] $*" >&2; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

require_root() {
  [[ "$(id -u)" -eq 0 ]] || die "Run as root"
}

# -----------------------------------------------------------------------------
# Convenience wrapper — uses root credentials consistently everywhere
# -----------------------------------------------------------------------------
mysql_root() {
  mysql -u root ${DB_ROOT_PASSWORD:+-p"${DB_ROOT_PASSWORD}"} "$@"
}

preflight_checks() {
  info "Running preflight checks"
  require_root
  require_cmd apt
  require_cmd curl
  require_cmd mysql
  require_cmd systemctl
}

install_kea_packages() {
  info "Installing Kea"
  # NOTE: curl|bash is convenient but skips checksum verification.
  # Review https://dl.cloudsmith.io/public/isc/kea-3-0/setup.deb.sh before running in production.
  curl -fsSL https://dl.cloudsmith.io/public/isc/kea-3-0/setup.deb.sh | bash
  apt update
  apt install -y \
    isc-kea-admin isc-kea-common isc-kea-dhcp4 \
    isc-kea-dhcp6 isc-kea-hooks isc-kea-mysql

  require_cmd kea-admin   # sanity-check post-install
}

kea_is_installed() {
  local packages=(
    isc-kea-admin isc-kea-common isc-kea-dhcp4
    isc-kea-dhcp6 isc-kea-hooks isc-kea-mysql
  )
  for pkg in "${packages[@]}"; do
    dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null \
      | grep -q "install ok installed" || return 1
  done
  return 0
}

# -----------------------------------------------------------------------------
# MySQL helpers
# -----------------------------------------------------------------------------
db_exists() {
  local count
  count=$(mysql_root -N -B \
    -e "SELECT COUNT(*) FROM information_schema.schemata
        WHERE schema_name='${KEA_DB_NAME}';" 2>/dev/null || echo 0)
  [[ "$count" -gt 0 ]]
}

user_exists() {
  local count
  count=$(mysql_root -N -B \
    -e "SELECT COUNT(*) FROM mysql.user
        WHERE user='${KEA_DB_USER}';" 2>/dev/null || echo 0)
  [[ "$count" -gt 0 ]]
}

schema_exists() {
  mysql_root -N -B "${KEA_DB_NAME}" \
    -e "SELECT COUNT(*) FROM information_schema.tables
        WHERE table_schema='${KEA_DB_NAME}' AND table_name='schema_version';" \
    2>/dev/null | grep -q "1"
}

setup_mysql_db() {
  info "Ensuring database '${KEA_DB_NAME}' exists"
  mysql_root <<EOF
CREATE DATABASE IF NOT EXISTS \`${KEA_DB_NAME}\`;
EOF
}

setup_mysql_user() {
  info "Ensuring MySQL user '${KEA_DB_USER}' and privileges"
  mysql_root <<EOF
CREATE USER IF NOT EXISTS '${KEA_DB_USER}'@'%' IDENTIFIED BY '${KEA_DB_PASSWORD}';
GRANT ALL PRIVILEGES ON \`${KEA_DB_NAME}\`.* TO '${KEA_DB_USER}'@'%';
FLUSH PRIVILEGES;
EOF
}

# Combines db + user setup — single entry point used by main()
setup_mysql() {
  db_exists   && skip "Database '${KEA_DB_NAME}' already exists"   || setup_mysql_db
  user_exists && skip "User '${KEA_DB_USER}' already exists"       || setup_mysql_user
}

init_kea_schema() {
  if schema_exists; then
    skip "Kea schema already present"
  else
    info "Initializing Kea schema via kea-admin (running as root)"
    kea-admin db-init mysql \
      -u root \
      ${DB_ROOT_PASSWORD:+-p "${DB_ROOT_PASSWORD}"} \
      -n "${KEA_DB_NAME}"
  fi
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
  preflight_checks

  if kea_is_installed; then
    skip "Kea already installed"
  else
    install_kea_packages
  fi

  # DB and schema checks are independent — schema may be absent even if
  # the DB and user were created in a previous (incomplete) run.
  setup_mysql
  init_kea_schema

  info "Installation complete. You may proceed with setting up the DHCP Server from the front."
}

main "$@"
