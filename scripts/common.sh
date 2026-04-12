#!/usr/bin/env bash
# Common variables and functions for mini-linux build scripts.
# Source this at the top of every script: source "$(dirname "$0")/common.sh"

set -euo pipefail

# --- Build Configuration ---
export BUILD_DIR="${BUILD_DIR:-/tmp/mini-linux-build}"
export ROOTFS="${BUILD_DIR}/rootfs"
export SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
export CONFIG_DIR="${PROJECT_ROOT}/config"
export MINI_LINUX_USER="${MINI_LINUX_USER:-user}"
export MINI_LINUX_HOSTNAME="${MINI_LINUX_HOSTNAME:-mini-linux}"
export KERNEL_VERSION="${KERNEL_VERSION:-6.12}"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
log_ok()    { echo -e "${GREEN}[ OK ]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERR ]${NC} $*" >&2; }

require_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (or with sudo)."
        exit 1
    fi
}

require_command() {
    local cmd="$1"
    if ! command -v "$cmd" &>/dev/null; then
        log_error "Required command not found: $cmd"
        exit 1
    fi
}

# Run a command inside the rootfs chroot
chroot_run() {
    arch-chroot "$ROOTFS" "$@"
}

cleanup_mounts() {
    log_info "Cleaning up mounts..."
    umount -R "${ROOTFS}/proc" 2>/dev/null || true
    umount -R "${ROOTFS}/sys" 2>/dev/null || true
    umount -R "${ROOTFS}/dev" 2>/dev/null || true
    umount -R "${ROOTFS}/run" 2>/dev/null || true
}
