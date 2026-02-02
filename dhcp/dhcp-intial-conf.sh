#!/bin/bash
set -euo pipefail

# =============================================================================
# Kea DHCP Server Setup Script
# =============================================================================

# -----------------------------------------------------------------------------
# Helper Functions
# -----------------------------------------------------------------------------
info() { echo "[INFO] $*"; }
err() { echo "[ERROR] $*" >&2; }
die() {
  err "$*"
  exit 1
}
require_cmd() { command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"; }
ensure_internet() {
  ping -c 1 -W 5 "$PING_HOST" >/dev/null 2>&1 || die "No internet connection detected. Cannot proceed."
}

# -----------------------------------------------------------------------------
# Configuration Variables
# -----------------------------------------------------------------------------
# Network connectivity
PING_HOST=${PING_HOST:-8.8.8.8}

# Package installation
KEA_PACKAGES=${KEA_PACKAGES:-"isc-kea-admin isc-kea-common isc-kea-dhcp4 isc-kea-dhcp6 isc-kea-hooks isc-kea-mysql radvd"}

# Database configuration
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
VALID_LIFETIME_IPv4=${VALID_LIFETIME_IPv4:-86400}
VALID_LIFETIME_IPv6=${VALID_LIFETIME_IPv6:-86400}

# Target config file paths
DHCP4_CONF_PATH=${DHCP4_CONF_PATH:-/etc/kea/kea-dhcp4.conf}
DHCP6_CONF_PATH=${DHCP6_CONF_PATH:-/etc/kea/kea-dhcp6.conf}

# Database table names for permission grants
DB_TABLES=(
  "host_identifier_type"
  "hosts"
  "ipv6_reservations"
  "schema_version"
  "dhcp4_options"
  "dhcp6_options"
  "lease4"
)

# -----------------------------------------------------------------------------
# Core Functions
# -----------------------------------------------------------------------------

# Add ISC KEA repository
add_isc_kea_repository() {
  info "Adding ISC KEA repository..."
  curl -1sLf 'https://dl.cloudsmith.io/public/isc/kea-3-0/setup.deb.sh' | bash
  apt update
  info "Done"
}

# Install Kea DHCP packages
install_kea_packages() {
  info "Installing Kea DHCP packages..."
  ensure_internet
  add_isc_kea_repository
  apt install -y ${KEA_PACKAGES} || die "Failed to install Kea DHCP packages"
  info "Done"
}

# Create configuration directories
create_config_directories() {
  info "Creating configuration directories..."
  mkdir -p "$SUBNETS_DIR4" || die "Failed to create directory $SUBNETS_DIR4"
  mkdir -p "$SUBNETS_DIR6" || die "Failed to create directory $SUBNETS_DIR6"
  info "Done"
}

# Grant permissions to specific tables only
grant_table_permissions() {
  info "Granting table-specific permissions..."

  local grant_sql=""
  for table in "${DB_TABLES[@]}"; do
    grant_sql+="GRANT SELECT, INSERT, UPDATE, DELETE ON \`$DB_NAME\`.$table TO '$DB_USER'@'$DB_HOST';"
  done
  grant_sql+="FLUSH PRIVILEGES;"

  mysql "${MYSQL_AUTH_ARGS[@]}" -e "$grant_sql" || die "Failed to grant table permissions"
  info "Done"
}

# Check if tables exist and grant permissions
setup_table_permissions() {
  info "Checking for existing tables and setting up permissions..."

  # Check if any of the expected tables exist
  local tables_exist
  tables_exist=$(mysql "${MYSQL_AUTH_ARGS[@]}" -N -B -e \
    "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${DB_NAME}' AND table_name IN ('hosts','host_identifier_type','dhcp4_options','dhcp6_options','ipv6_reservations','schema_version');" 2>/dev/null || echo "0")

  if [[ "$tables_exist" -eq 0 ]]; then
    info "No tables found in database '$DB_NAME'"
    info "Please create tables first."
    return 0
  fi

  info "Found $tables_exist tables in database '$DB_NAME'"

  # Grant permissions to existing tables
  grant_table_permissions

  info "Done"
}

# Setup MySQL database and user
setup_database() {
  info "Setting up MySQL database..."

  # Validate required commands
  require_cmd mysql

  # Check MySQL service
  if ! systemctl is-active --quiet mysql; then
    die "MySQL service is not running"
  fi

  # Validate required parameters
  [[ -n "$DB_USER_PASSWORD" ]] || die "DB_USER_PASSWORD must be set"

  # Build MySQL authentication arguments
  if [[ -z "$DB_ROOT_PASSWORD" ]]; then
    info "Using MySQL socket authentication"
    MYSQL_AUTH_ARGS=(-u root)
  else
    info "Using MySQL password authentication"
    MYSQL_AUTH_ARGS=(-h "$DB_HOST" -P "$DB_PORT" -u root -p"$DB_ROOT_PASSWORD")
  fi

  # Create database and user
  mysql "${MYSQL_AUTH_ARGS[@]}" <<EOF
CREATE USER IF NOT EXISTS '$DB_USER'@'$DB_HOST' IDENTIFIED BY '$DB_USER_PASSWORD';
FLUSH PRIVILEGES;
EOF
  [[ $? -eq 0 ]] || die "Failed to create database or user"

  info "User created successfully"

  # Setup table permissions (tables should be created manually)
  setup_table_permissions
}

# Write DHCPv4 configuration
write_dhcp4_config() {
  local target_path="$1"
  local temp_file
  temp_file=$(mktemp)

  info "Writing DHCPv4 configuration to $target_path"

  cat >"$temp_file" <<EOF
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

  cp "$temp_file" "$target_path" || die "Failed to write DHCPv4 config"
  rm -f "$temp_file"
  info "DHCPv4 configuration written successfully"
}

# Write DHCPv6 configuration
write_dhcp6_config() {
  local target_path="$1"
  local temp_file
  temp_file=$(mktemp)

  info "Writing DHCPv6 configuration to $target_path"

  cat >"$temp_file" <<EOF
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

  cp "$temp_file" "$target_path" || die "Failed to write DHCPv6 config"
  rm -f "$temp_file"
  info "DHCPv6 configuration written successfully"
}

# Restart Kea services
restart_kea_services() {
  info "Enabling Kea services..."
  systemctl enable isc-kea-dhcp4-server
  systemctl enable isc-kea-dhcp6-server
  info "Done"
  info "Restarting Kea services..."
  systemctl restart isc-kea-dhcp4-server
  systemctl restart isc-kea-dhcp6-server
  info "Done"
}

# -----------------------------------------------------------------------------
# Main Execution
# -----------------------------------------------------------------------------
main() {
  info "Setting up Kea DHCP server..."

  # Execute setup steps in sequence
  install_kea_packages
  create_config_directories
  setup_database
  write_dhcp4_config "$DHCP4_CONF_PATH"
  write_dhcp6_config "$DHCP6_CONF_PATH"
  restart_kea_services

  info "Kea DHCP server setup completed successfully!"
  info "Configuration files:"
  info "  DHCPv4: $DHCP4_CONF_PATH"
  info "  DHCPv6: $DHCP6_CONF_PATH"
  info "Database: $DB_NAME on $DB_HOST"
}

# Run main function
main "$@"
