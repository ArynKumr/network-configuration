#!/bin/bash
set -euo pipefail

# =============================================================================
# Kea DHCP Server Setup Script (Fixed)
# =============================================================================

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

# Kea DB Configuration
KEA_DB_HOST=${KEA_DB_HOST:-localhost}
KEA_DB_PORT=${KEA_DB_PORT:-3306}
KEA_DB_NAME=${KEA_DB_NAME:-kea_dhcp}
KEA_DB_USER=${KEA_DB_USER:-kea_user}
KEA_DB_PASSWORD=${KEA_DB_PASSWORD:-kea@123}
DB_ROOT_PASSWORD=${DB_ROOT_PASSWORD:-}

# DHCP configuration
DNS_SERVERS=${DNS_SERVERS:-"8.8.4.4, 8.8.8.8"}
DNS6_SERVERS=${DNS6_SERVERS:-"2001:4860:4860::8888, 2001:4860:4860::8844"}
VALID_LIFETIME_IPv4=${VALID_LIFETIME_IPv4:-86400}
VALID_LIFETIME_IPv6=${VALID_LIFETIME_IPv6:-86400}

DHCP4_CONF=/etc/kea/kea-dhcp4.conf
DHCP6_CONF=/etc/kea/kea-dhcp6.conf

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------

info() { echo "[INFO] $*"; }
err()  { echo "[ERROR] $*" >&2; }
die()  { err "$*"; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"
}

require_root() {
  [[ "$(id -u)" -eq 0 ]] || die "This script must be run as root"
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
}

install_kea_packages() {
  local packages=(
    isc-kea-admin isc-kea-common isc-kea-dhcp4 isc-kea-dhcp6
    isc-kea-hooks isc-kea-mysql mariadb-server
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
detect_lib_path() {
  local arch
  arch=$(arch)

  case "$arch" in
    x86_64)
      echo "/usr/lib/x86_64-linux-gnu/kea/hooks"
      ;;
    aarch64 | arm64)
      echo "/usr/lib/aarch64-linux-gnu/kea/hooks"
      ;;
    *)
      die "Unsupported architecture: $arch"
      ;;
  esac
}
init_kea_schema() {
  info "Checking Kea schema state"

  local schema_exists
  schema_exists=$(mysql -u"${KEA_DB_USER}" -p"${KEA_DB_PASSWORD}" -N -B "${KEA_DB_NAME}" \
    -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${KEA_DB_NAME}' AND table_name='schema_version';" || echo 0)

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
KEA_HOOKS_PATH=$(detect_lib_path)
info "Using Kea hooks path: $KEA_HOOKS_PATH"
write_dhcp4_config() {

  info "Writing DHCPv4 config"

  cat >"$DHCP4_CONF" <<EOF
{
  "Dhcp4": {
      "interfaces-config": {
    "interfaces": [ ]
  },
    "control-socket": {
      "socket-type": "unix",
      "socket-name": "/var/run/kea/kea4-ctrl-socket"
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
    "valid-lifetime": ${VALID_LIFETIME_IPv4},
    "hooks-libraries": [
      {
        "library": "${KEA_HOOKS_PATH}/libdhcp_mysql.so"
      },
      {
        "library": "${KEA_HOOKS_PATH}/libdhcp_host_cmds.so"
      }
    ],
    "subnet4": [],
    "loggers": [
      {
        "name": "kea-dhcp4",
        "output_options": [
          {
            "output": "/var/log/kea/kea-dhcp4.log",
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
    "interfaces": [ ]
  },
    "control-socket": {
      "socket-type": "unix",
      "socket-name": "/var/run/kea/kea6-ctrl-socket"
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
    "valid-lifetime": ${VALID_LIFETIME_IPv6},
    "hooks-libraries": [
      {
        "library": "${KEA_HOOKS_PATH}/libdhcp_mysql.so"
      },
      {
        "library": "${KEA_HOOKS_PATH}/libdhcp_host_cmds.so"
      }
    ],
    "subnet6": [],
    "loggers": [
      {
        "name": "kea-dhcp6",
        "output_options": [
          {
            "output": "/var/log/kea/kea-dhcp6.log",
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

validate_and_restart() {
  info "Validating Kea configuration"

  kea-dhcp4 -t -c "$DHCP4_CONF"
  kea-dhcp6 -t -c "$DHCP6_CONF"

  mkdir -p /var/log/kea
  chown -R _kea:_kea /var/log/kea

  systemctl enable isc-kea-dhcp4-server isc-kea-dhcp6-server
  systemctl restart isc-kea-dhcp4-server isc-kea-dhcp6-server

  info "Kea services restarted successfully"
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

main() {
  preflight_checks
  install_kea_packages
  setup_mysql_permissions
  init_kea_schema
  write_dhcp4_config
  write_dhcp6_config
  validate_and_restart

  info "Kea DHCP server setup COMPLETE"
  info "Interfaces and subnets are currently empty."
  info "Update /etc/kea/kea-dhcp4.conf and kea-dhcp6.conf before production use."
}

main "$@"
