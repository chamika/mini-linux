#!/usr/bin/env bash
# 01-kernel-config.sh — Generate or install a custom kernel config for XPS 13 9380.
# If running on the target hardware, generates config from loaded modules.
# Otherwise, copies the pre-built config from config/kernel/.

source "$(dirname "$0")/common.sh"
require_root

KERNEL_SRC="${BUILD_DIR}/linux-${KERNEL_VERSION}"
KERNEL_TARBALL="linux-${KERNEL_VERSION}.tar.xz"
KERNEL_URL="https://cdn.kernel.org/pub/linux/kernel/v6.x/${KERNEL_TARBALL}"
PREBUILT_CONFIG="${CONFIG_DIR}/kernel/xps13-9380.config"

log_info "=== Kernel Configuration ==="

# Download kernel source if not present
if [[ ! -d "${KERNEL_SRC}" ]]; then
    log_info "Downloading Linux ${KERNEL_VERSION} source..."
    mkdir -p "${BUILD_DIR}"
    cd "${BUILD_DIR}"
    if [[ ! -f "${KERNEL_TARBALL}" ]]; then
        wget -q --show-progress "${KERNEL_URL}"
    fi
    log_info "Extracting kernel source..."
    tar xf "${KERNEL_TARBALL}"
fi

cd "${KERNEL_SRC}"

# Use GCC 12 — GCC 13/14 default to C23 mode which breaks kernel 6.x builds
KERNEL_CC="${KERNEL_CC:-gcc-12}"
if ! command -v "${KERNEL_CC}" &>/dev/null; then
    log_warn "${KERNEL_CC} not found, falling back to system gcc."
    KERNEL_CC="gcc"
fi

if [[ -f "${PREBUILT_CONFIG}" && $(wc -l < "${PREBUILT_CONFIG}") -gt 10 ]]; then
    log_info "Using pre-built kernel config from ${PREBUILT_CONFIG}"
    cp "${PREBUILT_CONFIG}" .config
    # Clear Ubuntu host-specific certificate paths before olddefconfig can inherit them
    ./scripts/config --set-str CONFIG_SYSTEM_TRUSTED_KEYS ""
    ./scripts/config --set-str CONFIG_SYSTEM_REVOCATION_KEYS ""
    make CC="${KERNEL_CC}" olddefconfig
    log_ok "Kernel config installed from pre-built config."
