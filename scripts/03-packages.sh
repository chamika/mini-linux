#!/usr/bin/env bash
# 03-packages.sh — Install desktop environment and application packages into rootfs.
# Must run after 00-bootstrap.sh.

source "$(dirname "$0")/common.sh"
require_root

log_info "=== Package Installation ==="

if [[ ! -d "${ROOTFS}/usr" ]]; then
    log_error "Rootfs not found. Run 00-bootstrap.sh first."
    exit 1
fi

# Ensure rootfs mirrorlist has active servers (pacstrap copies a fully-commented one)
if ! grep -q "^Server" "${ROOTFS}/etc/pacman.d/mirrorlist" 2>/dev/null; then
    log_info "Fixing rootfs mirrorlist (no active servers found)..."
    cat > "${ROOTFS}/etc/pacman.d/mirrorlist" <<'EOF'
Server = https://mirrors.kernel.org/archlinux/$repo/os/$arch
Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch
Server = https://mirror.rackspace.com/archlinux/$repo/os/$arch
EOF
fi

# --- Desktop environment (GNOME) ---
DESKTOP_PACKAGES=(
    gnome-shell
    gdm
    gnome-control-center
    xdg-desktop-portal-gnome
    gnome-keyring
    xdg-utils
    xdg-user-dirs
)

# --- Applications ---
APP_PACKAGES=(
    gnome-console
    nautilus
    firefox
    gvfs
    gvfs-mtp
)

# --- Audio ---
AUDIO_PACKAGES=(
    pipewire-jack
    pavucontrol
)

# --- Fonts & Theming ---
THEME_PACKAGES=(
    noto-fonts
    noto-fonts-cjk
    noto-fonts-emoji
    ttf-jetbrains-mono-nerd
    papirus-icon-theme
    gtk3
    gtk4
)

# --- System utilities ---
UTIL_PACKAGES=(
    tlp
    brightnessctl
    playerctl
    networkmanager
    networkmanager-openvpn
    blueman
    nftables
    htop
    unzip
    p7zip
    wget
    curl
    linux-firmware
)

ALL_PACKAGES=(
    "${DESKTOP_PACKAGES[@]}"
    "${APP_PACKAGES[@]}"
    "${AUDIO_PACKAGES[@]}"
    "${THEME_PACKAGES[@]}"
    "${UTIL_PACKAGES[@]}"
)

log_info "Installing ${#ALL_PACKAGES[@]} packages into rootfs..."
# Pacman checks free space by finding the mountpoint of / and the cache dir.
# When the rootfs is a plain directory these lookups fail. Fix by bind-mounting
# the rootfs onto itself (making it a real mountpoint) and mounting a host-side
# cache dir so both checks resolve correctly.
PKG_CACHE="${BUILD_DIR}/pacman-cache"
mkdir -p "${PKG_CACHE}" "${ROOTFS}/var/cache/pacman/pkg"
mount --bind "${ROOTFS}" "${ROOTFS}"
mount --bind "${PKG_CACHE}" "${ROOTFS}/var/cache/pacman/pkg"
cleanup_mounts_pkg() {
    umount "${ROOTFS}/var/cache/pacman/pkg" 2>/dev/null || true
    umount "${ROOTFS}" 2>/dev/null || true
}
trap cleanup_mounts_pkg EXIT

arch-chroot "${ROOTFS}" pacman -Syu --noconfirm "${ALL_PACKAGES[@]}"

cleanup_mounts_pkg
trap - EXIT

# Clean pacman cache to reduce image size
arch-chroot "${ROOTFS}" pacman -Scc --noconfirm

log_ok "All packages installed."
log_info "Rootfs size: $(du -sh "${ROOTFS}" | cut -f1)"
