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
DB_HOST=${DB_HOST:-localhost}
DB_PORT=${DB_PORT:-3306}
DB_NAME=${DB_NAME:-firewall}
DB_USER=${DB_USER:-kea_user}
DB_USER_PASSWORD=${DB_USER_PASSWORD:-kea@123}
DB_ROOT_PASSWORD=${DB_ROOT_PASSWORD:-}

# Directory paths
SUBNETS_DIR4=${SUBNETS_DIR4:-/etc/kea/kea-dhcp4-subnets.d}
SUBNETS_DIR6=${SUBNETS_DIR6:-/etc/kea/kea-dhcp6-subnets.d}

# DHCP configuration
DNS_SERVERS=${DNS_SERVERS:-"8.8.4.4, 8.8.8.8"}
DNS6_SERVERS=${DNS6_SERVERS:-"2001:4860:4860::8888, 2001:4860:4860::8844"}
VALID_LIFETIME_IPv4=${VALID_LIFETIME_IPv4:-86400} #Can be left blank as defaults to this value
VALID_LIFETIME_IPv6=${VALID_LIFETIME_IPv6:-86400} #Can be left blank as defaults to this value

# Target config file paths
DHCP4_CONF_PATH=${DHCP4_CONF_PATH:-/etc/kea/kea-dhcp4.conf}
DHCP6_CONF_PATH=${DHCP6_CONF_PATH:-/etc/kea/kea-dhcp6.conf}


# File Paths
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
    isc-kea-hooks isc-kea-mysql mariadb-server
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
        "interfaces-config": {
            "interfaces": []
        },
        "control-socket": {
            "socket-type": "unix",
            "socket-name": "/var/run/kea/kea4-ctrl-socket"
        },
        "lease-database": {
            "type": "mysql",
            "name": "${DB_NAME}",
            "user": "${DB_USER}",
            "password": "${DB_USER_PASSWORD}",
            "host": "${DB_HOST}",
            "port": ${DB_PORT}
        },
        "hosts-database": {
            "type": "mysql",
            "name": "${DB_NAME}",
            "user": "${DB_USER}",
            "password": "${DB_USER_PASSWORD}",
            "host": "${DB_HOST}",
            "port": ${DB_PORT}
        },
        "expired-leases-processing": {
            "reclaim-timer-wait-time": 10,
            "flush-reclaimed-timer-wait-time": 25,
            "hold-reclaimed-time": 3600,
            "max-reclaim-leases": 100,
            "max-reclaim-time": 250,
            "unwarned-reclaim-cycles": 5
        },
        "calculate-tee-times": true,
        "valid-lifetime": ${VALID_LIFETIME_IPv4},
        "option-data": [
            {
                "name": "domain-name-servers",
                "data": "${DNS_SERVERS}"
            }
        ],

        "hooks-libraries": [
          {
            "library": "/usr/lib/aarch64-linux-gnu/kea/hooks/libdhcp_mysql.so"
          },
          {
            "library": "/usr/lib/aarch64-linux-gnu/kea/hooks/libdhcp_host_cmds.so"
          }
        ],
        
        "subnet4": [
        ],

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
                // Supported values: FATAL, ERROR, WARN, INFO, DEBUG
                "severity": "INFO",
                "debuglevel": 0
            }
        ]
    }
  }
EOF
}

write_dhcp6_config() {
  info "Writing DHCPv6 config to $DHCP6_CONF"
  cat >"$DHCP6_CONF" <<EOF
{
    "Dhcp6": {
        "interfaces-config": {
            "interfaces": []
        },
        "control-socket": {
            "socket-type": "unix",
            "socket-name": "/var/run/kea/kea6-ctrl-socket"
        },
        "lease-database": {
            "type": "mysql",
            "name": "${DB_NAME}",
            "user": "${DB_USER}",
            "password": "${DB_USER_PASSWORD}",
            "host": "${DB_HOST}",
            "port": ${DB_PORT}
        },
        "hosts-database": {
            "type": "mysql",
            "name": "${DB_NAME}",
            "user": "${DB_USER}",
            "password": "${DB_USER_PASSWORD}",
            "host": "${DB_HOST}",
            "port": ${DB_PORT}
        },
        "expired-leases-processing": {
            "reclaim-timer-wait-time": 10,
            "flush-reclaimed-timer-wait-time": 25,
            "hold-reclaimed-time": 3600,
            "max-reclaim-leases": 100,
            "max-reclaim-time": 250,
            "unwarned-reclaim-cycles": 5
        },
        "calculate-tee-times": true,
        "valid-lifetime": ${VALID_LIFETIME_IPv6},
        "option-data": [
            {
                "name": "dns-servers",
                "data": "${DNS6_SERVERS}"
            }
        ],

        "hooks-libraries": [
          {
            "library": "/usr/lib/aarch64-linux-gnu/kea/hooks/libdhcp_mysql.so"
          },
          {
            "library": "/usr/lib/aarch64-linux-gnu/kea/hooks/libdhcp_host_cmds.so"
          }
        ],
        "subnet6": [
        ],
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
                // Supported values: FATAL, ERROR, WARN, INFO, DEBUG
                "severity": "INFO",
                "debuglevel": 0
            }
        ]
    }
}
EOF
}


finalize_system() {
  info "Finalizing: Log directories and services"
  mkdir -p /var/log/kea
  chown -R _kea:_kea /var/log/kea

  systemctl enable isc-kea-dhcp4-server isc-kea-dhcp6-server
  systemctl restart isc-kea-dhcp4-server isc-kea-dhcp6-server 
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
  finalize_system
info "Kea DHCP server setup COMPLETE"
info "NOTE: DHCP interfaces and subnets may be empty."
info "      Update the configuration files under /etc/kea/ before serving clients."
info "NOTE: Verify services with:"
info "      systemctl status isc-kea-dhcp4-server"
info "      systemctl status isc-kea-dhcp6-server"
info "NOTE: Review logs if services fail to start:"
info "      journalctl -xeu isc-kea-dhcp4-server"
info "      journalctl -xeu isc-kea-dhcp6-server"
info "HINT: Use kea-config-tool or kea-shell to reload configuration without restarting services." #To be tested
}

main "$@"