#!/usr/bin/env bash
# 08-install-to-nvme.sh — Install mini-linux to NVMe alongside Ubuntu.
# This script:
#   1. Formats the target partitions (root + swap)
#   2. Copies the rootfs
#   3. Installs kernel + initramfs to the shared ESP
#   4. Adds a GRUB entry for dual-boot
#
# REQUIRES: Unallocated partitions already created (use GParted or fdisk beforehand).
# Run this from Ubuntu.

source "$(dirname "$0")/common.sh"
require_root

log_info "=== Mini-Linux NVMe Installer ==="
log_warn "This will FORMAT the target partitions. Data on them will be destroyed."
echo ""

if [[ ! -d "${ROOTFS}/usr" ]]; then
    log_error "Rootfs not found at ${ROOTFS}. Run the build pipeline first (make all)."
    exit 1
fi

# --- Show current partitions ---
log_info "Current NVMe partitions:"
lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT,LABEL /dev/nvme0n1
echo ""

# --- Prompt for target partitions ---
read -rp "Root partition (e.g., /dev/nvme0n1p5): " ROOT_PART
read -rp "Swap partition (e.g., /dev/nvme0n1p6, or 'none' to skip): " SWAP_PART

if [[ -z "$ROOT_PART" ]]; then
    log_error "Root partition is required."
    exit 1
fi

if [[ ! -b "$ROOT_PART" ]]; then
    log_error "Device ${ROOT_PART} does not exist."
    exit 1
fi

# Safety check — don't format Ubuntu's partitions
UBUNTU_ROOT=$(findmnt -n -o SOURCE /)
if [[ "$ROOT_PART" == "$UBUNTU_ROOT" ]]; then
    log_error "That's your current Ubuntu root partition! Aborting."
    exit 1
fi

echo ""
log_warn "About to format:"
log_warn "  Root: ${ROOT_PART} (ext4)"
[[ "$SWAP_PART" != "none" && -n "$SWAP_PART" ]] && log_warn "  Swap: ${SWAP_PART}"
echo ""
read -rp "Type 'yes' to continue: " CONFIRM
if [[ "$CONFIRM" != "yes" ]]; then
    log_info "Aborted."
    exit 0
fi

# --- Format partitions ---
log_info "Formatting root partition..."
mkfs.ext4 -L mini-linux -q "$ROOT_PART"

if [[ "$SWAP_PART" != "none" && -n "$SWAP_PART" ]]; then
    log_info "Formatting swap partition..."
    mkswap -L mini-swap "$SWAP_PART"
fi

# --- Mount and copy rootfs ---
MNT="${BUILD_DIR}/nvme-mnt"
mkdir -p "$MNT"
mount "$ROOT_PART" "$MNT"

# Cleanup trap
cleanup() {
    log_info "Cleaning up mounts..."
    umount -R "$MNT" 2>/dev/null || true
}
trap cleanup EXIT

log_info "Copying rootfs to NVMe (this may take several minutes)..."
rsync -aAX --info=progress2 "${ROOTFS}/" "${MNT}/"

# --- Generate fstab ---
ROOT_UUID=$(blkid -s UUID -o value "$ROOT_PART")
log_info "Root UUID: ${ROOT_UUID}"

# Find the existing ESP
ESP_MOUNT=""
for candidate in /boot/efi /boot/EFI /efi; do
    if mountpoint -q "$candidate" 2>/dev/null; then
        ESP_MOUNT="$candidate"
        break
    fi
done

if [[ -z "$ESP_MOUNT" ]]; then
    ESP_MOUNT=$(findmnt -n -o TARGET -t vfat | head -1)
fi

if [[ -z "$ESP_MOUNT" ]]; then
    log_error "Cannot find EFI System Partition. Is Ubuntu using UEFI?"
    exit 1
fi

ESP_DEV=$(findmnt -n -o SOURCE "$ESP_MOUNT")
ESP_UUID=$(blkid -s UUID -o value "$ESP_DEV")
log_info "ESP UUID: ${ESP_UUID} (mounted at ${ESP_MOUNT})"

cat > "${MNT}/etc/fstab" <<EOF
# /etc/fstab — Mini-Linux (installed to NVMe)
UUID=${ROOT_UUID}   /           ext4    defaults,noatime,commit=60  0 1
UUID=${ESP_UUID}    /boot/efi   vfat    defaults,umask=0077         0 2
tmpfs               /tmp        tmpfs   defaults,noatime,mode=1777,size=2G  0 0
EOF

