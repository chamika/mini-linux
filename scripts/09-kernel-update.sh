#!/usr/bin/env bash
# 09-kernel-update.sh — Update the kernel on an already-installed NVMe without touching user data.
#
# Run this from Ubuntu after rebuilding the kernel with 'make kernel'.
# Only replaces: UKI, kernel image, initramfs, microcode (on ESP) and kernel modules (on NVMe root).
# All other files — /home, /etc, packages — are untouched.
#
# Usage:
#   make kernel-update
#   make kernel-update NVME_ROOT=/dev/nvme0n1p5   # specify partition directly

source "$(dirname "$0")/common.sh"
require_root

log_info "=== Kernel Update (NVMe) ==="

# --- Verify new kernel exists in rootfs ---
VMLINUZ="${ROOTFS}/boot/vmlinuz-mini-linux"
INITRAMFS="${ROOTFS}/boot/initramfs-mini-linux.img"
UKI="${ROOTFS}/boot/EFI/Linux/mini-linux.efi"

if [[ ! -f "${VMLINUZ}" ]]; then
    log_error "New kernel not found at ${VMLINUZ}."
    log_error "Run 'make kernel' first to build and install the kernel into the rootfs."
    exit 1
fi

if [[ ! -f "${INITRAMFS}" ]]; then
    log_error "New initramfs not found at ${INITRAMFS}."
    log_error "Run 'make boot-optimize' first to regenerate the initramfs."
    exit 1
fi

# --- Find the mini-linux NVMe root partition ---
if [[ -n "${NVME_ROOT:-}" ]]; then
    ROOT_PART="${NVME_ROOT}"
else
    log_info "Searching for mini-linux partition by label..."
    ROOT_PART=$(blkid -L mini-linux 2>/dev/null || true)
fi

if [[ -z "${ROOT_PART}" ]]; then
    log_info "Current NVMe layout:"
    lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT /dev/nvme0n1 2>/dev/null || lsblk
    echo ""
    read -rp "Enter mini-linux root partition (e.g. /dev/nvme0n1p5): " ROOT_PART
fi

if [[ ! -b "${ROOT_PART}" ]]; then
    log_error "Device ${ROOT_PART} not found."
    exit 1
fi

# Safety: refuse to touch the currently running root
CURRENT_ROOT=$(findmnt -n -o SOURCE /)
if [[ "${ROOT_PART}" == "${CURRENT_ROOT}" ]]; then
    log_error "That is the currently running root partition — aborting to prevent data loss."
    exit 1
fi

log_info "Target partition: ${ROOT_PART}"
log_info "Kernel:           ${VMLINUZ}"
log_info "Initramfs:        ${INITRAMFS}"
[[ -f "${UKI}" ]] && log_info "UKI:              ${UKI}"

# --- Find the shared ESP ---
ESP_MOUNT=""
for candidate in /boot/efi /boot/EFI /efi; do
    if mountpoint -q "$candidate" 2>/dev/null; then
        ESP_MOUNT="$candidate"
        break
    fi
done
if [[ -z "${ESP_MOUNT}" ]]; then
    ESP_MOUNT=$(findmnt -n -o TARGET -t vfat | head -1)
fi
if [[ -z "${ESP_MOUNT}" ]]; then
    log_error "Cannot find EFI System Partition. Make sure Ubuntu's ESP is mounted."
    exit 1
fi
log_info "ESP:              ${ESP_MOUNT}"

echo ""
log_warn "This will update the kernel files only. All user data is preserved."
read -rp "Continue? [y/N] " CONFIRM
if [[ "${CONFIRM,,}" != "y" ]]; then
    log_info "Aborted."
    exit 0
fi

# --- Update kernel modules on NVMe root ---
MNT="${BUILD_DIR}/nvme-update-mnt"
mkdir -p "${MNT}"
mount "${ROOT_PART}" "${MNT}"
trap 'umount "${MNT}" 2>/dev/null || true' EXIT

log_info "Syncing kernel modules to NVMe root partition..."
rsync -aAX --delete \
    "${ROOTFS}/lib/modules/" \
    "${MNT}/lib/modules/"
log_ok "Modules updated."

# --- Regenerate UKI with the installed system's root UUID ---
ROOT_UUID=$(blkid -s UUID -o value "${ROOT_PART}")
log_info "Regenerating UKI with root UUID ${ROOT_UUID}..."

# Update kernel cmdline on the installed system
mkdir -p "${MNT}/etc/kernel"
echo "root=UUID=${ROOT_UUID} rw quiet loglevel=3 rd.systemd.show_status=false rd.udev.log_level=3 nowatchdog nmi_watchdog=0 tsc=reliable" > "${MNT}/etc/kernel/cmdline"

# Copy new kernel to installed system
cp "${VMLINUZ}" "${MNT}/boot/vmlinuz-mini-linux"

# Regenerate initramfs + UKI in the installed system
mount --bind "${MNT}" "${MNT}"
arch-chroot "${MNT}" mkinitcpio -P || true
umount "${MNT}" 2>/dev/null  # undo inner bind mount

# --- Update UKI on ESP ---
UKI_INSTALLED="${MNT}/boot/EFI/Linux/mini-linux.efi"
if [[ -f "${UKI_INSTALLED}" ]]; then
    log_info "Copying UKI to ESP..."
    mkdir -p "${ESP_MOUNT}/EFI/Linux"
    cp "${UKI_INSTALLED}" "${ESP_MOUNT}/EFI/Linux/mini-linux.efi"
    log_ok "UKI updated on ESP."
else
    log_warn "UKI was not generated — updating traditional kernel files instead."
fi

# --- Always update traditional files as GRUB fallback ---
log_info "Copying kernel image to ESP..."
mkdir -p "${ESP_MOUNT}/EFI/mini-linux"
cp "${VMLINUZ}" "${ESP_MOUNT}/EFI/mini-linux/vmlinuz"
log_ok "Kernel image updated."

INITRAMFS_INSTALLED="${MNT}/boot/initramfs-mini-linux.img"
if [[ -f "${INITRAMFS_INSTALLED}" ]]; then
    log_info "Copying initramfs to ESP..."
    cp "${INITRAMFS_INSTALLED}" "${ESP_MOUNT}/EFI/mini-linux/initramfs.img"
    log_ok "Initramfs updated."
fi

if [[ -f "${MNT}/boot/intel-ucode.img" ]]; then
    log_info "Copying Intel microcode to ESP..."
    cp "${MNT}/boot/intel-ucode.img" "${ESP_MOUNT}/EFI/mini-linux/intel-ucode.img"
    log_ok "Microcode updated."
fi

umount "${MNT}"
trap - EXIT

log_ok "Kernel update complete!"
log_info ""
log_info "New kernel:   $(file "${VMLINUZ}" | grep -oP 'version \S+' || echo 'see above')"
log_info "ESP location: ${ESP_MOUNT}"
if [[ -f "${ESP_MOUNT}/EFI/Linux/mini-linux.efi" ]]; then
    log_info "UKI:          ${ESP_MOUNT}/EFI/Linux/mini-linux.efi"
    log_info ""
    log_info "Reboot — Mini-Linux will boot directly via UEFI (fastest path)."
    log_info "To boot Ubuntu, use your BIOS boot menu (F12)."
else
    log_info ""
    log_info "Reboot and select 'Mini-Linux' from the GRUB menu to boot the new kernel."
fi
