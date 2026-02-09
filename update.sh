#!/usr/bin/env bash
#
# Comprehensive Update Script for Debian-based Systems
# Updates apt, installs necessary packages, upgrades system, and cleans up

# --------------------------------------------------
# Enable unofficial bash "strict mode":
# - e : Exit immediately if a command exits with a non-zero status
# - u : Treat unset variables as an error
# - o pipefail : Pipeline returns the exit status of the last command that had a non-zero exit code
# --------------------------------------------------
set -euo pipefail

# --------------------------------------------------
# Config (override via env vars if desired)
# --------------------------------------------------
: "${LOG_DIR:=/var/log/update-script}"
: "${LOG_FILE:=$LOG_DIR/update.log}"
: "${REQUIRED_DISK_KB:=1048576}"       # 1GB
: "${JOURNAL_VACUUM_TIME:=7d}"         # journald vacuum retention
: "${RUN_DOCKCHECK:=1}"                # 1=run dockcheck if docker installed
: "${DOCKCHECK_REF:=main}"             # branch/tag for dockcheck script
: "${DOCKCHECK_OPTS:=-apfs}"           # dockcheck options

# --------------------------------------------------
# Globals
# --------------------------------------------------
SCRIPT_NAME="$(basename "$0")"
HOSTNAME="$(hostname)"
START_TIME="$(date +%s)"
TMPDIR_CLEANUP=""

# --------------------------------------------------
# Early privilege escalation (before touching /var/log)
# --------------------------------------------------
if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "Requires root. Re-running with sudo."
  exec sudo -E bash "$0" "$@"
fi

# --------------------------------------------------
# Ensure log path exists, then tee all output to log
# --------------------------------------------------
install -d -m 0755 "$LOG_DIR"
touch "$LOG_FILE"
chmod 0644 "$LOG_FILE"
exec > >(tee -a "$LOG_FILE") 2>&1

# --------------------------------------------------
# Utility Functions
# --------------------------------------------------
print_section() {
  echo -e "\e[1;34m${1}\e[0m"
}

print_info()    { echo -e "\e[1;32m▶\e[0m ${1}"; }
print_warning() { echo -e "\e[1;33m⚠\e[0m ${1}"; }
print_error()   { echo -e "\e[1;31m✗\e[0m ${1}"; }

have_cmd() { command -v "$1" &>/dev/null; }

# --------------------------------------------------
# Trap handlers
# --------------------------------------------------
cleanup_tmp() {
  if [[ -n "${TMPDIR_CLEANUP:-}" && -d "${TMPDIR_CLEANUP:-}" ]]; then
    rm -rf "$TMPDIR_CLEANUP" || true
  fi
}

on_err() {
  local exit_code=$?
  print_error "Script failed with exit code $exit_code at line ${BASH_LINENO[0]} while running ${BASH_COMMAND}."
  cleanup_tmp
  exit "$exit_code"
}

on_exit() {
  cleanup_tmp
  # Reboot prompt if needed
  if [[ -f /var/run/reboot-required ]]; then
    echo -e "\n\e[1;33mReboot required. Reboot now? [y/N]:\e[0m "
    read -r reboot_now || reboot_now="N"
    if [[ "${reboot_now}" =~ ^[Yy]$ ]]; then
      print_info "Rebooting."
      reboot
    fi
  fi
}

trap on_err ERR
trap on_exit EXIT

# --------------------------------------------------
# Prerequisites and Validation
# --------------------------------------------------
check_root_privileges() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    print_error "Root privileges required."
    exit 1
  fi
}

check_dependencies() {
  local required_commands=("apt-get" "dpkg" "grep" "awk" "df" "find")
  for cmd in "${required_commands[@]}"; do
    if ! have_cmd "$cmd"; then
      print_error "Required command '$cmd' is not available."
      return 1
    fi
  done
}

format_kb_human() {
  local kb="$1"
  # Prefer numfmt if available
  if have_cmd numfmt; then
    numfmt --to=iec --suffix=B $((kb * 1024))
    return 0
  fi

  # Fallback: show "X GB Y MB"
  if (( kb >= 1048576 )); then
    local gb=$((kb / 1048576))
    local mb=$(((kb % 1048576) / 1024))
    echo "${gb}GB ${mb}MB"
  else
    local mb=$((kb / 1024))
    echo "${mb}MB"
  fi
}

check_disk_space() {
  local available_kb
  available_kb="$(df --output=avail -k / | tail -n1 | tr -d ' ')"

  if (( available_kb < REQUIRED_DISK_KB )); then
    print_error "Insufficient disk space. Need $(format_kb_human "$REQUIRED_DISK_KB"), have $(format_kb_human "$available_kb")."
    exit 1
  fi
}

