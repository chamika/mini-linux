#!/usr/bin/env bash
# setup-host.sh — Install Arch Linux tools (pacman, pacstrap) on Ubuntu.
# Run this ONCE before 'make all'. Must be run as root.

source "$(dirname "$0")/common.sh"
require_root

log_info "=== Setting up Ubuntu host for mini-linux builds ==="

# Check we're on Ubuntu/Debian
if ! command -v apt &>/dev/null; then
    log_error "This script is for Ubuntu/Debian hosts only."
    log_info "On Arch Linux, pacstrap is already available — skip this step."
    exit 1
fi

log_info "Installing build dependencies..."
apt update -qq
apt install -y \
    arch-install-scripts \
    dosfstools \
    e2fsprogs \
    parted \
    rsync \
    wget \
    curl \
    squashfs-tools \
    grub-efi-amd64-bin \
    grub-pc-bin \
    mtools \
    qemu-utils \
    binfmt-support \
    qemu-user-static \
    zstd \
    flex \
    bison \
    bc \
    libelf-dev \
    libssl-dev \
    build-essential \
    gcc-12 \
    g++-12

# pacman is not in Ubuntu repos — install from upstream
if ! command -v pacman &>/dev/null; then
    log_info "Installing pacman from Ubuntu repos or building from source..."

    # Try the AUR-like approach: install from a PPA or build
    # The cleanest method on Ubuntu 22.04+ is the 'pacman-package-manager' PPA
    # Fallback: download a static pacman or build from source

    PACMAN_BUILD_DIR=$(mktemp -d)
    cd "$PACMAN_BUILD_DIR"

    log_info "Downloading and building pacman from source..."
    apt install -y \
        meson \
        ninja-build \
        cmake \
        pkg-config \
        libarchive-dev \
        libcurl4-openssl-dev \
        libgpgme-dev \
        libssl-dev \
        python3 \
        doxygen \
        asciidoc \
        gettext \
        libarchive-tools \
        fakeroot \
        fakechroot

    PACMAN_VER="7.0.0"
    wget -q "https://gitlab.archlinux.org/pacman/pacman/-/releases/v${PACMAN_VER}/downloads/pacman-${PACMAN_VER}.tar.xz" \
        -O "pacman-${PACMAN_VER}.tar.xz" || {
        # Fallback URL
        wget -q "https://sources.archlinux.org/other/pacman/pacman-${PACMAN_VER}.tar.xz" \
            -O "pacman-${PACMAN_VER}.tar.xz"
    }

    tar xf "pacman-${PACMAN_VER}.tar.xz"
    cd "pacman-${PACMAN_VER}"

    mkdir build && cd build
    meson setup .. \
        --prefix=/usr \
        --buildtype=release \
        -Ddoc=disabled \
        -Dscriptlet-shell=/usr/bin/bash \
        -Dldconfig=/usr/bin/ldconfig
    ninja
    ninja install

    cd /
    rm -rf "$PACMAN_BUILD_DIR"

    log_ok "pacman installed successfully."
else
    log_ok "pacman already installed."
fi

install_arch_keyring() {
    local keyring_dir="/usr/share/pacman/keyrings"
    local mirror_url="https://mirrors.kernel.org/archlinux/core/os/x86_64/"
    local tmpdir package_name

    if [[ -f "${keyring_dir}/archlinux.gpg" ]]; then
        log_ok "Arch Linux keyring already installed."
        return
    fi

    log_info "Installing Arch Linux keyring files..."
    tmpdir=$(mktemp -d)

    package_name=$(curl -fsSL "${mirror_url}" \
        | grep -oE 'archlinux-keyring-[^"]+-any\.pkg\.tar\.zst' \
        | sort -V \
        | tail -n1)

    if [[ -z "${package_name}" ]]; then
        rm -rf "${tmpdir}"
        log_error "Unable to determine the latest archlinux-keyring package."
        exit 1
    fi

    curl -fsSL "${mirror_url}${package_name}" -o "${tmpdir}/${package_name}"
    mkdir -p "${keyring_dir}" "${tmpdir}/extract"
    tar --zstd -xf "${tmpdir}/${package_name}" -C "${tmpdir}/extract" usr/share/pacman/keyrings
    cp "${tmpdir}/extract/usr/share/pacman/keyrings/archlinux"* "${keyring_dir}/"
    rm -rf "${tmpdir}"

    log_ok "Arch Linux keyring files installed."
}

# Set up pacman for Arch Linux repos
log_info "Configuring pacman for Arch Linux repositories..."
mkdir -p /etc/pacman.d

if ! grep -q "^\[core\]" /etc/pacman.conf 2>/dev/null; then
    cat > /etc/pacman.conf <<'EOF'
[options]
HoldPkg     = pacman glibc
Architecture = x86_64
SigLevel    = Required DatabaseOptional
LocalFileSigLevel = Optional

[core]
Server = https://mirrors.kernel.org/archlinux/$repo/os/$arch

[extra]
Server = https://mirrors.kernel.org/archlinux/$repo/os/$arch
EOF
    log_ok "pacman.conf created."
fi

install_arch_keyring

# Initialize pacman keyring
log_info "Initializing pacman keyring (this may take a minute)..."
pacman-key --init
pacman-key --populate archlinux

# Sync package databases
log_info "Syncing pacman package databases..."
pacman -Sy --noconfirm

log_ok "Host setup complete!"
log_info ""
log_info "You can now run: make all"
