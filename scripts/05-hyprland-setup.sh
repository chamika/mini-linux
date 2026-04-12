#!/usr/bin/env bash
# 05-hyprland-setup.sh — Install desktop environment configs into rootfs.

source "$(dirname "$0")/common.sh"
require_root

log_info "=== Hyprland Desktop Setup ==="

if [[ ! -d "${ROOTFS}/usr" ]]; then
    log_error "Rootfs not found. Run 00-bootstrap.sh first."
    exit 1
fi

# Bind-mount rootfs so arch-chroot sees it as a real mountpoint
mount --bind "${ROOTFS}" "${ROOTFS}"
trap 'umount "${ROOTFS}" 2>/dev/null || true' EXIT

USER_HOME="${ROOTFS}/home/${MINI_LINUX_USER}"
CONFIG_HOME="${USER_HOME}/.config"

# Create config directories
mkdir -p "${CONFIG_HOME}/hypr"
mkdir -p "${CONFIG_HOME}/waybar"
mkdir -p "${CONFIG_HOME}/kitty"
mkdir -p "${CONFIG_HOME}/wofi"
mkdir -p "${CONFIG_HOME}/mako"

# Copy configs
log_info "Installing Hyprland config..."
cp "${CONFIG_DIR}/hyprland/hyprland.conf" "${CONFIG_HOME}/hypr/hyprland.conf"

log_info "Installing Waybar config..."
cp "${CONFIG_DIR}/waybar/config.jsonc" "${CONFIG_HOME}/waybar/config.jsonc"
cp "${CONFIG_DIR}/waybar/style.css" "${CONFIG_HOME}/waybar/style.css"

log_info "Installing Kitty config..."
cp "${CONFIG_DIR}/kitty/kitty.conf" "${CONFIG_HOME}/kitty/kitty.conf"

log_info "Installing Wofi config..."
cp "${CONFIG_DIR}/wofi/config" "${CONFIG_HOME}/wofi/config"

log_info "Installing Mako config..."
cp "${CONFIG_DIR}/mako/config" "${CONFIG_HOME}/mako/config"

# --- GTK Theme ---
log_info "Configuring GTK theme..."
mkdir -p "${CONFIG_HOME}/gtk-3.0"
cat > "${CONFIG_HOME}/gtk-3.0/settings.ini" <<EOF
[Settings]
gtk-theme-name=Adwaita-dark
gtk-icon-theme-name=Papirus-Dark
gtk-cursor-theme-name=Adwaita
gtk-cursor-theme-size=24
gtk-font-name=Noto Sans 11
gtk-application-prefer-dark-theme=1
EOF

# --- Cursor theme for Hyprland ---
mkdir -p "${CONFIG_HOME}/icons/default"
cat > "${CONFIG_HOME}/icons/default/index.theme" <<EOF
[Icon Theme]
Inherits=Adwaita
EOF

# Fix ownership using numeric UID/GID (name-based chown fails on host for chroot users)
USER_UID=$(grep "^${MINI_LINUX_USER}:" "${ROOTFS}/etc/passwd" | cut -d: -f3)
USER_GID=$(grep "^${MINI_LINUX_USER}:" "${ROOTFS}/etc/passwd" | cut -d: -f4)
if [[ -n "${USER_UID}" ]]; then
    chown -R "${USER_UID}:${USER_GID}" "${ROOTFS}/home/${MINI_LINUX_USER}"
else
    log_warn "Could not find UID for '${MINI_LINUX_USER}' — skipping chown"
fi

log_ok "Desktop environment configured."
umount "${ROOTFS}" 2>/dev/null || true
trap - EXIT
