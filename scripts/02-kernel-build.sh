#!/usr/bin/env bash
# 02-kernel-build.sh — Compile the custom kernel and install to rootfs.
# Requires: kernel source downloaded and .config in place (run 01-kernel-config.sh first).

source "$(dirname "$0")/common.sh"
require_root

KERNEL_SRC="${BUILD_DIR}/linux-${KERNEL_VERSION}"
NPROC=$(nproc)

log_info "=== Kernel Build ==="

if [[ ! -f "${KERNEL_SRC}/.config" ]]; then
    log_error "No kernel .config found. Run 01-kernel-config.sh first."
    exit 1
fi

if [[ ! -d "${ROOTFS}/usr" ]]; then
    log_error "Rootfs not found at ${ROOTFS}. Run 00-bootstrap.sh first."
    exit 1
fi

cd "${KERNEL_SRC}"

# Use GCC 12 — GCC 13/14 default to C23 mode which breaks kernel 6.x builds
# (bool/false become keywords, conflicting with kernel typedefs)
KERNEL_CC="${KERNEL_CC:-gcc-12}"
if ! command -v "${KERNEL_CC}" &>/dev/null; then
    log_warn "${KERNEL_CC} not found, falling back to system gcc. Run 'make setup' to install gcc-12."
    KERNEL_CC="gcc"
fi
log_info "Using compiler: ${KERNEL_CC} ($(${KERNEL_CC} --version | head -1))"

# Compile kernel
log_info "Compiling kernel with ${NPROC} cores..."
make -j"${NPROC}" CC="${KERNEL_CC}"

# Install modules to rootfs
log_info "Installing kernel modules to rootfs..."
make modules_install INSTALL_MOD_PATH="${ROOTFS}"

# Install kernel image
log_info "Installing kernel image to rootfs..."
mkdir -p "${ROOTFS}/boot"
cp arch/x86/boot/bzImage "${ROOTFS}/boot/vmlinuz-mini-linux"
cp System.map "${ROOTFS}/boot/System.map-mini-linux"
cp .config "${ROOTFS}/boot/config-mini-linux"

log_ok "Kernel compiled and installed to rootfs."
log_info "Kernel image: ${ROOTFS}/boot/vmlinuz-mini-linux"
log_info "Modules: ${ROOTFS}/lib/modules/"