# --------------------------------------------------
# Package Management Functions
# --------------------------------------------------
update_apt_packages() {
  echo
  print_section "Updating package lists!"
  echo
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  echo
}

is_pkg_installed() {
  dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed"
}

install_necessary_packages() {
  export DEBIAN_FRONTEND=noninteractive

  local packages=("curl")  # needed for dockcheck download

  for package in "${packages[@]}"; do
    if ! is_pkg_installed "$package"; then
      if ! apt-get install -y "$package"; then
        print_warning "Failed to install $package."
      fi
    fi
  done
}


upgrade_system() {
  echo
  print_section "Upgrading system packages!"
  echo
  export DEBIAN_FRONTEND=noninteractive
  apt-get -y \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold" \
    full-upgrade
  echo
}

autoclean_and_purge() {
  echo
  print_section "Cleaning up unused packages and cache!"
  echo
  export DEBIAN_FRONTEND=noninteractive
  apt-get autoremove -y --purge
  apt-get clean
  apt-get autoclean
  echo
}

cleanup_old_kernels() {
  echo
  print_section "Removing old kernel packages!"
  echo
  export DEBIAN_FRONTEND=noninteractive
  apt-get autoremove -y --purge
  echo
}

# --------------------------------------------------
# Log / Journal Maintenance (SAFE)
# --------------------------------------------------
cleanup_logs() {
  echo
  print_section "Cleaning up system logs!"
  echo
  if have_cmd journalctl; then
    journalctl --vacuum-time="$JOURNAL_VACUUM_TIME" || true
  fi
  if [[ -f "$LOG_FILE" ]]; then
    local max_lines=20000
    local cur_lines
    cur_lines="$(wc -l < "$LOG_FILE" | tr -d ' ')"
    if (( cur_lines > max_lines )); then
      tail -n "$max_lines" "$LOG_FILE" > "${LOG_FILE}.tmp" && mv "${LOG_FILE}.tmp" "$LOG_FILE"
    fi
  fi
  echo
}

# --------------------------------------------------
# Docker Maintenance
# --------------------------------------------------
docker_maintenance() {
  echo
  print_section "Updating Docker containers and cleaning up old images, volumes, and networks!"
  if ! have_cmd docker; then
    return 0
  fi
  # Use default local daemon; avoid inheriting user's DOCKER_HOST/DOCKER_CONTEXT from sudo -E
  unset -v DOCKER_HOST DOCKER_CONTEXT DOCKER_CONFIG
  if ! docker info &>/dev/null; then
    print_warning "Docker daemon is not reachable."
    return 0
  fi
  if (( RUN_DOCKCHECK == 1 )); then
    if ! have_cmd curl; then
      apt-get update
      apt-get install -y curl
    fi
    local dockcheck_dir="/usr/local/lib/update-script"
    local dockcheck_file="$dockcheck_dir/dockcheck.sh"
    local dockcheck_url="https://raw.githubusercontent.com/mag37/dockcheck/${DOCKCHECK_REF}/dockcheck.sh"
    install -d -m 0755 "$dockcheck_dir" 2>/dev/null || true
    if curl -fsSLo "$dockcheck_file" "$dockcheck_url"; then
      chmod +x "$dockcheck_file"
      (cd "$dockcheck_dir" && bash "$dockcheck_file" ${DOCKCHECK_OPTS}) || true
    fi
  fi
  docker system prune -a -f --volumes
  echo
}

# --------------------------------------------------
# Snap Package Updates
# --------------------------------------------------
update_snap_packages() {
  if ! have_cmd snap; then
    return 0
  fi
  echo
  print_section "Updating snap packages!"
  echo
  if ! systemctl is-active --quiet snapd 2>/dev/null; then
    systemctl start snapd 2>/dev/null || return 0
  fi
  snap refresh
  echo
}

# --------------------------------------------------
# Main Execution
# --------------------------------------------------
main() {
  check_root_privileges
  check_disk_space
  check_dependencies
  update_apt_packages
  install_necessary_packages
  upgrade_system
  update_snap_packages
  autoclean_and_purge
  cleanup_old_kernels
  cleanup_logs
  docker_maintenance
  if [[ -r /proc/cpuinfo ]] && grep -q "Raspberry Pi" /proc/cpuinfo; then
    echo -e "\n\e[1;33mRun unifi-update.sh? [y/N]:\e[0m "
    read -t 30 -rp "" run_unifi || run_unifi="N"
    if [[ "${run_unifi}" =~ ^[Yy]$ ]]; then
      if [[ -f "/home/doubleangels/unifi-update.sh" ]]; then
        chmod +x /home/doubleangels/unifi-update.sh
        bash /home/doubleangels/unifi-update.sh
      fi
    fi
  fi
}

main "$@"