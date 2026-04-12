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

# --- Desktop environment (Hyprland + Wayland) ---
DESKTOP_PACKAGES=(
    hyprland
    xdg-desktop-portal-hyprland
    waybar
    wofi
    mako
    swaylock
    hyprpaper
    polkit-gnome
    grim
    slurp
    wl-clipboard
    xdg-utils
    xdg-user-dirs
)

# --- Applications ---
APP_PACKAGES=(
    kitty
    thunar
    thunar-volman
    gvfs
    gvfs-mtp
    tumbler
    ffmpegthumbnailer
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
    qt5-wayland
    qt6-wayland
)

# --- System utilities ---
UTIL_PACKAGES=(
    tlp
    brightnessctl
    playerctl
    networkmanager-openvpn
    nm-connection-editor
    blueman
    nftables
    htop
    unzip
    p7zip
    wget
    curl
)

ALL_PACKAGES=(
    "${DESKTOP_PACKAGES[@]}"
    "${APP_PACKAGES[@]}"
    "${AUDIO_PACKAGES[@]}"
    "${THEME_PACKAGES[@]}"
    "${UTIL_PACKAGES[@]}"
)

log_info "Installing ${#ALL_PACKAGES[@]} packages into rootfs..."
# Bind-mount a host-side cache dir so pacman can detect the mountpoint for
# free-space checks (fails when rootfs is a plain directory, not a mountpoint).
PKG_CACHE="${BUILD_DIR}/pacman-cache"
mkdir -p "${PKG_CACHE}" "${ROOTFS}/var/cache/pacman/pkg"
mount --bind "${PKG_CACHE}" "${ROOTFS}/var/cache/pacman/pkg"
trap 'umount "${ROOTFS}/var/cache/pacman/pkg" 2>/dev/null || true' EXIT

arch-chroot "${ROOTFS}" pacman -Syu --noconfirm "${ALL_PACKAGES[@]}"

umount "${ROOTFS}/var/cache/pacman/pkg"
trap - EXIT

# --- AUR packages (Google Chrome) ---
log_info "Setting up AUR package build..."

# Re-mount cache for AUR build
mount --bind "${PKG_CACHE}" "${ROOTFS}/var/cache/pacman/pkg"
trap 'umount "${ROOTFS}/var/cache/pacman/pkg" 2>/dev/null || true' EXIT

# Create a build user for makepkg (cannot run as root)
arch-chroot "${ROOTFS}" useradd -m -s /bin/bash builder 2>/dev/null || true
arch-chroot "${ROOTFS}" bash -c "echo 'builder ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/builder"

# Install google-chrome from AUR
log_info "Building google-chrome from AUR (this may take a few minutes)..."
arch-chroot "${ROOTFS}" su - builder -c "
    cd /tmp
    git clone https://aur.archlinux.org/google-chrome.git
    cd google-chrome
    makepkg -si --noconfirm
    cd /tmp && rm -rf google-chrome
"

# Clean up build user
arch-chroot "${ROOTFS}" userdel -r builder 2>/dev/null || true
arch-chroot "${ROOTFS}" rm -f /etc/sudoers.d/builder

umount "${ROOTFS}/var/cache/pacman/pkg"
trap - EXIT

# Clean pacman cache to reduce image size
arch-chroot "${ROOTFS}" pacman -Scc --noconfirm

log_ok "All packages installed."
log_info "Rootfs size: $(du -sh "${ROOTFS}" | cut -f1)"
