
#!/bin/bash
set -euo pipefail
# =============================================================================
# IPv6 Transition Toolkit Setup Script (Debian Trixie)
# unbound (DNS64) + Jool (NAT64/SIIT, JSON-config-driven) + radvd (RA) + ndppd
# =============================================================================
#
# REQUIREMENTS / WHAT THIS INSTALLS
#   unbound     -> unbound # Optional: include unbound-anchor if DNSSEC root trust anchor management is desired.
#                  binaries: unbound, unbound-checkconf, unbound-control
#                  config:   /etc/unbound/unbound.conf (+ unbound.conf.d/*.conf)
#   jool        -> jool-tools, jool-dkms  (+ dkms, build-essential, matching
#                  linux-headers-$(uname -r) for the DKMS build)
#                  binaries: jool (stateful NAT64), jool_siit (SIIT)
#                  config:   /etc/jool/jool.conf      (JOOL_MODE=nat64)
#                            /etc/jool/jool_siit.conf (JOOL_MODE=siit, default)
#   radvd       -> radvd
#                  binaries: radvd
#                  optional: radvdump (diagnostics)
#                  config:   /etc/radvd.conf  (must exist before service start)
#   ndppd       -> ndppd
#                  binaries: ndppd
#                  config:   /etc/ndppd.conf  (must exist before service start)
#
# All packages are present in Debian trixie main as of this writing
# (jool-dkms/jool-tools 4.1.13-1, ndppd 0.2.5-6). DKMS build success for Jool
# depends on matching kernel headers being available for the running kernel —
# NOT guaranteed on vendor-patched/custom kernels (e.g. SoC BSP kernels), so
# that step is checked and warned on rather than assumed.
# =============================================================================
readonly UNBOUND_PACKAGES=(unbound)
readonly JOOL_PACKAGES=(jool-tools jool-dkms)
readonly RADVD_PACKAGES=(radvd)
readonly NDPPD_PACKAGES=(ndppd)
INSTALL_UNBOUND=${INSTALL_UNBOUND:-true}
INSTALL_JOOL=${INSTALL_JOOL:-true}
INSTALL_RADVD=${INSTALL_RADVD:-true}
INSTALL_NDPPD=${INSTALL_NDPPD:-true}
ENABLE_SERVICES=${ENABLE_SERVICES:-false}   # opt-in: these all need real config first

JOOL_MODE=${JOOL_MODE:-nat64}                # siit | nat64
JOOL_CONF_DIR=/etc/jool
JOOL_EXAMPLES_DIR=/usr/share/doc/jool-tools/examples

APT_UPDATED=false

info() { echo "[INFO]  $*"; }
skip() { echo "[SKIP]  $*"; }
warn() { echo "[WARN]  $*" >&2; }
die()  { echo "[ERROR] $*" >&2; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}
validate_bool() {
  case "$2" in
    true|false) ;;
    *) die "$1 must be true or false (got '$2')" ;;
  esac
}

require_root() {
  [[ "$(id -u)" -eq 0 ]] || die "Run as root"
}

preflight_checks() {
  info "Running preflight checks"
  require_root
  require_cmd apt-get
  require_cmd apt-cache
  require_cmd grep
#  require_cmd jq
  require_cmd dpkg-query

  if [[ ! -f /etc/os-release ]] || ! grep -qi 'trixie' /etc/os-release; then
    warn "/etc/os-release does not confirm Debian trixie — continuing anyway"
  fi

  case "$JOOL_MODE" in
    siit|nat64) ;;
    *) die "JOOL_MODE must be 'siit' or 'nat64', got '${JOOL_MODE}'" ;;
  esac
  validate_bool "INSTALL_UNBOUND" "$INSTALL_UNBOUND"
  validate_bool "INSTALL_JOOL" "$INSTALL_JOOL"
  validate_bool "INSTALL_RADVD" "$INSTALL_RADVD"
  validate_bool "INSTALL_NDPPD" "$INSTALL_NDPPD"
  validate_bool "ENABLE_SERVICES" "$ENABLE_SERVICES"
  readonly INSTALL_UNBOUND
  readonly INSTALL_JOOL
  readonly INSTALL_RADVD
  readonly INSTALL_NDPPD
  readonly ENABLE_SERVICES
  readonly JOOL_MODE
}

