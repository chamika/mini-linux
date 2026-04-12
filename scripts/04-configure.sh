#!/usr/bin/env bash
# 04-configure.sh — System configuration: locale, timezone, users, network, services.

source "$(dirname "$0")/common.sh"
require_root

log_info "=== System Configuration ==="

if [[ ! -d "${ROOTFS}/usr" ]]; then
    log_error "Rootfs not found. Run 00-bootstrap.sh first."
    exit 1
fi

# Bind-mount rootfs onto itself so arch-chroot sees it as a real mountpoint
mount --bind "${ROOTFS}" "${ROOTFS}"
trap 'umount "${ROOTFS}" 2>/dev/null || true' EXIT

# --- Timezone ---
log_info "Setting timezone to UTC (change in config if needed)..."
chroot_run ln -sf /usr/share/zoneinfo/UTC /etc/localtime
chroot_run hwclock --systohc

# --- Locale ---
log_info "Setting locale to en_US.UTF-8..."
echo "en_US.UTF-8 UTF-8" > "${ROOTFS}/etc/locale.gen"
chroot_run locale-gen
echo "LANG=en_US.UTF-8" > "${ROOTFS}/etc/locale.conf"

# --- Hostname ---
log_info "Setting hostname to ${MINI_LINUX_HOSTNAME}..."
echo "${MINI_LINUX_HOSTNAME}" > "${ROOTFS}/etc/hostname"
cat > "${ROOTFS}/etc/hosts" <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${MINI_LINUX_HOSTNAME}.localdomain ${MINI_LINUX_HOSTNAME}
EOF

# --- User account ---
log_info "Creating user '${MINI_LINUX_USER}'..."
chroot_run useradd -m -G wheel,video,audio,input,network,bluetooth -s /bin/bash "${MINI_LINUX_USER}" 2>/dev/null || true
# Set password by writing the hash directly — chpasswd fails via PAM in a foreign-arch chroot
HASHED_PW=$(openssl passwd -6 "${MINI_LINUX_USER}")
sed -i "s|^${MINI_LINUX_USER}:[^:]*:|${MINI_LINUX_USER}:${HASHED_PW}:|" "${ROOTFS}/etc/shadow"
log_warn "Default password is '${MINI_LINUX_USER}'. Change it on first boot!"

# Enable wheel group in sudoers
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' "${ROOTFS}/etc/sudoers"

# --- Enable services ---
log_info "Enabling system services..."
chroot_run systemctl enable NetworkManager.service
chroot_run systemctl enable bluetooth.service
chroot_run systemctl enable tlp.service
chroot_run systemctl enable nftables.service
chroot_run systemctl enable systemd-timesyncd.service

# --- Mask unnecessary services ---
log_info "Masking unnecessary services..."
while IFS= read -r service; do
    [[ -z "$service" || "$service" == \#* ]] && continue
    log_info "  Masking: $service"
    chroot_run systemctl mask "$service" 2>/dev/null || true
done < "${CONFIG_DIR}/systemd/masked-services.list"

# --- Autologin on TTY1 ---
log_info "Configuring autologin for '${MINI_LINUX_USER}' on TTY1..."
mkdir -p "${ROOTFS}/etc/systemd/system/getty@tty1.service.d"
sed "s/MINI_LINUX_USER/${MINI_LINUX_USER}/g" \
    "${CONFIG_DIR}/systemd/getty-autologin.conf" \
    > "${ROOTFS}/etc/systemd/system/getty@tty1.service.d/autologin.conf"

# --- Auto-start Hyprland ---
log_info "Configuring Hyprland auto-start..."
BASH_PROFILE="${ROOTFS}/home/${MINI_LINUX_USER}/.bash_profile"
mkdir -p "${ROOTFS}/home/${MINI_LINUX_USER}"
cat > "${BASH_PROFILE}" <<'EOF'
# Auto-start Hyprland on TTY1
if [ -z "$WAYLAND_DISPLAY" ] && [ "$XDG_VTNR" -eq 1 ]; then
    exec Hyprland
fi
EOF
chroot_run chown -R "${MINI_LINUX_USER}:${MINI_LINUX_USER}" "/home/${MINI_LINUX_USER}"

# --- XDG user directories ---
chroot_run su - "${MINI_LINUX_USER}" -c "xdg-user-dirs-update" 2>/dev/null || true

log_ok "System configuration complete."

umount "${ROOTFS}"
trap - EXIT
