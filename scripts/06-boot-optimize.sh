#!/usr/bin/env bash
# 06-boot-optimize.sh — Apply boot time optimizations to rootfs.
# Generates a Unified Kernel Image (UKI) that bundles kernel + initramfs +
# cmdline + microcode into a single .efi binary for near-instant boot.

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

# Install systemd-ukify for Unified Kernel Image generation
log_info "Installing systemd-ukify for UKI generation..."
chroot_run pacman -S --noconfirm --needed systemd-ukify

# --- Initramfs + UKI ---
log_info "Installing optimized mkinitcpio.conf..."
cp "${CONFIG_DIR}/mkinitcpio.conf" "${ROOTFS}/etc/mkinitcpio.conf"

# --- Kernel command line (used by UKI and bootloader) ---
log_info "Writing kernel command line..."
mkdir -p "${ROOTFS}/etc/kernel"
# ROOTFS_UUID is a placeholder — replaced at install time (08-install-to-nvme.sh)
# or at image build time (07-build-usb-image.sh) with the real UUID.
CMDLINE="root=UUID=ROOTFS_UUID rw quiet loglevel=3 rd.systemd.show_status=false rd.udev.log_level=3 nowatchdog nmi_watchdog=0 tsc=reliable"
echo "${CMDLINE}" > "${ROOTFS}/etc/kernel/cmdline"

# Create a mkinitcpio preset that generates both a traditional initramfs
# and a Unified Kernel Image (.efi). The UKI bundles:
#   - kernel (vmlinuz)
#   - initramfs
#   - kernel command line (/etc/kernel/cmdline)
#   - CPU microcode (intel-ucode, if present)
# into a single EFI-bootable binary — no separate initrd loading phase.
log_info "Creating mkinitcpio preset for UKI..."
mkdir -p "${ROOTFS}/etc/mkinitcpio.d"
cat > "${ROOTFS}/etc/mkinitcpio.d/mini-linux.preset" <<'EOF'
ALL_config="/etc/mkinitcpio.conf"
ALL_kver="/boot/vmlinuz-mini-linux"

# Embed Intel microcode into the UKI
ALL_microcode=(/boot/*-ucode.img)

PRESETS=('default')

# Traditional initramfs (fallback for GRUB dual-boot)
default_config="/etc/mkinitcpio.conf"
default_image="/boot/initramfs-mini-linux.img"
default_options=""

# Unified Kernel Image — single .efi file for direct UEFI/systemd-boot
default_uki="/boot/EFI/Linux/mini-linux.efi"
default_options="--cmdline /etc/kernel/cmdline"
EOF

# Ensure UKI output directory exists
mkdir -p "${ROOTFS}/boot/EFI/Linux"

# Regenerate initramfs + UKI
log_info "Regenerating initramfs and UKI..."
chroot_run mkinitcpio -P || true

# Verify outputs
if [[ ! -f "${ROOTFS}/boot/initramfs-mini-linux.img" ]]; then
    log_error "initramfs was not created — mkinitcpio failed fatally."
    exit 1
fi
log_info "initramfs created successfully."

if [[ -f "${ROOTFS}/boot/EFI/Linux/mini-linux.efi" ]]; then
    UKI_SIZE=$(du -h "${ROOTFS}/boot/EFI/Linux/mini-linux.efi" | cut -f1)
    log_ok "UKI created: /boot/EFI/Linux/mini-linux.efi (${UKI_SIZE})"
else
    log_warn "UKI was not created — systemd-ukify may have failed."
    log_warn "Falling back to traditional initramfs boot (still works, but slower)."
fi

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
log_info "Expected boot timeline (NVMe with UKI + systemd-boot):"
log_info "  UEFI POST → systemd-boot → UKI (kernel+initrd) → Userspace → GNOME"
log_info "  ~11s        ~0s             ~1.5s                  ~3.5s      = ~16s"
log_info "  (UEFI POST time varies by BIOS settings; enable Fast Boot in BIOS to reduce it)"

umount "${ROOTFS}" 2>/dev/null || true
trap - EXIT
