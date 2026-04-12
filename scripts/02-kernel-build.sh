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

# Compile kernel
log_info "Compiling kernel with ${NPROC} cores..."
make -j"${NPROC}"

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
