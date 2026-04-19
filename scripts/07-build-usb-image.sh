#!/usr/bin/env bash
# 07-build-usb-image.sh — Package the rootfs into a bootable USB image.
# Uses systemd-boot + Unified Kernel Image (UKI) for near-zero bootloader overhead.

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

# --- Write the real kernel command line with the actual root UUID ---
log_info "Writing kernel command line with root UUID..."
mkdir -p "${MNT}/etc/kernel"
echo "root=UUID=${ROOT_UUID} rw quiet loglevel=3 rd.systemd.show_status=false rd.udev.log_level=3 nowatchdog nmi_watchdog=0 tsc=reliable" > "${MNT}/etc/kernel/cmdline"

# --- Regenerate UKI with the real root UUID baked in ---
log_info "Regenerating UKI with correct root UUID..."
mount --bind "${MNT}" "${MNT}"
arch-chroot "${MNT}" mkinitcpio -P || true
umount "${MNT}" 2>/dev/null  # undo the inner bind mount

UKI_PATH="${MNT}/boot/EFI/Linux/mini-linux.efi"

# --- Install systemd-boot (replaces GRUB — near-zero overhead) ---
if [[ -f "${UKI_PATH}" ]]; then
    log_info "Installing systemd-boot to ESP..."
    # systemd-boot auto-discovers UKI files in EFI/Linux/
    mkdir -p "${MNT}/boot/efi/EFI/Linux"
    mkdir -p "${MNT}/boot/efi/EFI/BOOT"
    mkdir -p "${MNT}/boot/efi/loader"

    # Copy UKI to the ESP where systemd-boot will find it
    cp "${UKI_PATH}" "${MNT}/boot/efi/EFI/Linux/mini-linux.efi"

    # Install systemd-boot EFI binaries
    # The bootloader binary goes to EFI/BOOT/BOOTX64.EFI for removable media
    if [[ -f "${MNT}/usr/lib/systemd/boot/efi/systemd-bootx64.efi" ]]; then
        cp "${MNT}/usr/lib/systemd/boot/efi/systemd-bootx64.efi" \
           "${MNT}/boot/efi/EFI/BOOT/BOOTX64.EFI"
    else
        log_warn "systemd-boot EFI binary not found — falling back to bootctl install"
        mount --bind "${MNT}" "${MNT}"
        arch-chroot "${MNT}" bootctl install --esp-path=/boot/efi 2>/dev/null || true
        umount "${MNT}" 2>/dev/null
    fi

    # Minimal loader.conf — timeout 0 means boot immediately
    cat > "${MNT}/boot/efi/loader/loader.conf" <<EOF
timeout 0
console-mode auto
EOF

    log_ok "systemd-boot installed with UKI."
else
    # Fallback: UKI generation failed, use GRUB with traditional initramfs
    log_warn "UKI not found — falling back to GRUB bootloader."

    if [[ ! -f "${MNT}/usr/bin/grub-install" ]]; then
        log_info "grub not found — installing..."
        mount --bind "${MNT}" "${MNT}"
        arch-chroot "${MNT}" pacman -S --noconfirm grub efibootmgr
        umount "${MNT}"
    fi

    grub-install \
        --target=x86_64-efi \
        --efi-directory="${MNT}/boot/efi" \
        --boot-directory="${MNT}/boot" \
        --removable \
        --no-nvram

    log_info "Writing GRUB config..."
    mkdir -p "${MNT}/boot/grub"
    cat > "${MNT}/boot/grub/grub.cfg" <<EOF
set default=0
set timeout=0

menuentry "Mini-Linux" {
    search --no-floppy --label --set=root mini-linux
    linux   /boot/vmlinuz-mini-linux root=LABEL=mini-linux rw quiet loglevel=3 rd.systemd.show_status=false rd.udev.log_level=3 nowatchdog nmi_watchdog=0 tsc=reliable
    initrd  /boot/initramfs-mini-linux.img
}
EOF
fi

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
