#!/usr/bin/env bash
# 06-boot-optimize.sh — Apply boot time optimizations to rootfs.

source "$(dirname "$0")/common.sh"
require_root

log_info "=== Boot Optimization ==="

if [[ ! -d "${ROOTFS}/usr" ]]; then
    log_error "Rootfs not found. Run previous scripts first."
    exit 1
fi

# Bind-mount rootfs so arch-chroot sees it as a real mountpoint
mount --bind "${ROOTFS}" "${ROOTFS}"
trap 'umount "${ROOTFS}" 2>/dev/null || true' EXIT

# Ensure mkinitcpio is present (may be missing if bootstrap ran before mirror was configured)
if ! chroot_run bash -c "command -v mkinitcpio" &>/dev/null; then
    log_info "mkinitcpio not found — installing..."
    chroot_run pacman -S --noconfirm --needed mkinitcpio
fi

# --- Initramfs ---
log_info "Installing optimized mkinitcpio.conf..."
cp "${CONFIG_DIR}/mkinitcpio.conf" "${ROOTFS}/etc/mkinitcpio.conf"

# Create a preset for our custom kernel (no Arch 'linux' package = no preset file)
log_info "Creating mkinitcpio preset for custom kernel..."
mkdir -p "${ROOTFS}/etc/mkinitcpio.d"
cat > "${ROOTFS}/etc/mkinitcpio.d/mini-linux.preset" <<EOF
ALL_config="/etc/mkinitcpio.conf"
ALL_kver="/boot/vmlinuz-mini-linux"

PRESETS=('default')

default_config="/etc/mkinitcpio.conf"
default_image="/boot/initramfs-mini-linux.img"
default_options=""
EOF

# Regenerate initramfs with minimal config
log_info "Regenerating initramfs..."
chroot_run mkinitcpio -P || true
# Verify initramfs was actually produced
if [[ ! -f "${ROOTFS}/boot/initramfs-mini-linux.img" ]]; then
    log_error "initramfs was not created — mkinitcpio failed fatally."
    exit 1
fi
log_info "initramfs created successfully (module warnings above are non-fatal)."

# --- Kernel command line (stored for bootloader config) ---
log_info "Writing kernel command line..."
mkdir -p "${ROOTFS}/etc/kernel"
CMDLINE="root=UUID=ROOTFS_UUID rw quiet loglevel=3 rd.systemd.show_status=false rd.udev.log_level=3 nowatchdog nmi_watchdog=0 tsc=reliable"
echo "${CMDLINE}" > "${ROOTFS}/etc/kernel/cmdline"

# --- Filesystem optimizations ---
log_info "Configuring filesystem optimizations..."

# NVMe scheduler — none is optimal for NVMe
mkdir -p "${ROOTFS}/etc/udev/rules.d"
cat > "${ROOTFS}/etc/udev/rules.d/60-iosched.rules" <<'EOF'
# Set NVMe scheduler to none (no-op) — NVMe has its own internal scheduling
ACTION=="add|change", KERNEL=="nvme[0-9]*", ATTR{queue/scheduler}="none"
EOF

# --- Tmpfiles — mount /tmp as tmpfs ---
log_info "Configuring /tmp as tmpfs..."
if ! grep -q "tmpfs.*/tmp" "${ROOTFS}/etc/fstab" 2>/dev/null; then
    cat >> "${ROOTFS}/etc/fstab" <<EOF

# tmpfs for /tmp — faster than disk, cleared on reboot
tmpfs   /tmp    tmpfs   defaults,noatime,mode=1777,size=2G  0 0
EOF
fi

# --- Disable core dumps (faster, saves disk) ---
mkdir -p "${ROOTFS}/etc/systemd/coredump.conf.d"
cat > "${ROOTFS}/etc/systemd/coredump.conf.d/disable.conf" <<EOF
[Coredump]
Storage=none
ProcessSizeMax=0
EOF

# --- Journal size limit ---
mkdir -p "${ROOTFS}/etc/systemd/journald.conf.d"
cat > "${ROOTFS}/etc/systemd/journald.conf.d/size.conf" <<EOF
[Journal]
SystemMaxUse=50M
RuntimeMaxUse=20M
EOF

log_ok "Boot optimizations applied."
log_info "Expected boot timeline:"
log_info "  UEFI POST → GRUB → Kernel → systemd → GNOME"
log_info "  ~0.5s       ~1s    ~1.5s    ~2.5s     ~1s = ~6.5s"

umount "${ROOTFS}" 2>/dev/null || true
trap - EXIT
