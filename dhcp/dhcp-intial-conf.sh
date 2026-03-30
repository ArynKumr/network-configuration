#!/bin/bash
set -euo pipefail
# =============================================================================
# Kea DHCP Server Setup Script
# =============================================================================
# Designed for UTM appliances where DHCP is optional/opt-in.
# Safe to run on every boot or initial install — all steps are idempotent.
# =============================================================================

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
KEA_DB_HOST=${KEA_DB_HOST:-localhost}
KEA_DB_PORT=${KEA_DB_PORT:-3306}
KEA_DB_NAME=${KEA_DB_NAME:-kea_dhcp}
KEA_DB_USER=${KEA_DB_USER:-kea_user}
KEA_DB_PASSWORD=${KEA_DB_PASSWORD:-kea@123}
DB_ROOT_PASSWORD=${DB_ROOT_PASSWORD:-}
DHCP4_CONF=/etc/kea/kea-dhcp4.conf
DHCP6_CONF=/etc/kea/kea-dhcp6.conf

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------
info()  { echo "[INFO]  $*"; }
skip()  { echo "[SKIP]  $*"; }
warn()  { echo "[WARN]  $*" >&2; }
err()   { echo "[ERROR] $*" >&2; }
die()   { err "$*"; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

require_root() {
  [[ "$(id -u)" -eq 0 ]] || die "This script must be run as root"
}

# Returns 0 if all core Kea packages are installed
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

# Returns 0 if both config files already exist on disk
configs_exist() {
  [[ -f "$DHCP4_CONF" && -f "$DHCP6_CONF" ]]
}

# Returns 0 if at least one real interface is set in both configs.
# Kea 3.0 hard-errors on empty interfaces-config, so we use this
# to gate the -t validation step only.
interfaces_configured() {
  local dhcp4_ifaces dhcp6_ifaces
  dhcp4_ifaces=$(grep -oP '"interfaces"\s*:\s*\[\s*\K[^\]]+' "$DHCP4_CONF" 2>/dev/null \
    | tr -d ' "' | grep -v '^$' || true)
  dhcp6_ifaces=$(grep -oP '"interfaces"\s*:\s*\[\s*\K[^\]]+' "$DHCP6_CONF" 2>/dev/null \
    | tr -d ' "' | grep -v '^$' || true)
  [[ -n "$dhcp4_ifaces" && -n "$dhcp6_ifaces" ]]
}

# -----------------------------------------------------------------------------
# Core Functions
# -----------------------------------------------------------------------------
preflight_checks() {
  info "Running preflight checks..."
  require_root
  require_cmd apt
  require_cmd curl
  require_cmd mysql
  require_cmd systemctl

  # Report upfront what will be skipped so the operator knows the state
  if kea_is_installed; then
    info "Kea packages already installed — install step will be skipped"
  fi
  if configs_exist; then
    info "Config files already exist — write step will be skipped"
    info "  $DHCP4_CONF"
    info "  $DHCP6_CONF"
  fi
}

install_kea_packages() {
  local packages=(
    isc-kea-admin isc-kea-common isc-kea-dhcp4 isc-kea-dhcp6
    isc-kea-hooks isc-kea-mysql
  )
  info "Installing Kea packages"
  curl -fsSL https://dl.cloudsmith.io/public/isc/kea-3-0/setup.deb.sh | bash
  apt update
  apt install -y "${packages[@]}"
}

setup_mysql_permissions() {
  info "Configuring MySQL database and user"
  systemctl enable mariadb
  systemctl start mariadb
  local mysql_args=(-u root)
  [[ -n "$DB_ROOT_PASSWORD" ]] && mysql_args+=("-p${DB_ROOT_PASSWORD}")
  mysql "${mysql_args[@]}" <<EOF
CREATE DATABASE IF NOT EXISTS \`${KEA_DB_NAME}\`;
CREATE USER IF NOT EXISTS '${KEA_DB_USER}'@'%' IDENTIFIED BY '${KEA_DB_PASSWORD}';
GRANT ALL PRIVILEGES ON \`${KEA_DB_NAME}\`.* TO '${KEA_DB_USER}'@'%';
FLUSH PRIVILEGES;
EOF
}

init_kea_schema() {
  info "Checking Kea schema state"
  local schema_exists
  schema_exists=$(mysql -u"${KEA_DB_USER}" -p"${KEA_DB_PASSWORD}" -N -B "${KEA_DB_NAME}" \
    -e "SELECT COUNT(*) FROM information_schema.tables
        WHERE table_schema='${KEA_DB_NAME}' AND table_name='schema_version';" || echo 0)

  if [[ "$schema_exists" -eq 0 ]]; then
    info "Initializing Kea database schema"
    kea-admin db-init mysql \
      -h "${KEA_DB_HOST}" \
      -u "${KEA_DB_USER}" \
      -p "${KEA_DB_PASSWORD}" \
      -n "${KEA_DB_NAME}"
  else
    info "Kea schema already present"
  fi
}

write_dhcp4_config() {
  info "Writing DHCPv4 config"
  # Note: uses single-quote heredoc (<<'EOF') to prevent shell expansion of
  # the hardcoded credentials inside the JSON.
  cat >"$DHCP4_CONF" <<'EOF'
{
  "Dhcp4": {
    "interfaces-config": {
      "interfaces": []
    },
    "decline-probation-period": 300,
    "control-socket": {
      "socket-type": "unix",
      "socket-name": "kea4-ctrl-socket"
    },
    "lease-database": {
      "type": "mysql",
      "name": "kea_dhcp",
      "user": "kea_user",
      "password": "kea@123",
      "host": "localhost",
      "port": 3306
    },
    "hosts-database": {
      "type": "mysql",
      "name": "kea_dhcp",
      "user": "kea_user",
      "password": "kea@123",
      "host": "localhost",
      "port": 3306
    },
    "hooks-libraries": [
      { "library": "libdhcp_mysql.so" },
      { "library": "libdhcp_host_cmds.so" },
      { "library": "libdhcp_lease_cmds.so" }
    ],
    "subnet4": [],
    "loggers": [
      {
        "name": "kea-dhcp4",
        "output_options": [
          {
            "output": "kea-dhcp4.log",
            "pattern": "%d %-5p [%c] %m\n",
            "maxsize": 1048576,
            "maxver": 8
          }
        ],
        "severity": "INFO",
        "debuglevel": 0
      }
    ]
  }
}
EOF
}

write_dhcp6_config() {
  info "Writing DHCPv6 config"
  cat >"$DHCP6_CONF" <<EOF
{
  "Dhcp6": {
    "interfaces-config": {
      "interfaces": []
    },
    "decline-probation-period": 300,
    "control-socket": {
      "socket-type": "unix",
      "socket-name": "kea6-ctrl-socket"
    },
    "lease-database": {
      "type": "mysql",
      "name": "${KEA_DB_NAME}",
      "user": "${KEA_DB_USER}",
      "password": "${KEA_DB_PASSWORD}",
      "host": "${KEA_DB_HOST}",
      "port": ${KEA_DB_PORT}
    },
    "hosts-database": {
      "type": "mysql",
      "name": "${KEA_DB_NAME}",
      "user": "${KEA_DB_USER}",
      "password": "${KEA_DB_PASSWORD}",
      "host": "${KEA_DB_HOST}",
      "port": ${KEA_DB_PORT}
    },
    "hooks-libraries": [
      { "library": "libdhcp_mysql.so" },
      { "library": "libdhcp_host_cmds.so" },
      { "library": "libdhcp_lease_cmds.so" }
    ],
    "subnet6": [],
    "loggers": [
      {
        "name": "kea-dhcp6",
        "output_options": [
          {
            "output": "kea-dhcp6.log",
            "pattern": "%d %-5p [%c] %m\n",
            "maxsize": 1048576,
            "maxver": 8
          }
        ],
        "severity": "INFO",
        "debuglevel": 0
      }
    ]
  }
}
EOF
}

# Validates config with kea's built-in -t flag.
# Skipped when interfaces are empty — Kea 3.0 hard-errors on empty
# interfaces-config, which is expected on a UTM not yet acting as
# a DHCP provider.
validate_config() {
  if interfaces_configured; then
    info "Validating Kea configuration"
    kea-dhcp4 -t "$DHCP4_CONF"
    kea-dhcp6 -t "$DHCP6_CONF"
  else
    skip "Skipping config validation — no interfaces configured yet"
    skip "This is expected on a UTM not currently acting as a DHCP provider"
  fi
}

# Always runs on every boot to ensure correct systemd service state.
# If Kea can't open sockets (no interfaces/subnets configured) it will
# exit on its own — we catch that and warn rather than failing the script.
ensure_services() {
  info "Ensuring Kea services are enabled and started"
  mkdir -p /var/log/kea
  chown -R _kea:_kea /var/log/kea
  systemctl enable isc-kea-dhcp4-server isc-kea-dhcp6-server
  systemctl restart isc-kea-dhcp4-server isc-kea-dhcp6-server || {
    warn "Kea services did not start cleanly"
    warn "If no interfaces or subnets are configured, this is expected"
    warn "Configure $DHCP4_CONF and $DHCP6_CONF then run:"
    warn "  systemctl start isc-kea-dhcp4-server isc-kea-dhcp6-server"
  }
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
  preflight_checks

  if kea_is_installed; then
    skip "Kea packages already installed"
  else
    install_kea_packages
  fi

  setup_mysql_permissions   # idempotent — uses CREATE IF NOT EXISTS
  init_kea_schema           # idempotent — checks schema_version table first

  if configs_exist; then
    skip "Config files already exist — skipping write"
    skip "Delete $DHCP4_CONF / $DHCP6_CONF to regenerate defaults"
  else
    write_dhcp4_config
    write_dhcp6_config
  fi

  validate_config   # safe no-op when interfaces are empty
  ensure_services   # always runs — systemd owns service state on every boot

  info "Kea DHCP setup COMPLETE"
  info "This device is not currently acting as a DHCP provider."
  info "To enable DHCP, configure interfaces and subnets in:"
  info "  $DHCP4_CONF"
  info "  $DHCP6_CONF"
  info "Then restart: systemctl restart isc-kea-dhcp4-server isc-kea-dhcp6-server"
}

main "$@"
