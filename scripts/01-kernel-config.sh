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

if [[ -f "${PREBUILT_CONFIG}" && $(wc -l < "${PREBUILT_CONFIG}") -gt 10 ]]; then
    log_info "Using pre-built kernel config from ${PREBUILT_CONFIG}"
    cp "${PREBUILT_CONFIG}" .config
    make olddefconfig
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
    make localmodconfig

    # Apply XPS 13 specific tweaks
    log_info "Applying XPS 13 optimizations..."

    # Build boot-critical drivers into kernel (not modules)
    ./scripts/config --enable CONFIG_NVME_CORE
    ./scripts/config --enable CONFIG_BLK_DEV_NVME
    ./scripts/config --enable CONFIG_DRM_I915
    ./scripts/config --enable CONFIG_EXT4_FS

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

    # Performance tuning
    ./scripts/config --disable CONFIG_DEBUG_INFO
    ./scripts/config --disable CONFIG_DEBUG_KERNEL
    ./scripts/config --enable CONFIG_CC_OPTIMIZE_FOR_PERFORMANCE

    # Disable watchdog (saves ~0.5s boot)
    ./scripts/config --disable CONFIG_WATCHDOG

    make olddefconfig

    # Save the generated config back to the project
    cp .config "${PREBUILT_CONFIG}"
    log_ok "Kernel config generated and saved to ${PREBUILT_CONFIG}"
    log_info "Review with: make menuconfig (in ${KERNEL_SRC})"
fi

log_ok "Kernel config ready at ${KERNEL_SRC}/.config"
