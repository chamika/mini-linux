#!/usr/bin/env bash
# 07-build-usb-image.sh — Package the rootfs into a bootable USB image.
# Creates a GPT disk image with EFI + root partitions, installs GRUB for UEFI boot.

source "$(dirname "$0")/common.sh"
require_root
require_command parted
require_command mkfs.fat
require_command mkfs.ext4

IMAGE_SIZE="${IMAGE_SIZE:-8G}"
IMAGE_FILE="${BUILD_DIR}/mini-linux.img"
MNT="${BUILD_DIR}/mnt"

log_info "=== USB Image Builder ==="
log_info "Image size: ${IMAGE_SIZE}"
log_info "Image file: ${IMAGE_FILE}"

if [[ ! -d "${ROOTFS}/usr" ]]; then
    log_error "Rootfs not found. Run previous build steps first."
    exit 1
fi

# Pre-flight: verify rootfs fits in the image
# Layout: 1MiB gap + 512MiB EFI + rest for root → root ≈ IMAGE_SIZE - 513MiB
IMAGE_BYTES=$(numfmt --from=iec "${IMAGE_SIZE}")
EFI_BYTES=$(( 513 * 1024 * 1024 ))
ROOT_AVAIL=$(( IMAGE_BYTES - EFI_BYTES ))
ROOTFS_BYTES=$(du -sb "${ROOTFS}" | cut -f1)
# Add 10% headroom for filesystem overhead
ROOTFS_NEEDED=$(( ROOTFS_BYTES * 11 / 10 ))
if (( ROOTFS_NEEDED > ROOT_AVAIL )); then
    NEEDED_GIB=$(numfmt --to=iec ${ROOTFS_NEEDED})
    log_error "Rootfs (${NEEDED_GIB} with overhead) exceeds root partition space."
    log_error "Increase IMAGE_SIZE or reduce packages. Try: make usb-image IMAGE_SIZE=10G"
    exit 1
fi
log_info "Size check passed: rootfs $(numfmt --to=iec ${ROOTFS_BYTES}), root partition $(numfmt --to=iec ${ROOT_AVAIL}) available."

# Clean up from previous runs
[[ -d "${MNT}" ]] && umount -R "${MNT}" 2>/dev/null || true

# Create sparse image
log_info "Creating disk image..."
truncate -s "${IMAGE_SIZE}" "${IMAGE_FILE}"

# Partition: GPT with EFI (512MB) + root (rest)
log_info "Partitioning image..."
parted -s "${IMAGE_FILE}" \
    mklabel gpt \
    mkpart ESP fat32 1MiB 513MiB \
    set 1 esp on \
    mkpart root ext4 513MiB 100%

# Set up loop device
LOOP=$(losetup --find --show --partscan "${IMAGE_FILE}")
log_info "Loop device: ${LOOP}"

# Ensure partition devices appear
sleep 1
partprobe "${LOOP}" 2>/dev/null || true

EFI_PART="${LOOP}p1"
ROOT_PART="${LOOP}p2"

# Cleanup trap
cleanup() {
    log_info "Cleaning up..."
    umount -R "${MNT}" 2>/dev/null || true
    losetup -d "${LOOP}" 2>/dev/null || true
}
trap cleanup EXIT

# Format partitions
log_info "Formatting partitions..."
mkfs.fat -F 32 -n MINI_EFI "${EFI_PART}"
mkfs.ext4 -L mini-linux -q "${ROOT_PART}"

# Mount
log_info "Mounting partitions..."
mkdir -p "${MNT}"
mount "${ROOT_PART}" "${MNT}"
mkdir -p "${MNT}/boot/efi"
mount "${EFI_PART}" "${MNT}/boot/efi"

# Copy rootfs
log_info "Copying rootfs to image (this may take a few minutes)..."
rsync -aAX --info=progress2 "${ROOTFS}/" "${MNT}/"

# Generate fstab
log_info "Generating fstab..."
ROOT_UUID=$(blkid -s UUID -o value "${ROOT_PART}")
EFI_UUID=$(blkid -s UUID -o value "${EFI_PART}")

cat > "${MNT}/etc/fstab" <<EOF
# /etc/fstab — Mini-Linux (USB)
UUID=${ROOT_UUID}   /           ext4    defaults,noatime,commit=60  0 1
UUID=${EFI_UUID}    /boot/efi   vfat    defaults,umask=0077         0 2
tmpfs               /tmp        tmpfs   defaults,noatime,mode=1777,size=2G  0 0
EOF

# Install GRUB for UEFI
log_info "Installing GRUB bootloader..."
# Ensure grub is installed in the rootfs
if [[ ! -f "${MNT}/usr/bin/grub-install" ]]; then
    arch-chroot "${MNT}" pacman -S --noconfirm grub efibootmgr
fi

arch-chroot "${MNT}" grub-install \
    --target=x86_64-efi \
    --efi-directory=/boot/efi \
    --boot-directory=/boot \
    --removable

# Configure GRUB
cat > "${MNT}/etc/default/grub" <<EOF
GRUB_DEFAULT=0
GRUB_TIMEOUT=0
GRUB_DISTRIBUTOR="Mini-Linux"
GRUB_CMDLINE_LINUX_DEFAULT="quiet loglevel=3 rd.systemd.show_status=false rd.udev.log_level=3 nowatchdog nmi_watchdog=0 tsc=reliable"
GRUB_CMDLINE_LINUX=""
GRUB_GFXMODE=auto
GRUB_GFXPAYLOAD_LINUX=keep
EOF

arch-chroot "${MNT}" grub-mkconfig -o /boot/grub/grub.cfg

# Unmount (trap will handle cleanup)
log_info "Unmounting..."
umount -R "${MNT}"
losetup -d "${LOOP}"
trap - EXIT

# Copy image to project build directory
mkdir -p "${PROJECT_ROOT}/build"
cp "${IMAGE_FILE}" "${PROJECT_ROOT}/build/mini-linux.img"

log_ok "USB image created: build/mini-linux.img"
log_info "Flash to USB:"
log_info "  sudo dd if=build/mini-linux.img of=/dev/sdX bs=4M status=progress"
log_info ""
log_info "Find your USB device with: lsblk"