apt_update_once() {
  if [[ "$APT_UPDATED" == false ]]; then
    info "Refreshing apt package index"
    apt-get update
    APT_UPDATED=true
  else
    skip "apt index already refreshed this run"
  fi
}

# -----------------------------------------------------------------------------
# Generic package-set helper
# -----------------------------------------------------------------------------
packages_installed() {
  # Usage: packages_installed pkg1 pkg2 ...
  local pkg
  for pkg in "$@"; do
    dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null \
      | grep -q "install ok installed" || return 1
  done
  return 0
}

# -----------------------------------------------------------------------------
# unbound (DNSv6 resolver)
# -----------------------------------------------------------------------------


unbound_is_installed() { packages_installed "${UNBOUND_PACKAGES[@]}"; }

install_unbound() {
  info "Installing unbound (DNS64-capable resolver)"
  apt_update_once
  apt-get install -y "${UNBOUND_PACKAGES[@]}"
  require_cmd unbound
  require_cmd unbound-checkconf
}

# -----------------------------------------------------------------------------
# Jool (SIIT / NAT64) — userspace tools + DKMS kernel modules, JSON-config-driven
# -----------------------------------------------------------------------------


if [[ "$JOOL_MODE" == "nat64" ]]; then
  JOOL_SERVICE="jool.service"
  JOOL_CONF="${JOOL_CONF_DIR}/jool.conf"
  JOOL_EXAMPLE="${JOOL_EXAMPLES_DIR}/jool.conf"
else
  JOOL_SERVICE="jool_siit.service"
  JOOL_CONF="${JOOL_CONF_DIR}/jool_siit.conf"
  JOOL_EXAMPLE="${JOOL_EXAMPLES_DIR}/jool_siit.conf"
fi

jool_is_installed() { packages_installed "${JOOL_PACKAGES[@]}"; }

install_kernel_headers() {
  local hdr_pkg="linux-headers-$(uname -r)"
  info "Checking kernel header availability for DKMS: ${hdr_pkg}"
  if apt-cache policy "$hdr_pkg" | grep -q 'Candidate: [^()]'; then
    apt-get install -y "$hdr_pkg"
  else
    warn "${hdr_pkg} not found in apt (likely a vendor-patched/custom kernel)."
    warn "jool-dkms will fail to build its kernel module without matching headers."
    warn "Source or build headers for this exact kernel before re-running."
  fi
}

install_jool() {
  info "Installing DKMS toolchain (dkms, build-essential)"
  apt_update_once
  apt-get install -y dkms build-essential

  install_kernel_headers

  info "Installing Jool (jool-tools, jool-dkms)"
  apt-get install -y "${JOOL_PACKAGES[@]}"

  require_cmd jool
  require_cmd jool_siit

  verify_jool_dkms
}

verify_jool_dkms() {
  info "Verifying Jool DKMS module build status"
  if command -v dkms >/dev/null 2>&1 \
      && dkms status 2>/dev/null | grep -qi '^jool.*installed'; then
    info "jool DKMS module reports 'installed' for $(uname -r)"
  else
    warn "Could not confirm the jool DKMS module is built+installed for $(uname -r)."
    warn "Check 'dkms status' and /var/lib/dkms/jool/*/build/make.log on failure."
  fi
}

setup_jool_conf() {
  info "Preparing Jool JSON config (${JOOL_MODE} mode) at ${JOOL_CONF}"

  mkdir -p "$JOOL_CONF_DIR"

  if [[ -f "$JOOL_CONF" ]]; then
    skip "${JOOL_CONF} already exists — leaving it untouched"
  elif [[ -f "$JOOL_EXAMPLE" ]]; then
    info "Seeding ${JOOL_CONF} from packaged example (edit before enabling ${JOOL_SERVICE})"
    cp "$JOOL_EXAMPLE" "$JOOL_CONF"
  else
    warn "No packaged example found at ${JOOL_EXAMPLE}."
    warn "You must create ${JOOL_CONF} by hand before ${JOOL_SERVICE} will start cleanly."
  fi

  validate_jool_conf
}

