#!/bin/bash
set -euo pipefail

# =============================================================================
# Kea DHCP Server Setup Script (Refactored)
# =============================================================================

# -----------------------------------------------------------------------------
# Configuration (Networking set to empty by default)
# -----------------------------------------------------------------------------
PING_HOST=${PING_HOST:-8.8.8.8}

# Database Config
DB_HOST=${DB_HOST:-127.0.0.1}
DB_PORT=${DB_PORT:-3306}
DB_NAME=${DB_NAME:-firewall}
DB_USER=${DB_USER:-kea_user}
DB_USER_PASSWORD=${DB_USER_PASSWORD:-kea@123}
DB_ROOT_PASSWORD=${DB_ROOT_PASSWORD:-}

# Networking - Emptied as requested
INTERFACE4=${INTERFACE4:-}
INTERFACE6=${INTERFACE6:-}
SUBNET4=${SUBNET4:-}
POOL4=${POOL4:-}
ROUTER4=${ROUTER4:-}
SUBNET6=${SUBNET6:-}
POOL6=${POOL6:-}
DNS4=${DNS4:-}
DNS6=${DNS6:-}

# File Paths
DHCP4_CONF=/etc/kea/kea-dhcp4.conf
DHCP6_CONF=/etc/kea/kea-dhcp6.conf
CTRL_CONF=/etc/kea/kea-ctrl-agent.conf

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------
info() { echo "[INFO] $*"; }
err()  { echo "[ERROR] $*" >&2; }
die()  { err "$*"; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"
}

# -----------------------------------------------------------------------------
# Core Functions
# -----------------------------------------------------------------------------

preflight_checks() {
  info "Running preflight checks..."
  require_cmd apt
  require_cmd curl
  ping -c1 -W5 "$PING_HOST" >/dev/null || die "No internet connectivity"
}

install_kea_packages() {
  local packages=(
    isc-kea-admin isc-kea-common isc-kea-dhcp4 isc-kea-dhcp6
    isc-kea-hooks isc-kea-ctrl-agent isc-kea-mysql mariadb-server
  )
  
  info "Installing Kea packages from Cloudsmith"
  curl -fsSL https://dl.cloudsmith.io/public/isc/kea-3-0/setup.deb.sh | bash
  apt update
  apt install -y "${packages[@]}"
}

setup_mysql_permissions() {
  info "Configuring MySQL database and user"
  local mysql_args=(-u root)
  [[ -n "$DB_ROOT_PASSWORD" ]] && mysql_args+=("-p$DB_ROOT_PASSWORD")

  mysql "${mysql_args[@]}" <<EOF
CREATE DATABASE IF NOT EXISTS \`$DB_NAME\`;
CREATE USER IF NOT EXISTS '$DB_USER'@'%' IDENTIFIED BY '$DB_USER_PASSWORD';
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'%';
FLUSH PRIVILEGES;
EOF
}

init_kea_schema() {
  info "Checking Kea schema state"
  
  local schema_exists
  schema_exists=$(mysql -u"$DB_USER" -p"$DB_USER_PASSWORD" -N -B "$DB_NAME" \
    -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$DB_NAME' AND table_name='schema_version';")

  if [[ "$schema_exists" -eq 0 ]]; then
    info "No schema found, initializing Kea database..."
    kea-admin db-init mysql -h "$DB_HOST" -u "$DB_USER" -p "$DB_USER_PASSWORD" -n "$DB_NAME"
  else
    info "Kea schema already present, skipping db-init"
  fi
}

write_dhcp4_config() {
  info "Writing DHCPv4 config to $DHCP4_CONF"
  cat >"$DHCP4_CONF" <<EOF
{
  "Dhcp4": {
    "interfaces-config": { "interfaces": [ "$INTERFACE4" ] },
    "lease-database": {
      "type": "mysql",
      "name": "$DB_NAME",
      "user": "$DB_USER",
      "password": "$DB_USER_PASSWORD",
      "host": "$DB_HOST",
      "port": $DB_PORT
    },
    "option-data": [
      { "name": "domain-name-servers", "data": "$DNS4" },
      { "name": "routers", "data": "$ROUTER4" }
    ],
    "subnet4": [
      {
        "subnet": "$SUBNET4",
        "pools": [ { "pool": "$POOL4" } ]
      }
    ],
    "loggers": [{
      "name": "kea-dhcp4",
      "severity": "INFO",
      "output_options": [{ "output": "/var/log/kea/kea-dhcp4.log" }]
    }]
  }
}
EOF
}

write_dhcp6_config() {
  info "Writing DHCPv6 config to $DHCP6_CONF"
  cat >"$DHCP6_CONF" <<EOF
{
  "Dhcp6": {
    "interfaces-config": { "interfaces": [ "$INTERFACE6" ] },
    "lease-database": {
      "type": "mysql",
      "name": "$DB_NAME",
      "user": "$DB_USER",
      "password": "$DB_USER_PASSWORD",
      "host": "$DB_HOST",
      "port": $DB_PORT
    },
    "subnet6": [
      {
        "subnet": "$SUBNET6",
        "pools": [ { "pool": "$POOL6" } ]
      }
    ],
    "option-data": [ { "name": "dns-servers", "data": "$DNS6" } ],
    "loggers": [{
      "name": "kea-dhcp6",
      "severity": "INFO",
      "output_options": [{ "output": "/var/log/kea/kea-dhcp6.log" }]
    }]
  }
}
EOF
}

write_ctrl_agent_config() {
  info "Configuring Control Agent"
  cat >"$CTRL_CONF" <<EOF
{
  "Control-agent": {
    "http-host": "127.0.0.1",
    "http-port": 8000,
    "control-sockets": {
      "dhcp4": { "socket-type": "unix", "socket-name": "/run/kea/kea4-ctrl-socket" },
      "dhcp6": { "socket-type": "unix", "socket-name": "/run/kea/kea6-ctrl-socket" }
    }
  }
}
EOF
}

finalize_system() {
  info "Finalizing: Log directories and services"
  mkdir -p /var/log/kea
  chown -R _kea:_kea /var/log/kea

  systemctl enable isc-kea-dhcp4-server isc-kea-dhcp6-server isc-kea-ctrl-agent
  systemctl restart isc-kea-dhcp4-server isc-kea-dhcp6-server isc-kea-ctrl-agent
}

# -----------------------------------------------------------------------------
# Main Execution
# -----------------------------------------------------------------------------

main() {
  preflight_checks
  install_kea_packages
  setup_mysql_permissions
  init_kea_schema
  
  write_dhcp4_config
  write_dhcp6_config
  write_ctrl_agent_config
  
  finalize_system
  
info "Kea DHCP server setup COMPLETE"

info "NOTE: DHCP interfaces and subnets may be empty."
info "      Update the configuration files under /etc/kea/ before serving clients."

info "NOTE: Verify services with:"
info "      systemctl status isc-kea-dhcp4-server"
info "      systemctl status isc-kea-dhcp6-server"
info "      systemctl status isc-kea-ctrl-agent"

info "NOTE: Review logs if services fail to start:"
info "      journalctl -xeu isc-kea-dhcp4-server"
info "      journalctl -xeu isc-kea-dhcp6-server"
info "      journalctl -xeu isc-kea-ctrl-agent"
info "HINT: Use kea-config-tool or kea-shell to reload configuration without restarting services."

}

main "$@"