if [[ "$SWAP_PART" != "none" && -n "$SWAP_PART" ]]; then
    SWAP_UUID=$(blkid -s UUID -o value "$SWAP_PART")
    echo "UUID=${SWAP_UUID}   none        swap    defaults                    0 0" >> "${MNT}/etc/fstab"
fi

# --- Install kernel + initramfs to shared ESP ---
log_info "Installing kernel to shared ESP..."
mkdir -p "${ESP_MOUNT}/EFI/mini-linux"
cp "${MNT}/boot/vmlinuz-mini-linux" "${ESP_MOUNT}/EFI/mini-linux/vmlinuz"

# Copy initramfs (try different naming conventions)
for initrd_name in initramfs-linux.img initramfs-mini-linux.img; do
    if [[ -f "${MNT}/boot/${initrd_name}" ]]; then
        cp "${MNT}/boot/${initrd_name}" "${ESP_MOUNT}/EFI/mini-linux/initramfs.img"
        break
    fi
done

# Copy Intel microcode
if [[ -f "${MNT}/boot/intel-ucode.img" ]]; then
    cp "${MNT}/boot/intel-ucode.img" "${ESP_MOUNT}/EFI/mini-linux/intel-ucode.img"
fi

# --- Add GRUB entry ---
log_info "Adding GRUB entry for dual-boot..."
GRUB_CUSTOM="/etc/grub.d/40_custom"

# Check if entry already exists and remove old one
if grep -q "Mini-Linux" "$GRUB_CUSTOM" 2>/dev/null; then
    log_warn "GRUB entry for Mini-Linux already exists. Updating..."
    sed -i '/# --- Mini-Linux START ---/,/# --- Mini-Linux END ---/d' "$GRUB_CUSTOM"
fi

cat >> "$GRUB_CUSTOM" <<EOF

# --- Mini-Linux START ---
menuentry "Mini-Linux" --class arch --class gnu-linux --class os {
    search --no-floppy --label --set=root mini-linux
    linux   /boot/vmlinuz-mini-linux root=LABEL=mini-linux rw quiet loglevel=3 rd.systemd.show_status=false rd.udev.log_level=3 nowatchdog nmi_watchdog=0 tsc=reliable
    initrd  /boot/intel-ucode.img /boot/initramfs-mini-linux.img
}
# --- Mini-Linux END ---
EOF

# --- Reduce GRUB timeout ---
# Ubuntu's GRUB defaults to 5s. Reduce to 1s so Mini-Linux boots faster.
# This is still long enough to select Ubuntu if needed.
log_info "Reducing GRUB timeout to 1 second..."
GRUB_DEFAULT_CFG="/etc/default/grub"
if [[ -f "${GRUB_DEFAULT_CFG}" ]]; then
    CURRENT_TIMEOUT=$(grep -oP '(?<=GRUB_TIMEOUT=)\S+' "${GRUB_DEFAULT_CFG}" || echo "5")
    if [[ "${CURRENT_TIMEOUT}" -gt 1 ]] 2>/dev/null; then
        sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=1/' "${GRUB_DEFAULT_CFG}"
        log_ok "GRUB_TIMEOUT reduced from ${CURRENT_TIMEOUT}s → 1s (saves ~${CURRENT_TIMEOUT}s per boot)."
    else
        log_info "GRUB_TIMEOUT is already ${CURRENT_TIMEOUT}s — no change needed."
    fi
else
    log_warn "/etc/default/grub not found — skipping timeout reduction."
fi

# Regenerate GRUB config
log_info "Regenerating GRUB config..."
update-grub

# --- Cleanup ---
umount -R "$MNT"
trap - EXIT

log_ok "Mini-Linux installed to NVMe!"
log_info ""
log_info "  Root partition: ${ROOT_PART} (UUID: ${ROOT_UUID})"
log_info "  Kernel at: ${ESP_MOUNT}/EFI/mini-linux/vmlinuz"
log_info "  GRUB entry added — select 'Mini-Linux' at boot menu"
log_info ""
log_info "Reboot and select 'Mini-Linux' from the GRUB menu to test."
log_info "Default password: ${MINI_LINUX_USER} (change with 'passwd' after login)"