validate_jool_conf() {
    [[ -f "$JOOL_CONF" ]] || return 0

    command -v jq >/dev/null 2>&1 || {
        warn "jq not installed — skipping JSON validation"
        return 0
    }

    jq empty "$JOOL_CONF" >/dev/null 2>&1 \
        && info "${JOOL_CONF} is valid JSON" \
        || warn "${JOOL_CONF} is NOT valid JSON"
}

# -----------------------------------------------------------------------------
# radvd (Router Advertisement daemon)
# -----------------------------------------------------------------------------

radvd_is_installed() { packages_installed "${RADVD_PACKAGES[@]}"; }

install_radvd() {
  info "Installing radvd"
  apt_update_once
  apt-get install -y "${RADVD_PACKAGES[@]}"
  require_cmd radvd

  [[ -f /etc/radvd.conf ]] || \
    warn "/etc/radvd.conf not present — radvd.service will refuse to start until created"
}

# -----------------------------------------------------------------------------
# ndppd (NDP Proxy Daemon)
# -----------------------------------------------------------------------------

ndppd_is_installed() { packages_installed "${NDPPD_PACKAGES[@]}"; }

install_ndppd() {
  info "Installing ndppd"
  apt_update_once
  apt-get install -y "${NDPPD_PACKAGES[@]}"
  require_cmd ndppd

  [[ -f /etc/ndppd.conf ]] || \
    warn "/etc/ndppd.conf not present — ndppd.service will refuse to start until created"
}

# -----------------------------------------------------------------------------
# Optional service enablement (opt-in via ENABLE_SERVICES=true)
# -----------------------------------------------------------------------------
enable_service_if_requested() {
  local svc="$1"

  if [[ "$ENABLE_SERVICES" != true ]]; then
    skip "ENABLE_SERVICES=false — leaving ${svc} unstarted"
    return 0
  fi

  if systemctl is-enabled "$svc" >/dev/null 2>&1; then
    skip "${svc} already enabled"
  else
    info "Enabling ${svc}"
    systemctl enable "$svc"
  fi

  if systemctl is-active "$svc" >/dev/null 2>&1; then
    skip "${svc} already active"
  else
    info "Starting ${svc}"
    systemctl start "$svc" || \
      warn "${svc} failed to start — check its config and 'journalctl -u ${svc}'"
  fi
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
  preflight_checks

  if [[ "$INSTALL_UNBOUND" == true ]]; then
    if unbound_is_installed; then
      skip "unbound already installed"
    else
      install_unbound
    fi
  fi

  if [[ "$INSTALL_JOOL" == true ]]; then
    if jool_is_installed; then
      skip "jool-tools/jool-dkms already installed"
    else
      install_jool
    fi
    setup_jool_conf
  fi

  if [[ "$INSTALL_RADVD" == true ]]; then
    if radvd_is_installed; then
      skip "radvd already installed"
    else
      install_radvd
    fi
  fi

  if [[ "$INSTALL_NDPPD" == true ]]; then
    if ndppd_is_installed; then
      skip "ndppd already installed"
    else
      install_ndppd
    fi
  fi

  enable_service_if_requested unbound
  [[ "$INSTALL_JOOL" == true ]] && enable_service_if_requested "$JOOL_SERVICE"
  enable_service_if_requested radvd
  enable_service_if_requested ndppd

  info "Installation complete."
  info "Next: configure DNS64 in /etc/unbound/unbound.conf.d/, write /etc/radvd.conf,"
  info "write /etc/ndppd.conf, and edit ${JOOL_CONF} (${JOOL_MODE} mode)."
  info "Re-run with ENABLE_SERVICES=true once configs are in place to enable+start services."
}

main "$@"
