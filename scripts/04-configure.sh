#!/usr/bin/env bash
# 04-configure.sh — System configuration: locale, timezone, users, network, services. LightDM provides graphical login.

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
# Remove stale lock files from a previous interrupted run
rm -f "${ROOTFS}/etc/passwd.lock" "${ROOTFS}/etc/shadow.lock" \
      "${ROOTFS}/etc/group.lock"  "${ROOTFS}/etc/gshadow.lock"
# Create user — only primary group assignment; optional groups added below
chroot_run useradd -m -s /bin/bash "${MINI_LINUX_USER}" 2>/dev/null || \
    log_warn "useradd returned non-zero (user may already exist — continuing)"
# Add to optional groups only if they exist in the rootfs
for grp in wheel video audio input network bluetooth; do
    if chroot_run getent group "${grp}" &>/dev/null; then
        chroot_run usermod -aG "${grp}" "${MINI_LINUX_USER}" 2>/dev/null || true
    else
        log_warn "Group '${grp}' not found in rootfs — skipping"
    fi
done
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
chroot_run systemctl enable lightdm.service

# --- Mask unnecessary services ---
log_info "Masking unnecessary services..."
while IFS= read -r service; do
    [[ -z "$service" || "$service" == \#* ]] && continue
    log_info "  Masking: $service"
    chroot_run systemctl mask "$service" 2>/dev/null || true
done < "${CONFIG_DIR}/systemd/masked-services.list"

# --- XDG user directories ---
chroot_run su - "${MINI_LINUX_USER}" -c "xdg-user-dirs-update" 2>/dev/null || true

# Fix home directory ownership
USER_UID=$(grep "^${MINI_LINUX_USER}:" "${ROOTFS}/etc/passwd" | cut -d: -f3)
USER_GID=$(grep "^${MINI_LINUX_USER}:" "${ROOTFS}/etc/passwd" | cut -d: -f4)
if [[ -n "${USER_UID}" ]]; then
    chown -R "${USER_UID}:${USER_GID}" "${ROOTFS}/home/${MINI_LINUX_USER}"
else
    log_warn "Could not find UID for '${MINI_LINUX_USER}' in rootfs passwd — skipping chown"
fi

log_ok "System configuration complete."

umount "${ROOTFS}" 2>/dev/null || true
trap - EXIT
