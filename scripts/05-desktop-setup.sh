#!/usr/bin/env bash
# 05-desktop-setup.sh — Configure GNOME desktop defaults in rootfs.

source "$(dirname "$0")/common.sh"
require_root

log_info "=== GNOME Desktop Setup ==="

if [[ ! -d "${ROOTFS}/usr" ]]; then
    log_error "Rootfs not found. Run 00-bootstrap.sh first."
    exit 1
fi

# Bind-mount rootfs so arch-chroot sees it as a real mountpoint
mount --bind "${ROOTFS}" "${ROOTFS}"
trap 'umount "${ROOTFS}" 2>/dev/null || true' EXIT

USER_HOME="${ROOTFS}/home/${MINI_LINUX_USER}"
CONFIG_HOME="${USER_HOME}/.config"

mkdir -p "${CONFIG_HOME}"

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

mkdir -p "${CONFIG_HOME}/gtk-4.0"
cat > "${CONFIG_HOME}/gtk-4.0/settings.ini" <<EOF
[Settings]
gtk-application-prefer-dark-theme=1
gtk-icon-theme-name=Papirus-Dark
gtk-cursor-theme-name=Adwaita
gtk-cursor-theme-size=24
gtk-font-name=Noto Sans 11
EOF

# --- GNOME dconf defaults ---
# Write a dconf keyfile so GNOME picks up defaults on first login
log_info "Configuring GNOME dconf defaults..."
mkdir -p "${ROOTFS}/etc/dconf/db/local.d"
cat > "${ROOTFS}/etc/dconf/db/local.d/01-mini-linux" <<'EOF'
[org/gnome/desktop/interface]
color-scheme='prefer-dark'
gtk-theme='Adwaita-dark'
icon-theme='Papirus-Dark'
cursor-theme='Adwaita'
cursor-size=24
font-name='Noto Sans 11'
document-font-name='Noto Sans 11'
monospace-font-name='JetBrainsMono Nerd Font 11'

[org/gnome/desktop/wm/preferences]
button-layout='appmenu:minimize,maximize,close'

[org/gnome/shell]
favorite-apps=['org.gnome.Nautilus.desktop', 'firefox.desktop', 'org.gnome.Console.desktop', 'org.gnome.Settings.desktop']

[org/gnome/desktop/background]
picture-options='none'
primary-color='#1e1e2e'

[org/gnome/desktop/screensaver]
picture-options='none'
primary-color='#1e1e2e'

[org/gnome/settings-daemon/plugins/power]
sleep-inactive-ac-timeout=3600
sleep-inactive-battery-timeout=900
power-button-action='suspend'

[org/gnome/desktop/input-sources]
sources=[('xkb', 'us')]

[org/gnome/desktop/peripherals/touchpad]
natural-scroll=true
tap-to-click=true
two-finger-scrolling-enabled=true
EOF

# Write dconf profile so the keyfile is picked up
mkdir -p "${ROOTFS}/etc/dconf/profile"
cat > "${ROOTFS}/etc/dconf/profile/user" <<'EOF'
user-db:user
system-db:local
EOF

# Compile the dconf database inside the chroot
log_info "Compiling dconf database..."
arch-chroot "${ROOTFS}" dconf update 2>/dev/null || \
    log_warn "dconf update skipped (dconf not yet available in rootfs — will apply on first boot)"

# Fix ownership using numeric UID/GID
USER_UID=$(grep "^${MINI_LINUX_USER}:" "${ROOTFS}/etc/passwd" | cut -d: -f3)
USER_GID=$(grep "^${MINI_LINUX_USER}:" "${ROOTFS}/etc/passwd" | cut -d: -f4)
if [[ -n "${USER_UID}" ]]; then
    chown -R "${USER_UID}:${USER_GID}" "${USER_HOME}"
else
    log_warn "Could not find UID for '${MINI_LINUX_USER}' — skipping chown"
fi

log_ok "GNOME desktop configured."
umount "${ROOTFS}" 2>/dev/null || true
trap - EXIT
