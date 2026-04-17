#!/usr/bin/env bash
# 00-bootstrap.sh — Create a minimal Arch Linux root filesystem.
# Must run as root on a Linux system with pacstrap installed.
# On Ubuntu: sudo apt install arch-install-scripts

source "$(dirname "$0")/common.sh"
require_root
require_command pacstrap

log_info "=== Mini-Linux Bootstrap ==="
log_info "Build directory: ${BUILD_DIR}"
log_info "Root filesystem: ${ROOTFS}"

# Create build directory
mkdir -p "${ROOTFS}"

# Base packages — minimal Arch system + hardware essentials
BASE_PACKAGES=(
    base
    linux-firmware
    intel-ucode
    sudo
    networkmanager
    bluez
    bluez-utils
    pipewire
    wireplumber
    pipewire-pulse
    pipewire-alsa
    wpa_supplicant
    base-devel
    git
    vim
    man-db
    man-pages
)

log_info "Running pacstrap to create base rootfs..."
log_info "Packages: ${BASE_PACKAGES[*]}"

pacstrap -K "${ROOTFS}" "${BASE_PACKAGES[@]}"

# Ensure the rootfs mirrorlist has an active server so arch-chroot/pacman works
log_info "Configuring mirror in rootfs..."
cat > "${ROOTFS}/etc/pacman.d/mirrorlist" <<'EOF'
Server = https://mirrors.kernel.org/archlinux/$repo/os/$arch
Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch
Server = https://mirror.rackspace.com/archlinux/$repo/os/$arch
EOF

log_ok "Bootstrap complete. Rootfs at ${ROOTFS}"
log_info "Rootfs size: $(du -sh "${ROOTFS}" | cut -f1)"