else
    log_warn "No pre-built config found. Generating from running system..."
    log_info "Ensure you are running this on the Dell XPS 13 9380 with all hardware active."

    # Start from current running kernel config
    if [[ -f /proc/config.gz ]]; then
        zcat /proc/config.gz > .config
    elif [[ -f "/boot/config-$(uname -r)" ]]; then
        cp "/boot/config-$(uname -r)" .config
    else
        log_error "Cannot find running kernel config. Run on the target machine."
        exit 1
    fi

    # Strip to only loaded modules
    log_info "Running localmodconfig (stripping to loaded modules)..."
    log_warn "Make sure WiFi, Bluetooth, audio, camera, and USB devices are connected/active!"
    yes "" | make CC="${KERNEL_CC}" localmodconfig

    # Apply XPS 13 specific tweaks
    log_info "Applying XPS 13 optimizations..."

    # CPU family — Intel Core 2/newer (Whiskey Lake)
    ./scripts/config --set-val CONFIG_MCORE2 y
    ./scripts/config --set-val CONFIG_GENERIC_CPU n

    # No 5-level paging — Whiskey Lake does not support it
    ./scripts/config --disable CONFIG_X86_5LEVEL

    # zswap — use zstd compressor and zsmalloc allocator
    ./scripts/config --enable CONFIG_ZSWAP
    ./scripts/config --set-str CONFIG_ZSWAP_COMPRESSOR_DEFAULT "zstd"
    ./scripts/config --set-str CONFIG_ZSWAP_ZPOOL_DEFAULT "zsmalloc"
    ./scripts/config --disable CONFIG_ZBUD
    ./scripts/config --disable CONFIG_Z3FOLD_DEPRECATED

    # Crypto modules required by systemd in initramfs (mkinitcpio systemd hook)
    # Built-in (not module) so initramfs doesn't need to load it
    ./scripts/config --enable CONFIG_CRYPTO_LZ4

    # Build boot-critical drivers into kernel (not modules)
    # This shrinks the initramfs and eliminates module-load time during boot
    ./scripts/config --enable CONFIG_NVME_CORE
    ./scripts/config --enable CONFIG_BLK_DEV_NVME
    ./scripts/config --enable CONFIG_DRM_I915
    ./scripts/config --enable CONFIG_EXT4_FS

    # HID subsystem built-in — needed for USB keyboard during early boot
    ./scripts/config --enable CONFIG_HID
    ./scripts/config --enable CONFIG_HID_GENERIC
    ./scripts/config --enable CONFIG_USB_HID

    # Disable unnecessary subsystems
    ./scripts/config --disable CONFIG_DRM_NOUVEAU
    ./scripts/config --disable CONFIG_DRM_AMDGPU
    ./scripts/config --disable CONFIG_DRM_RADEON
    ./scripts/config --disable CONFIG_SCSI_LOWLEVEL
    ./scripts/config --disable CONFIG_INFINIBAND
    ./scripts/config --disable CONFIG_ISDN
    ./scripts/config --disable CONFIG_HAMRADIO
    ./scripts/config --disable CONFIG_CAN
    ./scripts/config --disable CONFIG_WLAN_VENDOR_REALTEK
    ./scripts/config --disable CONFIG_WLAN_VENDOR_BROADCOM
    ./scripts/config --disable CONFIG_WLAN_VENDOR_ATHEROS
    ./scripts/config --disable CONFIG_WLAN_VENDOR_MEDIATEK
    # XPS 13 9380 has Intel Wireless-AC 9560 — iwlwifi + mvm required
    ./scripts/config --enable CONFIG_WLAN_VENDOR_INTEL
    ./scripts/config --module CONFIG_IWLWIFI
    ./scripts/config --module CONFIG_IWLMVM
    ./scripts/config --enable CONFIG_IWLWIFI_LEDS
    ./scripts/config --enable CONFIG_CFG80211
    ./scripts/config --enable CONFIG_MAC80211

    # Disable legacy / irrelevant hardware
    ./scripts/config --disable CONFIG_EISA
    ./scripts/config --disable CONFIG_IP_DCCP
    ./scripts/config --disable CONFIG_NF_CT_PROTO_DCCP
    ./scripts/config --disable CONFIG_CDROM_PKTCDVD
    ./scripts/config --disable CONFIG_TI_ST
    ./scripts/config --disable CONFIG_ECHO
    ./scripts/config --disable CONFIG_INPUT_EVBUG
    ./scripts/config --disable CONFIG_KEYBOARD_ADP5589
    ./scripts/config --disable CONFIG_SERIAL_KGDB_NMI
    ./scripts/config --disable CONFIG_SENSORS_OXP
    ./scripts/config --disable CONFIG_MFD_PCF50633
    ./scripts/config --disable CONFIG_DRM_I2C_CH7006
    ./scripts/config --disable CONFIG_DRM_I2C_SIL164
    ./scripts/config --disable CONFIG_SND_SOC_IMG
    ./scripts/config --disable CONFIG_MEMORY_HOTPLUG_DEFAULT_ONLINE

    # Clear Ubuntu-specific certificate paths that don't exist in vanilla source
    ./scripts/config --set-str CONFIG_SYSTEM_TRUSTED_KEYS ""
    ./scripts/config --set-str CONFIG_SYSTEM_REVOCATION_KEYS ""

    # Performance tuning
    ./scripts/config --disable CONFIG_DEBUG_INFO
    ./scripts/config --disable CONFIG_DEBUG_KERNEL
    ./scripts/config --enable CONFIG_CC_OPTIMIZE_FOR_PERFORMANCE

    # Kernel compression — lz4 decompresses ~2x faster than zstd at boot
    ./scripts/config --disable CONFIG_KERNEL_ZSTD
    ./scripts/config --enable CONFIG_KERNEL_LZ4

    # Built-in kernel command line (fallback if bootloader doesn't provide one)
    ./scripts/config --enable CONFIG_CMDLINE_BOOL
    ./scripts/config --set-str CONFIG_CMDLINE "quiet loglevel=3 nowatchdog nmi_watchdog=0 tsc=reliable"
    ./scripts/config --disable CONFIG_CMDLINE_OVERRIDE

    # Disable watchdog (saves ~0.5s boot)
    ./scripts/config --disable CONFIG_WATCHDOG

    # Disable btrfs — not used on this system, avoids crypto_lz4 dep issue in initramfs
    ./scripts/config --disable CONFIG_BTRFS_FS

    make CC="${KERNEL_CC}" olddefconfig

    # Save the generated config back to the project
    cp .config "${PREBUILT_CONFIG}"
    log_ok "Kernel config generated and saved to ${PREBUILT_CONFIG}"
    log_info "Review with: make menuconfig (in ${KERNEL_SRC})"
fi

log_ok "Kernel config ready at ${KERNEL_SRC}/.config"
