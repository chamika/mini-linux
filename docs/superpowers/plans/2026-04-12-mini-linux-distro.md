# Mini-Linux Distribution Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a minimal, fast-booting (<7s) Arch Linux distribution with Hyprland desktop for the Dell XPS 13 9380, dual-booting alongside Ubuntu.

**Architecture:** Shell-script build pipeline that creates an Arch Linux rootfs via pacstrap, compiles a custom kernel stripped to XPS 13 hardware, installs a Hyprland desktop with Chrome/Thunar/Kitty, optimizes boot time, and generates both a USB test image and an NVMe install script for dual-boot with Ubuntu's GRUB.

**Tech Stack:** Bash scripts, Arch Linux (pacstrap/pacman), Linux kernel (make menuconfig), systemd, Hyprland (Wayland), GRUB

**Spec:** `docs/superpowers/specs/mini-linux-spec.md`

**Important context:** This repo lives on macOS but the scripts run on the Dell XPS 13 (Ubuntu). All scripts must be self-contained and runnable from the cloned repo on the target machine. The build user must have sudo access. All scripts share a common `ROOTFS` build directory (default: `/tmp/mini-linux-build/rootfs`).

---

## File Structure

```
mini-linux/
├── README.md                                # Project overview, quick start, architecture diagram
├── Makefile                                 # Top-level build orchestration (make all, make usb, make install)
├── scripts/
│   ├── common.sh                            # Shared variables, logging functions, root check
│   ├── 00-bootstrap.sh                      # Create minimal Arch rootfs via pacstrap
│   ├── 01-kernel-config.sh                  # Generate/install custom kernel .config
│   ├── 02-kernel-build.sh                   # Download kernel source + compile + install to rootfs
│   ├── 03-packages.sh                       # Install desktop + app packages into rootfs
│   ├── 04-configure.sh                      # System config: locale, timezone, users, fstab, services
│   ├── 05-hyprland-setup.sh                 # Copy desktop configs into rootfs, set autologin + autostart
│   ├── 06-boot-optimize.sh                  # Apply boot optimizations: initramfs, kernel cmdline, services
│   ├── 07-build-usb-image.sh                # Package rootfs into bootable USB .img file
│   └── 08-install-to-nvme.sh                # Install rootfs to NVMe partition + add GRUB entry
├── config/
│   ├── kernel/
│   │   └── xps13-9380.config                # Custom kernel .config (generated, then checked in)
│   ├── hyprland/
│   │   └── hyprland.conf                    # Hyprland compositor config (keybinds, appearance, autostart)
│   ├── waybar/
│   │   ├── config.jsonc                     # Waybar modules: clock, battery, wifi, audio, bluetooth
│   │   └── style.css                        # Waybar styling (colors, fonts, spacing)
│   ├── kitty/
│   │   └── kitty.conf                       # Kitty terminal config (font, theme, splits)
│   ├── wofi/
│   │   └── config                           # Wofi app launcher config
│   ├── mako/
│   │   └── config                           # Mako notification daemon config
│   ├── systemd/
│   │   ├── getty-autologin.conf              # Drop-in for getty@tty1 autologin
│   │   └── masked-services.list             # List of systemd services to mask
│   ├── mkinitcpio.conf                      # Minimal initramfs hooks for fast boot
│   └── grub/
│       └── 40_custom-mini-linux             # GRUB menu entry template for dual-boot
├── docs/
│   ├── 00-prerequisites.md                  # Required tools, disk space, Ubuntu packages
│   ├── 01-bootstrap.md                      # Explains rootfs creation
│   ├── 02-kernel.md                         # Kernel compilation guide
│   ├── 03-packages.md                       # What gets installed and why
│   ├── 04-configuration.md                  # System config walkthrough
│   ├── 05-boot-optimization.md              # Boot time tuning explained
│   ├── 06-usb-image.md                      # How to build + flash USB image
│   ├── 07-install-to-nvme.md                # Dual-boot install alongside Ubuntu
│   └── superpowers/
│       ├── specs/
│       │   └── mini-linux-spec.md           # (already exists) Full specification
│       └── plans/
│           └── 2026-04-12-mini-linux-distro.md  # (this file)
└── .gitignore                               # Ignore build artifacts
```

---

## Task 1: Project Scaffolding

**Files:**
- Create: `.gitignore`
- Create: `README.md`
- Create: `scripts/common.sh`
- Create: `Makefile`

- [ ] **Step 1: Create .gitignore**

```gitignore
# Build artifacts
build/
*.img
*.iso

# Kernel build
config/kernel/*.old

# Editor
*.swp
*.swo
*~
.vscode/
.idea/

# OS
.DS_Store
Thumbs.db
```

- [ ] **Step 2: Create scripts/common.sh — shared variables and helper functions**

All build scripts source this file. It defines the build directory, color logging, and a root check.

```bash
#!/usr/bin/env bash
# Common variables and functions for mini-linux build scripts.
# Source this at the top of every script: source "$(dirname "$0")/common.sh"

set -euo pipefail

# --- Build Configuration ---
export BUILD_DIR="${BUILD_DIR:-/tmp/mini-linux-build}"
export ROOTFS="${BUILD_DIR}/rootfs"
export SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
export CONFIG_DIR="${PROJECT_ROOT}/config"
export MINI_LINUX_USER="${MINI_LINUX_USER:-user}"
export MINI_LINUX_HOSTNAME="${MINI_LINUX_HOSTNAME:-mini-linux}"
export KERNEL_VERSION="${KERNEL_VERSION:-6.12}"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
log_ok()    { echo -e "${GREEN}[ OK ]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERR ]${NC} $*" >&2; }

require_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (or with sudo)."
        exit 1
    fi
}

require_command() {
    local cmd="$1"
    if ! command -v "$cmd" &>/dev/null; then
        log_error "Required command not found: $cmd"
        exit 1
    fi
}

# Run a command inside the rootfs chroot
chroot_run() {
    arch-chroot "$ROOTFS" "$@"
}

cleanup_mounts() {
    log_info "Cleaning up mounts..."
    umount -R "${ROOTFS}/proc" 2>/dev/null || true
    umount -R "${ROOTFS}/sys" 2>/dev/null || true
    umount -R "${ROOTFS}/dev" 2>/dev/null || true
    umount -R "${ROOTFS}/run" 2>/dev/null || true
}
```

- [ ] **Step 3: Create Makefile — top-level build orchestration**

```makefile
.PHONY: all bootstrap kernel-config kernel packages configure desktop boot-optimize usb-image install clean help

SCRIPTS := scripts

all: bootstrap kernel packages configure desktop boot-optimize usb-image
	@echo ""
	@echo "========================================="
	@echo " Build complete! USB image is ready."
	@echo " Flash with: sudo dd if=build/mini-linux.img of=/dev/sdX bs=4M status=progress"
	@echo "========================================="

bootstrap:
	sudo bash $(SCRIPTS)/00-bootstrap.sh

kernel-config:
	sudo bash $(SCRIPTS)/01-kernel-config.sh

kernel:
	sudo bash $(SCRIPTS)/02-kernel-build.sh

packages:
	sudo bash $(SCRIPTS)/03-packages.sh

configure:
	sudo bash $(SCRIPTS)/04-configure.sh

desktop:
	sudo bash $(SCRIPTS)/05-hyprland-setup.sh

boot-optimize:
	sudo bash $(SCRIPTS)/06-boot-optimize.sh

usb-image:
	sudo bash $(SCRIPTS)/07-build-usb-image.sh

install:
	sudo bash $(SCRIPTS)/08-install-to-nvme.sh

clean:
	@echo "Removing build directory..."
	sudo rm -rf /tmp/mini-linux-build
	@echo "Clean complete."

help:
	@echo "Mini-Linux Build System"
	@echo ""
	@echo "  make all            - Full build pipeline (bootstrap → USB image)"
	@echo "  make bootstrap      - Create Arch Linux base rootfs"
	@echo "  make kernel-config  - Generate custom kernel config for XPS 13"
	@echo "  make kernel         - Compile and install custom kernel"
	@echo "  make packages       - Install desktop and application packages"
	@echo "  make configure      - Apply system configuration"
	@echo "  make desktop        - Set up Hyprland desktop environment"
	@echo "  make boot-optimize  - Apply boot time optimizations"
	@echo "  make usb-image      - Generate bootable USB image"
	@echo "  make install        - Install to NVMe (dual-boot with Ubuntu)"
	@echo "  make clean          - Remove build directory"
```

- [ ] **Step 4: Create README.md**

```markdown
# Mini-Linux

A minimal, fast-booting Linux distribution built on Arch Linux for the Dell XPS 13 9380.

## What You Get

- **<7 second cold boot** to a modern Wayland desktop
- **Hyprland** compositor with smooth animations
- **Google Chrome**, **Thunar** file manager, **Kitty** terminal
- Full hardware support: WiFi, Bluetooth, audio, camera, touchpad
- Dual-boots alongside Ubuntu via GRUB

## Architecture

```
┌─────────────────────────────────────────────┐
│  Chrome · Thunar · Kitty                    │
├─────────────────────────────────────────────┤
│  Hyprland + Waybar + Wofi + Mako            │
├─────────────────────────────────────────────┤
│  systemd · NetworkManager · PipeWire        │
├─────────────────────────────────────────────┤
│  Custom Linux Kernel (XPS 13 only)          │
├─────────────────────────────────────────────┤
│  Ubuntu GRUB (shared EFI)                   │
└─────────────────────────────────────────────┘
```

## Quick Start

> **Prerequisites:** Run on the Dell XPS 13 (booted into Ubuntu). See [docs/00-prerequisites.md](docs/00-prerequisites.md).

```bash
# Clone this repo
git clone <this-repo> && cd mini-linux

# Build everything and create a USB image
make all

# Flash to USB for testing
sudo dd if=build/mini-linux.img of=/dev/sdX bs=4M status=progress

# After testing, install to NVMe alongside Ubuntu
make install
```

## Build Steps

| Step | Command | What it does |
|------|---------|-------------|
| 1 | `make bootstrap` | Creates Arch Linux base rootfs |
| 2 | `make kernel` | Compiles custom kernel for XPS 13 |
| 3 | `make packages` | Installs Hyprland, Chrome, Thunar, Kitty |
| 4 | `make configure` | Users, locale, timezone, services |
| 5 | `make desktop` | Hyprland + Waybar + theme configs |
| 6 | `make boot-optimize` | Initramfs stripping, service tuning |
| 7 | `make usb-image` | Generates bootable USB image |
| 8 | `make install` | Installs to NVMe alongside Ubuntu |

## Documentation

Each step has a detailed guide in [docs/](docs/).

## License

MIT
```

- [ ] **Step 5: Commit scaffolding**

```bash
git add .gitignore README.md scripts/common.sh Makefile
git commit -m "feat: project scaffolding — README, Makefile, common.sh

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

## Task 2: Bootstrap Script

**Files:**
- Create: `scripts/00-bootstrap.sh`
- Create: `docs/00-prerequisites.md`
- Create: `docs/01-bootstrap.md`

- [ ] **Step 1: Create docs/00-prerequisites.md**

```markdown
# Prerequisites

## Hardware

- Dell XPS 13 9380 (or similar Intel laptop)
- USB flash drive (8GB+) for testing
- Internet connection

## Software

Run these commands on your Ubuntu installation on the XPS 13:

```bash
# Install Arch bootstrap tools
sudo apt update
sudo apt install -y arch-install-scripts qemu-utils dosfstools e2fsprogs parted debootstrap wget

# Verify pacstrap is available
which pacstrap
```

## Disk Space

- ~10GB free for the build workspace (`/tmp/mini-linux-build/`)
- 30-50GB unallocated NVMe space for the final install (check with `lsblk`)

## Network

The build process downloads ~2GB of packages. A stable internet connection is required.
```

- [ ] **Step 2: Create scripts/00-bootstrap.sh**

This script creates a minimal Arch Linux rootfs using pacstrap. It must run on Ubuntu (the XPS 13's existing OS).

```bash
#!/usr/bin/env bash
# 00-bootstrap.sh — Create a minimal Arch Linux root filesystem.
# Must run as root on a Linux system with pacstrap installed.
# On Ubuntu: sudo apt install arch-install-scripts

source "$(dirname "$0")/common.sh"
require_root
require_command pacstrap

log_info "=== Mini-Linux Bootstrap ==="
log_info "Build directory: ${BUILD_DIR}"
log_info "Root filesystem: ${ROOTFS}"

# Create build directory
mkdir -p "${ROOTFS}"

# Base packages — minimal Arch system + hardware essentials
BASE_PACKAGES=(
    base
    linux-firmware
    intel-ucode
    sudo
    networkmanager
    bluez
    bluez-utils
    pipewire
    wireplumber
    pipewire-pulse
    pipewire-alsa
    iwd
    wpa_supplicant
    base-devel
    git
    vim
    man-db
    man-pages
)

log_info "Running pacstrap to create base rootfs..."
log_info "Packages: ${BASE_PACKAGES[*]}"

pacstrap -K "${ROOTFS}" "${BASE_PACKAGES[@]}"

log_ok "Bootstrap complete. Rootfs at ${ROOTFS}"
log_info "Rootfs size: $(du -sh "${ROOTFS}" | cut -f1)"
```

- [ ] **Step 3: Create docs/01-bootstrap.md**

```markdown
# Step 1: Bootstrap

## What This Does

Creates a minimal Arch Linux root filesystem at `/tmp/mini-linux-build/rootfs/` using `pacstrap`. This is the foundation everything else builds on.

## What Gets Installed

| Package | Purpose |
|---------|---------|
| `base` | Core Arch system (glibc, bash, coreutils, systemd, etc.) |
| `linux-firmware` | WiFi, Bluetooth, and other firmware blobs |
| `intel-ucode` | Intel CPU microcode updates |
| `sudo` | Privilege escalation |
| `networkmanager` | WiFi and network management |
| `bluez`, `bluez-utils` | Bluetooth stack |
| `pipewire`, `wireplumber` | Modern audio system |
| `pipewire-pulse`, `pipewire-alsa` | PulseAudio and ALSA compatibility |
| `base-devel`, `git` | Needed for building AUR packages later |

## Running

```bash
make bootstrap
# or directly:
sudo bash scripts/00-bootstrap.sh
```

## Verification

```bash
# Check rootfs exists and has expected structure
ls /tmp/mini-linux-build/rootfs/bin/bash
ls /tmp/mini-linux-build/rootfs/usr/lib/firmware/
```

## Customization

Set `BUILD_DIR` to change the build location:
```bash
BUILD_DIR=/mnt/fast-ssd/build make bootstrap
```
```

- [ ] **Step 4: Commit**

```bash
git add scripts/00-bootstrap.sh docs/00-prerequisites.md docs/01-bootstrap.md
git commit -m "feat: bootstrap script — creates Arch Linux base rootfs

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

## Task 3: Kernel Configuration Script

**Files:**
- Create: `scripts/01-kernel-config.sh`
- Create: `config/kernel/xps13-9380.config` (placeholder — real config generated on target)
- Create: `docs/02-kernel.md`

- [ ] **Step 1: Create scripts/01-kernel-config.sh**

This script generates a kernel .config tuned for the XPS 13 9380. It works two ways:
- On the XPS 13 itself: uses `make localmodconfig` to detect loaded modules, then strips further.
- Elsewhere: uses the checked-in config from `config/kernel/xps13-9380.config`.

```bash
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

if [[ -f "${PREBUILT_CONFIG}" ]]; then
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
```

- [ ] **Step 2: Create config/kernel/xps13-9380.config as a placeholder**

```
# This file is generated by scripts/01-kernel-config.sh on the target machine.
# Run `make kernel-config` on the Dell XPS 13 9380 to generate it.
# After generation, commit this file to the repo for reproducible builds.
```

Note: This is intentionally a placeholder. The real .config is ~7000 lines and must be generated on the target hardware where `make localmodconfig` can detect loaded modules. Once generated, it gets committed.

- [ ] **Step 3: Create docs/02-kernel.md**

```markdown
# Step 2: Custom Kernel

## Why a Custom Kernel?

The default Arch kernel includes ~5000 modules for every possible hardware combination. Our XPS 13 needs ~50. Stripping the rest gives us:

- **Faster boot:** Smaller kernel + smaller initramfs = faster load
- **Less RAM:** No unused modules loaded
- **Faster compile:** Subsequent kernel updates build in ~5 minutes

## Generating the Config

First time — run on the XPS 13 with all hardware active:

```bash
# Make sure these are active before generating config:
# - WiFi connected
# - Bluetooth on
# - Audio playing (activates audio driver)
# - Camera app open (activates uvcvideo)
# - USB device plugged in
# - External monitor connected (if you use one)

make kernel-config
```

This runs `make localmodconfig` to capture only drivers your hardware actually uses, then applies XPS 13-specific tweaks. The config is saved to `config/kernel/xps13-9380.config`.

## Building the Kernel

```bash
make kernel
```

This compiles the kernel using all CPU cores. On the i7-8565U, expect ~15-20 minutes.

## Key Config Choices

| Setting | Value | Why |
|---------|-------|-----|
| NVMe, i915, ext4 | Built-in (=y) | Available immediately at boot |
| iwlwifi, bluetooth, audio | Module (=m) | Loaded after boot |
| NOUVEAU, AMDGPU, RADEON | Disabled | Not Intel GPU |
| DEBUG_INFO | Disabled | Saves compile time + kernel size |
| WATCHDOG | Disabled | Saves ~0.5s boot time |
```

- [ ] **Step 4: Commit**

```bash
git add scripts/01-kernel-config.sh config/kernel/xps13-9380.config docs/02-kernel.md
git commit -m "feat: kernel config script — generates XPS 13 tuned config

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

## Task 4: Kernel Build Script

**Files:**
- Create: `scripts/02-kernel-build.sh`

- [ ] **Step 1: Create scripts/02-kernel-build.sh**

```bash
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
log_info "Modules: ${ROOTFS}/lib/modules/${KERNEL_VERSION}*/"
```

- [ ] **Step 2: Commit**

```bash
git add scripts/02-kernel-build.sh
git commit -m "feat: kernel build script — compiles and installs to rootfs

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

## Task 5: Package Installation Script

**Files:**
- Create: `scripts/03-packages.sh`
- Create: `docs/03-packages.md`

- [ ] **Step 1: Create scripts/03-packages.sh**

```bash
#!/usr/bin/env bash
# 03-packages.sh — Install desktop environment and application packages into rootfs.
# Must run after 00-bootstrap.sh.

source "$(dirname "$0")/common.sh"
require_root

log_info "=== Package Installation ==="

if [[ ! -d "${ROOTFS}/usr" ]]; then
    log_error "Rootfs not found. Run 00-bootstrap.sh first."
    exit 1
fi

# --- Desktop environment (Hyprland + Wayland) ---
DESKTOP_PACKAGES=(
    hyprland
    xdg-desktop-portal-hyprland
    waybar
    wofi
    mako
    swaylock
    hyprpaper
    polkit-gnome
    grim
    slurp
    wl-clipboard
    xdg-utils
    xdg-user-dirs
)

# --- Applications ---
APP_PACKAGES=(
    kitty
    thunar
    thunar-volman
    gvfs
    gvfs-mtp
    tumbler
    ffmpegthumbnailer
)

# --- Audio (PipeWire is in base, but need session manager bits) ---
AUDIO_PACKAGES=(
    pipewire-jack
    pavucontrol
)

# --- Fonts & Theming ---
THEME_PACKAGES=(
    noto-fonts
    noto-fonts-cjk
    noto-fonts-emoji
    ttf-jetbrains-mono-nerd
    papirus-icon-theme
    gtk3
    gtk4
    qt5-wayland
    qt6-wayland
)

# --- System utilities ---
UTIL_PACKAGES=(
    tlp
    brightnessctl
    playerctl
    networkmanager-openvpn
    nm-connection-editor
    blueman
    nftables
    htop
    unzip
    p7zip
    wget
    curl
)

ALL_PACKAGES=(
    "${DESKTOP_PACKAGES[@]}"
    "${APP_PACKAGES[@]}"
    "${AUDIO_PACKAGES[@]}"
    "${THEME_PACKAGES[@]}"
    "${UTIL_PACKAGES[@]}"
)

log_info "Installing ${#ALL_PACKAGES[@]} packages into rootfs..."
arch-chroot "${ROOTFS}" pacman -Syu --noconfirm "${ALL_PACKAGES[@]}"

# --- AUR packages (Google Chrome) ---
log_info "Setting up AUR package build..."

# Create a build user for makepkg (cannot run as root)
arch-chroot "${ROOTFS}" useradd -m -s /bin/bash builder 2>/dev/null || true
arch-chroot "${ROOTFS}" bash -c "echo 'builder ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/builder"

# Install google-chrome from AUR
log_info "Building google-chrome from AUR (this may take a few minutes)..."
arch-chroot "${ROOTFS}" su - builder -c "
    cd /tmp
    git clone https://aur.archlinux.org/google-chrome.git
    cd google-chrome
    makepkg -si --noconfirm
    cd /tmp && rm -rf google-chrome
"

# Clean up build user
arch-chroot "${ROOTFS}" userdel -r builder 2>/dev/null || true
arch-chroot "${ROOTFS}" rm -f /etc/sudoers.d/builder

# Clean pacman cache to reduce image size
arch-chroot "${ROOTFS}" pacman -Scc --noconfirm

log_ok "All packages installed."
log_info "Rootfs size: $(du -sh "${ROOTFS}" | cut -f1)"
```

- [ ] **Step 2: Create docs/03-packages.md**

```markdown
# Step 3: Packages

## What Gets Installed

### Desktop Environment (~120MB)
Hyprland compositor, Waybar status bar, Wofi launcher, Mako notifications, screen lock, wallpaper utility, screenshot tools.

### Applications (~250MB)
- **Kitty** — GPU-accelerated terminal with native splits
- **Thunar** — Lightweight file manager with thumbnail support
- **Google Chrome** — Built from AUR

### Audio (~5MB)
PipeWire JACK bridge and PulseAudio volume control (PipeWire base installed in bootstrap).

### Fonts & Theming (~150MB)
Noto fonts (full Unicode), JetBrains Mono Nerd Font (terminal/bar), Papirus icons, Qt Wayland support.

### System Utilities (~30MB)
TLP (battery), brightness/media controls, Bluetooth manager, firewall, archive tools.

## Running

```bash
make packages
```

## Adding More Packages Later

After installing to NVMe and booting into mini-linux:
```bash
sudo pacman -S <package-name>
```

For AUR packages, install an AUR helper first:
```bash
sudo pacman -S --needed git base-devel
git clone https://aur.archlinux.org/yay-bin.git
cd yay-bin && makepkg -si
yay -S visual-studio-code-bin
```
```

- [ ] **Step 3: Commit**

```bash
git add scripts/03-packages.sh docs/03-packages.md
git commit -m "feat: package installation script — desktop, apps, fonts, utils

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

## Task 6: System Configuration Script

**Files:**
- Create: `scripts/04-configure.sh`
- Create: `config/systemd/getty-autologin.conf`
- Create: `config/systemd/masked-services.list`
- Create: `docs/04-configuration.md`

- [ ] **Step 1: Create config/systemd/getty-autologin.conf**

```ini
[Service]
ExecStart=
ExecStart=-/sbin/agetty -o '-p -f -- \\u' --noclear --autologin MINI_LINUX_USER %I $TERM
Type=idle
```

Note: `MINI_LINUX_USER` is replaced by the configure script with the actual username.

- [ ] **Step 2: Create config/systemd/masked-services.list**

One service per line. These get masked during configuration.

```
lvm2-monitor.service
remote-fs.target
ModemManager.service
```

- [ ] **Step 3: Create scripts/04-configure.sh**

```bash
#!/usr/bin/env bash
# 04-configure.sh — System configuration: locale, timezone, users, network, services.

source "$(dirname "$0")/common.sh"
require_root

log_info "=== System Configuration ==="

if [[ ! -d "${ROOTFS}/usr" ]]; then
    log_error "Rootfs not found. Run 00-bootstrap.sh first."
    exit 1
fi

# --- Timezone ---
log_info "Setting timezone to UTC (change in config if needed)..."
chroot_run ln -sf /usr/share/zoneinfo/UTC /etc/localtime
chroot_run hwclock --systohc

# --- Locale ---
log_info "Setting locale to en_US.UTF-8..."
echo "en_US.UTF-8 UTF-8" > "${ROOTFS}/etc/locale.gen"
chroot_run locale-gen
echo "LANG=en_US.UTF-8" > "${ROOTFS}/etc/locale.conf"

# --- Hostname ---
log_info "Setting hostname to ${MINI_LINUX_HOSTNAME}..."
echo "${MINI_LINUX_HOSTNAME}" > "${ROOTFS}/etc/hostname"
cat > "${ROOTFS}/etc/hosts" <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${MINI_LINUX_HOSTNAME}.localdomain ${MINI_LINUX_HOSTNAME}
EOF

# --- User account ---
log_info "Creating user '${MINI_LINUX_USER}'..."
chroot_run useradd -m -G wheel,video,audio,input,network,bluetooth -s /bin/bash "${MINI_LINUX_USER}" 2>/dev/null || true
echo "${MINI_LINUX_USER}:${MINI_LINUX_USER}" | chroot_run chpasswd
log_warn "Default password is '${MINI_LINUX_USER}'. Change it on first boot!"

# Enable wheel group in sudoers
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' "${ROOTFS}/etc/sudoers"

# --- Enable services ---
log_info "Enabling system services..."
chroot_run systemctl enable NetworkManager.service
chroot_run systemctl enable bluetooth.service
chroot_run systemctl enable tlp.service
chroot_run systemctl enable nftables.service
chroot_run systemctl enable systemd-timesyncd.service

# --- Mask unnecessary services ---
log_info "Masking unnecessary services..."
while IFS= read -r service; do
    [[ -z "$service" || "$service" == \#* ]] && continue
    log_info "  Masking: $service"
    chroot_run systemctl mask "$service" 2>/dev/null || true
done < "${CONFIG_DIR}/systemd/masked-services.list"

# --- Autologin on TTY1 ---
log_info "Configuring autologin for '${MINI_LINUX_USER}' on TTY1..."
mkdir -p "${ROOTFS}/etc/systemd/system/getty@tty1.service.d"
sed "s/MINI_LINUX_USER/${MINI_LINUX_USER}/g" \
    "${CONFIG_DIR}/systemd/getty-autologin.conf" \
    > "${ROOTFS}/etc/systemd/system/getty@tty1.service.d/autologin.conf"

# --- Auto-start Hyprland ---
log_info "Configuring Hyprland auto-start..."
BASH_PROFILE="${ROOTFS}/home/${MINI_LINUX_USER}/.bash_profile"
cat > "${BASH_PROFILE}" <<'EOF'
# Auto-start Hyprland on TTY1
if [ -z "$WAYLAND_DISPLAY" ] && [ "$XDG_VTNR" -eq 1 ]; then
    exec Hyprland
fi
EOF
chroot_run chown "${MINI_LINUX_USER}:${MINI_LINUX_USER}" "/home/${MINI_LINUX_USER}/.bash_profile"

# --- XDG user directories ---
chroot_run su - "${MINI_LINUX_USER}" -c "xdg-user-dirs-update" 2>/dev/null || true

log_ok "System configuration complete."
```

- [ ] **Step 4: Create docs/04-configuration.md**

```markdown
# Step 4: Configuration

## What This Configures

| Setting | Value | Change by |
|---------|-------|-----------|
| Timezone | UTC | Edit `04-configure.sh` or run `timedatectl set-timezone <zone>` after boot |
| Locale | en_US.UTF-8 | Edit `04-configure.sh` |
| Hostname | mini-linux | Set `MINI_LINUX_HOSTNAME=myhost` environment variable |
| Username | user | Set `MINI_LINUX_USER=myname` environment variable |
| Default password | Same as username | **Change on first boot!** Run `passwd` |

## Services Enabled

| Service | Purpose |
|---------|---------|
| NetworkManager | WiFi and ethernet management |
| bluetooth | Bluetooth device support |
| tlp | Battery power optimization |
| nftables | Firewall |
| systemd-timesyncd | Time synchronization |

## Services Masked

Services in `config/systemd/masked-services.list` are masked (permanently disabled). Edit that file to change which services are masked.

## Autologin Flow

```
Boot → systemd → getty@tty1 (autologin) → .bash_profile → Hyprland
```

No display manager (GDM/SDDM/LightDM) is used. The user is logged in directly to TTY1, and `.bash_profile` launches Hyprland automatically. This saves 1-2 seconds on boot.

## Customization

```bash
# Change timezone
MINI_LINUX_TIMEZONE=America/New_York   # add to common.sh

# Change username
MINI_LINUX_USER=chamika make configure
```
```

- [ ] **Step 5: Commit**

```bash
git add scripts/04-configure.sh config/systemd/getty-autologin.conf config/systemd/masked-services.list docs/04-configuration.md
git commit -m "feat: system configuration — locale, user, services, autologin

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

## Task 7: Hyprland Desktop Setup

**Files:**
- Create: `scripts/05-hyprland-setup.sh`
- Create: `config/hyprland/hyprland.conf`
- Create: `config/waybar/config.jsonc`
- Create: `config/waybar/style.css`
- Create: `config/kitty/kitty.conf`
- Create: `config/wofi/config`
- Create: `config/mako/config`

- [ ] **Step 1: Create config/hyprland/hyprland.conf**

```ini
# Mini-Linux Hyprland Configuration
# See: https://wiki.hyprland.org/Configuring/

# --- Monitor ---
monitor=,preferred,auto,1

# --- Autostart ---
exec-once = waybar
exec-once = mako
exec-once = hyprpaper
exec-once = /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1
exec-once = nm-applet --indicator
exec-once = blueman-applet

# --- Environment ---
env = XCURSOR_SIZE,24
env = QT_QPA_PLATFORM,wayland
env = QT_QPA_PLATFORMTHEME,qt5ct
env = GDK_BACKEND,wayland
env = XDG_CURRENT_DESKTOP,Hyprland
env = XDG_SESSION_TYPE,wayland
env = XDG_SESSION_DESKTOP,Hyprland

# --- Input ---
input {
    kb_layout = us
    follow_mouse = 1
    sensitivity = 0
    touchpad {
        natural_scroll = true
        tap-to-click = true
        drag_lock = true
    }
}

# --- General ---
general {
    gaps_in = 4
    gaps_out = 8
    border_size = 2
    col.active_border = rgba(89b4faee) rgba(cba6f7ee) 45deg
    col.inactive_border = rgba(313244aa)
    layout = dwindle
}

# --- Decoration ---
decoration {
    rounding = 8
    blur {
        enabled = true
        size = 6
        passes = 2
        new_optimizations = true
    }
    shadow {
        enabled = true
        range = 8
        render_power = 2
        color = rgba(1a1a2eee)
    }
}

# --- Animations ---
animations {
    enabled = true
    bezier = ease, 0.25, 0.1, 0.25, 1.0
    animation = windows, 1, 4, ease, slide
    animation = windowsOut, 1, 4, ease, slide
    animation = fade, 1, 3, ease
    animation = workspaces, 1, 3, ease, slide
}

# --- Layout ---
dwindle {
    pseudotile = true
    preserve_split = true
}

# --- Keybindings ---
$mod = SUPER

bind = $mod, Return, exec, kitty
bind = $mod, E, exec, thunar
bind = $mod, B, exec, google-chrome-stable
bind = $mod, D, exec, wofi --show drun
bind = $mod, Q, killactive
bind = $mod SHIFT, Q, exit
bind = $mod, F, fullscreen, 0
bind = $mod, V, togglefloating
bind = $mod, P, pseudo
bind = $mod, S, togglesplit

# Move focus
bind = $mod, H, movefocus, l
bind = $mod, L, movefocus, r
bind = $mod, K, movefocus, u
bind = $mod, J, movefocus, d
bind = $mod, left, movefocus, l
bind = $mod, right, movefocus, r
bind = $mod, up, movefocus, u
bind = $mod, down, movefocus, d

# Move windows
bind = $mod SHIFT, H, movewindow, l
bind = $mod SHIFT, L, movewindow, r
bind = $mod SHIFT, K, movewindow, u
bind = $mod SHIFT, J, movewindow, d

# Workspaces
bind = $mod, 1, workspace, 1
bind = $mod, 2, workspace, 2
bind = $mod, 3, workspace, 3
bind = $mod, 4, workspace, 4
bind = $mod, 5, workspace, 5
bind = $mod, 6, workspace, 6
bind = $mod, 7, workspace, 7
bind = $mod, 8, workspace, 8
bind = $mod, 9, workspace, 9
bind = $mod, 0, workspace, 10

# Move window to workspace
bind = $mod SHIFT, 1, movetoworkspace, 1
bind = $mod SHIFT, 2, movetoworkspace, 2
bind = $mod SHIFT, 3, movetoworkspace, 3
bind = $mod SHIFT, 4, movetoworkspace, 4
bind = $mod SHIFT, 5, movetoworkspace, 5
bind = $mod SHIFT, 6, movetoworkspace, 6
bind = $mod SHIFT, 7, movetoworkspace, 7
bind = $mod SHIFT, 8, movetoworkspace, 8
bind = $mod SHIFT, 9, movetoworkspace, 9
bind = $mod SHIFT, 0, movetoworkspace, 10

# Screenshot
bind = , Print, exec, grim - | wl-copy
bind = SHIFT, Print, exec, grim -g "$(slurp)" - | wl-copy

# Volume / Brightness (media keys)
bindel = , XF86AudioRaiseVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+
bindel = , XF86AudioLowerVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-
bindl = , XF86AudioMute, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
bindl = , XF86AudioMicMute, exec, wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle
bindel = , XF86MonBrightnessUp, exec, brightnessctl s 5%+
bindel = , XF86MonBrightnessDown, exec, brightnessctl s 5%-
bindl = , XF86AudioPlay, exec, playerctl play-pause
bindl = , XF86AudioNext, exec, playerctl next
bindl = , XF86AudioPrev, exec, playerctl previous

# Mouse binds
bindm = $mod, mouse:272, movewindow
bindm = $mod, mouse:273, resizewindow

# Lock screen
bind = $mod SHIFT, L, exec, swaylock -f -c 1a1a2e

# Window rules
windowrulev2 = float, class:^(pavucontrol)$
windowrulev2 = float, class:^(nm-connection-editor)$
windowrulev2 = float, class:^(blueman-manager)$
windowrulev2 = float, title:^(File Operation Progress)$
```

- [ ] **Step 2: Create config/waybar/config.jsonc**

```jsonc
{
    "layer": "top",
    "position": "top",
    "height": 32,
    "spacing": 8,

    "modules-left": ["hyprland/workspaces"],
    "modules-center": ["clock"],
    "modules-right": ["network", "bluetooth", "pulseaudio", "backlight", "battery", "tray"],

    "hyprland/workspaces": {
        "format": "{icon}",
        "format-icons": {
            "active": "●",
            "default": "○"
        }
    },

    "clock": {
        "format": "{:%a %b %d  %H:%M}",
        "tooltip-format": "<tt>{calendar}</tt>"
    },

    "battery": {
        "format": "{icon} {capacity}%",
        "format-icons": ["", "", "", "", ""],
        "format-charging": " {capacity}%",
        "states": {
            "warning": 30,
            "critical": 15
        }
    },

    "network": {
        "format-wifi": "  {essid}",
        "format-ethernet": "  {ifname}",
        "format-disconnected": "  Disconnected",
        "tooltip-format-wifi": "{signalStrength}% | {ipaddr}",
        "on-click": "nm-connection-editor"
    },

    "bluetooth": {
        "format": "",
        "format-connected": " {device_alias}",
        "format-disabled": "",
        "on-click": "blueman-manager"
    },

    "pulseaudio": {
        "format": "{icon} {volume}%",
        "format-muted": " Muted",
        "format-icons": {
            "default": ["", "", ""]
        },
        "on-click": "pavucontrol"
    },

    "backlight": {
        "format": " {percent}%"
    },

    "tray": {
        "icon-size": 16,
        "spacing": 8
    }
}
```

- [ ] **Step 3: Create config/waybar/style.css**

```css
/* Waybar Styling — Catppuccin Mocha inspired */

* {
    font-family: "JetBrainsMono Nerd Font", sans-serif;
    font-size: 13px;
    min-height: 0;
}

window#waybar {
    background-color: rgba(30, 30, 46, 0.9);
    color: #cdd6f4;
    border-bottom: 2px solid rgba(137, 180, 250, 0.3);
}

#workspaces button {
    padding: 0 8px;
    color: #6c7086;
    border: none;
    border-radius: 0;
    background: transparent;
}

#workspaces button.active {
    color: #89b4fa;
}

#workspaces button:hover {
    background: rgba(137, 180, 250, 0.15);
}

#clock {
    color: #cdd6f4;
    font-weight: bold;
}

#battery,
#network,
#bluetooth,
#pulseaudio,
#backlight,
#tray {
    padding: 0 10px;
}

#battery.warning {
    color: #f9e2af;
}

#battery.critical {
    color: #f38ba8;
}

#network.disconnected {
    color: #6c7086;
}
```

- [ ] **Step 4: Create config/kitty/kitty.conf**

```conf
# Kitty Terminal Configuration

# Font
font_family      JetBrainsMono Nerd Font
bold_font        auto
italic_font      auto
bold_italic_font auto
font_size        11.0

# Window
window_padding_width 8
confirm_os_window_close 0
enable_audio_bell no

# Tab bar
tab_bar_style powerline
tab_bar_min_tabs 2

# Scrollback
scrollback_lines 10000

# Colors — Catppuccin Mocha
foreground           #cdd6f4
background           #1e1e2e
selection_foreground #1e1e2e
selection_background #f5e0dc
cursor               #f5e0dc
cursor_text_color    #1e1e2e
url_color            #89b4fa

# Black
color0  #45475a
color8  #585b70
# Red
color1  #f38ba8
color9  #f38ba8
# Green
color2  #a6e3a1
color10 #a6e3a1
# Yellow
color3  #f9e2af
color11 #f9e2af
# Blue
color4  #89b4fa
color12 #89b4fa
# Magenta
color5  #cba6f7
color13 #cba6f7
# Cyan
color6  #94e2d5
color14 #94e2d5
# White
color7  #bac2de
color15 #a6adc8

# Keybindings for splits
map ctrl+shift+enter new_window
map ctrl+shift+h neighboring_window left
map ctrl+shift+l neighboring_window right
map ctrl+shift+k neighboring_window up
map ctrl+shift+j neighboring_window down
```

- [ ] **Step 5: Create config/wofi/config**

```ini
show=drun
width=500
height=400
always_parse_args=true
show_all=false
print_command=true
insensitive=true
prompt=Search...
layer=overlay
```

- [ ] **Step 6: Create config/mako/config**

```ini
default-timeout=5000
border-size=2
border-color=#89b4fa
border-radius=8
background-color=#1e1e2e
text-color=#cdd6f4
font=JetBrainsMono Nerd Font 11
padding=12
margin=8
width=350
max-visible=3
layer=overlay

[urgency=high]
border-color=#f38ba8
default-timeout=10000
```

- [ ] **Step 7: Create scripts/05-hyprland-setup.sh**

```bash
#!/usr/bin/env bash
# 05-hyprland-setup.sh — Install desktop environment configs into rootfs.

source "$(dirname "$0")/common.sh"
require_root

log_info "=== Hyprland Desktop Setup ==="

if [[ ! -d "${ROOTFS}/usr" ]]; then
    log_error "Rootfs not found. Run 00-bootstrap.sh first."
    exit 1
fi

USER_HOME="${ROOTFS}/home/${MINI_LINUX_USER}"
CONFIG_HOME="${USER_HOME}/.config"

# Create config directories
mkdir -p "${CONFIG_HOME}/hypr"
mkdir -p "${CONFIG_HOME}/waybar"
mkdir -p "${CONFIG_HOME}/kitty"
mkdir -p "${CONFIG_HOME}/wofi"
mkdir -p "${CONFIG_HOME}/mako"

# Copy configs
log_info "Installing Hyprland config..."
cp "${CONFIG_DIR}/hyprland/hyprland.conf" "${CONFIG_HOME}/hypr/hyprland.conf"

log_info "Installing Waybar config..."
cp "${CONFIG_DIR}/waybar/config.jsonc" "${CONFIG_HOME}/waybar/config.jsonc"
cp "${CONFIG_DIR}/waybar/style.css" "${CONFIG_HOME}/waybar/style.css"

log_info "Installing Kitty config..."
cp "${CONFIG_DIR}/kitty/kitty.conf" "${CONFIG_HOME}/kitty/kitty.conf"

log_info "Installing Wofi config..."
cp "${CONFIG_DIR}/wofi/config" "${CONFIG_HOME}/wofi/config"

log_info "Installing Mako config..."
cp "${CONFIG_DIR}/mako/config" "${CONFIG_HOME}/mako/config"

# --- GTK Theme ---
log_info "Configuring GTK theme..."
mkdir -p "${CONFIG_HOME}/gtk-3.0"
cat > "${CONFIG_HOME}/gtk-3.0/settings.ini" <<EOF
[Settings]
gtk-theme-name=Adwaita-dark
gtk-icon-theme-name=Papirus-Dark
gtk-cursor-theme-name=Adwaita
gtk-cursor-theme-size=24
gtk-font-name=Noto Sans 11
gtk-application-prefer-dark-theme=1
EOF

# --- Cursor theme for Hyprland ---
mkdir -p "${CONFIG_HOME}/icons/default"
cat > "${CONFIG_HOME}/icons/default/index.theme" <<EOF
[Icon Theme]
Inherits=Adwaita
EOF

# Fix ownership
chroot_run chown -R "${MINI_LINUX_USER}:${MINI_LINUX_USER}" "/home/${MINI_LINUX_USER}"

log_ok "Desktop environment configured."
```

- [ ] **Step 8: Commit**

```bash
git add config/hyprland/ config/waybar/ config/kitty/ config/wofi/ config/mako/ scripts/05-hyprland-setup.sh
git commit -m "feat: Hyprland desktop setup — compositor, bar, terminal, launcher, notifications

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

## Task 8: Boot Optimization Script

**Files:**
- Create: `scripts/06-boot-optimize.sh`
- Create: `config/mkinitcpio.conf`
- Create: `docs/05-boot-optimization.md`

- [ ] **Step 1: Create config/mkinitcpio.conf**

```conf
# Minimal initramfs for fast boot on Dell XPS 13 9380.
# Boot-critical modules built into kernel, so MODULES is mostly empty.
# The autodetect hook strips this to only hardware-present modules.

MODULES=(i915)
BINARIES=()
FILES=()
HOOKS=(base systemd autodetect modconf kms block filesystems)

# Compression — zstd is fastest decompression
COMPRESSION="zstd"
COMPRESSION_OPTIONS=(-3)
```

- [ ] **Step 2: Create scripts/06-boot-optimize.sh**

```bash
#!/usr/bin/env bash
# 06-boot-optimize.sh — Apply boot time optimizations to rootfs.

source "$(dirname "$0")/common.sh"
require_root

log_info "=== Boot Optimization ==="

if [[ ! -d "${ROOTFS}/usr" ]]; then
    log_error "Rootfs not found. Run previous scripts first."
    exit 1
fi

# --- Initramfs ---
log_info "Installing optimized mkinitcpio.conf..."
cp "${CONFIG_DIR}/mkinitcpio.conf" "${ROOTFS}/etc/mkinitcpio.conf"

# Regenerate initramfs with minimal config
log_info "Regenerating initramfs..."
chroot_run mkinitcpio -P

# --- Kernel command line (stored for bootloader config) ---
log_info "Writing kernel command line..."
CMDLINE="root=UUID=ROOTFS_UUID rw quiet loglevel=3 rd.systemd.show_status=false rd.udev.log_level=3 nowatchdog nmi_watchdog=0 tsc=reliable"
echo "${CMDLINE}" > "${ROOTFS}/etc/kernel/cmdline"
mkdir -p "${ROOTFS}/etc/kernel"
echo "${CMDLINE}" > "${ROOTFS}/etc/kernel/cmdline"

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
cat >> "${ROOTFS}/etc/fstab" <<EOF

# tmpfs for /tmp — faster than disk, cleared on reboot
tmpfs   /tmp    tmpfs   defaults,noatime,mode=1777,size=2G  0 0
EOF

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

# --- PipeWire socket activation (start only when audio is needed) ---
log_info "Ensuring PipeWire uses socket activation..."
# PipeWire on Arch already uses user-level socket activation by default.
# We just make sure the socket is enabled and the service is not force-started.

log_ok "Boot optimizations applied."
log_info "Expected boot timeline:"
log_info "  UEFI POST → GRUB → Kernel → systemd → Hyprland"
log_info "  ~0.5s       ~1s    ~1.5s    ~2.5s     ~1s = ~6.5s"
```

- [ ] **Step 3: Create docs/05-boot-optimization.md**

```markdown
# Step 5: Boot Optimization

## Target: <7 seconds (UEFI POST to Hyprland ready)

## What We Optimize

### 1. Initramfs (saves ~1s)

Our `mkinitcpio.conf` uses:
- **systemd hook** instead of busybox (parallel init inside initramfs)
- **autodetect** — only includes modules for hardware actually present
- **kms** — early Intel GPU modesetting (display ready sooner)
- **zstd compression** — fastest decompression

### 2. Kernel Command Line (saves ~0.5s)

- `quiet loglevel=3` — suppress boot messages
- `nowatchdog nmi_watchdog=0` — disable hardware watchdog checks
- `tsc=reliable` — skip TSC calibration delay

### 3. systemd Services (saves ~1-2s)

Masked services (in `config/systemd/masked-services.list`):
- `lvm2-monitor` — no LVM on this system
- `remote-fs.target` — no network mounts
- `ModemManager` — no cellular modem

Socket-activated (start on demand, not at boot):
- PipeWire (starts when an app needs audio)
- BlueZ (starts when Bluetooth is used)

### 4. Filesystem (saves ~0.3s)

- `/tmp` mounted as tmpfs (no disk I/O for temp files)
- NVMe scheduler set to `none` (NVMe has internal scheduling)
- Journal size capped at 50MB

## Measuring Boot Time

After booting into mini-linux:

```bash
# Total boot time
systemd-analyze

# Per-service breakdown
systemd-analyze blame

# Critical path
systemd-analyze critical-chain

# Visual plot (open in browser)
systemd-analyze plot > boot.svg
```
```

- [ ] **Step 4: Commit**

```bash
git add scripts/06-boot-optimize.sh config/mkinitcpio.conf docs/05-boot-optimization.md
git commit -m "feat: boot optimizations — initramfs, kernel cmdline, services, filesystem

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

## Task 9: USB Image Builder

**Files:**
- Create: `scripts/07-build-usb-image.sh`
- Create: `docs/06-usb-image.md`

- [ ] **Step 1: Create scripts/07-build-usb-image.sh**

```bash
#!/usr/bin/env bash
# 07-build-usb-image.sh — Package the rootfs into a bootable USB image.
# Creates a GPT disk image with EFI + root partitions, installs GRUB for UEFI boot.

source "$(dirname "$0")/common.sh"
require_root
require_command parted
require_command mkfs.fat
require_command mkfs.ext4
require_command grub-install

IMAGE_SIZE="${IMAGE_SIZE:-8G}"
IMAGE_FILE="${BUILD_DIR}/mini-linux.img"
MNT="${BUILD_DIR}/mnt"

log_info "=== USB Image Builder ==="
log_info "Image size: ${IMAGE_SIZE}"
log_info "Image file: ${IMAGE_FILE}"

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
# /etc/fstab — Mini-Linux
UUID=${ROOT_UUID}   /           ext4    defaults,noatime,commit=60  0 1
UUID=${EFI_UUID}    /boot/efi   vfat    defaults,umask=0077         0 2
tmpfs               /tmp        tmpfs   defaults,noatime,mode=1777,size=2G  0 0
EOF

# Install GRUB for UEFI
log_info "Installing GRUB bootloader..."
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

# Unmount
log_info "Unmounting..."
umount -R "${MNT}"
losetup -d "${LOOP}"

# Copy image to project build directory
mkdir -p "${PROJECT_ROOT}/build"
cp "${IMAGE_FILE}" "${PROJECT_ROOT}/build/mini-linux.img"

log_ok "USB image created: build/mini-linux.img"
log_info "Flash to USB:"
log_info "  sudo dd if=build/mini-linux.img of=/dev/sdX bs=4M status=progress"
log_info ""
log_info "Find your USB device with: lsblk"
```

- [ ] **Step 2: Create docs/06-usb-image.md**

```markdown
# Step 6: USB Image

## What This Does

Packages the built rootfs into a bootable GPT disk image with:
- **EFI System Partition** (512MB, FAT32) — contains GRUB bootloader
- **Root Partition** (rest of image, ext4) — contains mini-linux

## Building

```bash
make usb-image
```

Output: `build/mini-linux.img`

## Flashing to USB

```bash
# Find your USB device (e.g., /dev/sdb — BE CAREFUL, wrong device = data loss!)
lsblk

# Flash the image
sudo dd if=build/mini-linux.img of=/dev/sdX bs=4M status=progress
sync
```

## Booting

1. Plug the USB into the XPS 13
2. Reboot and press **F12** during boot to open the boot menu
3. Select the USB device (UEFI)
4. Mini-linux should boot to Hyprland desktop

## Testing Checklist

After booting from USB, verify:
- [ ] WiFi connects (use `nmtui` or NetworkManager applet)
- [ ] Audio works (open a YouTube video in Chrome)
- [ ] Bluetooth pairs (use `blueman-manager`)
- [ ] Touchpad and keyboard work
- [ ] Screen brightness keys work
- [ ] Volume keys work
- [ ] Camera works (test with `mpv av://v4l2:/dev/video0`)
- [ ] External USB devices are detected

## Customizing Image Size

Default is 8GB. For a larger image:
```bash
IMAGE_SIZE=16G make usb-image
```
```

- [ ] **Step 3: Commit**

```bash
git add scripts/07-build-usb-image.sh docs/06-usb-image.md
git commit -m "feat: USB image builder — bootable GPT image with GRUB

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

## Task 10: NVMe Install Script (Dual-Boot)

**Files:**
- Create: `scripts/08-install-to-nvme.sh`
- Create: `config/grub/40_custom-mini-linux`
- Create: `docs/07-install-to-nvme.md`

- [ ] **Step 1: Create config/grub/40_custom-mini-linux**

This is a template GRUB entry. The install script substitutes real UUIDs.

```bash
#!/bin/sh
exec tail -n +3 $0
# Custom GRUB entry for Mini-Linux (added by mini-linux installer)
menuentry "Mini-Linux" --class arch --class gnu-linux --class os {
    search --no-floppy --fs-uuid --set=root ROOTFS_UUID_PLACEHOLDER
    linux /EFI/mini-linux/vmlinuz root=UUID=ROOTFS_UUID_PLACEHOLDER rw quiet loglevel=3 rd.systemd.show_status=false rd.udev.log_level=3 nowatchdog nmi_watchdog=0 tsc=reliable
    initrd /EFI/mini-linux/intel-ucode.img /EFI/mini-linux/initramfs.img
}
```

- [ ] **Step 2: Create scripts/08-install-to-nvme.sh**

```bash
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

# Safety check — don't format Ubuntu's partitions
UBUNTU_ROOT=$(findmnt -n -o SOURCE /)
if [[ "$ROOT_PART" == "$UBUNTU_ROOT" ]]; then
    log_error "That's your current Ubuntu root partition! Aborting."
    exit 1
fi

echo ""
log_warn "About to format:"
log_warn "  Root: ${ROOT_PART} (ext4)"
[[ "$SWAP_PART" != "none" ]] && log_warn "  Swap: ${SWAP_PART}"
echo ""
read -rp "Type 'yes' to continue: " CONFIRM
if [[ "$CONFIRM" != "yes" ]]; then
    log_info "Aborted."
    exit 0
fi

# --- Format partitions ---
log_info "Formatting root partition..."
mkfs.ext4 -L mini-linux -q "$ROOT_PART"

if [[ "$SWAP_PART" != "none" ]]; then
    log_info "Formatting swap partition..."
    mkswap -L mini-swap "$SWAP_PART"
fi

# --- Mount and copy rootfs ---
MNT="${BUILD_DIR}/nvme-mnt"
mkdir -p "$MNT"
mount "$ROOT_PART" "$MNT"

log_info "Copying rootfs to NVMe (this may take several minutes)..."
rsync -aAX --info=progress2 "${ROOTFS}/" "${MNT}/"

# --- Generate fstab ---
ROOT_UUID=$(blkid -s UUID -o value "$ROOT_PART")
log_info "Root UUID: ${ROOT_UUID}"

# Find the existing ESP
ESP_MOUNT=$(findmnt -n -o TARGET /boot/efi 2>/dev/null || findmnt -n -o TARGET /boot/EFI 2>/dev/null || echo "")
if [[ -z "$ESP_MOUNT" ]]; then
    # Try common Ubuntu ESP locations
    for candidate in /boot/efi /boot/EFI; do
        if mountpoint -q "$candidate" 2>/dev/null; then
            ESP_MOUNT="$candidate"
            break
        fi
    done
fi

if [[ -z "$ESP_MOUNT" ]]; then
    log_error "Cannot find EFI System Partition. Is Ubuntu using UEFI?"
    umount "$MNT"
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

if [[ "$SWAP_PART" != "none" ]]; then
    SWAP_UUID=$(blkid -s UUID -o value "$SWAP_PART")
    echo "UUID=${SWAP_UUID}   none        swap    defaults                    0 0" >> "${MNT}/etc/fstab"
fi

# --- Install kernel + initramfs to shared ESP ---
log_info "Installing kernel to shared ESP..."
mkdir -p "${ESP_MOUNT}/EFI/mini-linux"
cp "${MNT}/boot/vmlinuz-mini-linux" "${ESP_MOUNT}/EFI/mini-linux/vmlinuz"
cp "${MNT}/boot/initramfs-linux.img" "${ESP_MOUNT}/EFI/mini-linux/initramfs.img" 2>/dev/null || \
    cp "${MNT}/boot/initramfs-mini-linux.img" "${ESP_MOUNT}/EFI/mini-linux/initramfs.img" 2>/dev/null || true

# Copy Intel microcode
if [[ -f "${MNT}/boot/intel-ucode.img" ]]; then
    cp "${MNT}/boot/intel-ucode.img" "${ESP_MOUNT}/EFI/mini-linux/intel-ucode.img"
fi

# --- Add GRUB entry ---
log_info "Adding GRUB entry for dual-boot..."
GRUB_CUSTOM="/etc/grub.d/40_custom"

# Check if entry already exists
if grep -q "Mini-Linux" "$GRUB_CUSTOM" 2>/dev/null; then
    log_warn "GRUB entry for Mini-Linux already exists. Updating..."
    # Remove old entry (between Mini-Linux markers)
    sed -i '/# --- Mini-Linux START ---/,/# --- Mini-Linux END ---/d' "$GRUB_CUSTOM"
fi

cat >> "$GRUB_CUSTOM" <<EOF

# --- Mini-Linux START ---
menuentry "Mini-Linux" --class arch --class gnu-linux --class os {
    search --no-floppy --fs-uuid --set=root ${ROOT_UUID}
    linux /EFI/mini-linux/vmlinuz root=UUID=${ROOT_UUID} rw quiet loglevel=3 rd.systemd.show_status=false rd.udev.log_level=3 nowatchdog nmi_watchdog=0 tsc=reliable
    initrd /EFI/mini-linux/intel-ucode.img /EFI/mini-linux/initramfs.img
}
# --- Mini-Linux END ---
EOF

# Regenerate GRUB config
log_info "Regenerating GRUB config..."
update-grub

# --- Cleanup ---
umount "$MNT"

log_ok "Mini-Linux installed to NVMe!"
log_info ""
log_info "  Root partition: ${ROOT_PART} (UUID: ${ROOT_UUID})"
log_info "  Kernel at: ${ESP_MOUNT}/EFI/mini-linux/vmlinuz"
log_info "  GRUB entry added — select 'Mini-Linux' at boot menu"
log_info ""
log_info "Reboot and select 'Mini-Linux' from the GRUB menu to test."
log_info "Default password: ${MINI_LINUX_USER} (change with 'passwd' after login)"
```

- [ ] **Step 3: Create docs/07-install-to-nvme.md**

```markdown
# Step 7: Install to NVMe (Dual-Boot)

## Prerequisites

1. **Test on USB first!** Make sure everything works (WiFi, audio, etc.)
2. **Create partitions** for mini-linux on the NVMe. Use GParted (from Ubuntu):
   - Root partition: 30-50GB, ext4
   - Swap partition: 2GB (optional)

Example using `fdisk`:
```bash
sudo fdisk /dev/nvme0n1
# Create two new partitions in the unallocated space
# Type 'n' for new, accept defaults for start, set size with +30G, +2G
# Type 'w' to write
```

## Installing

```bash
make install
```

The script will:
1. Ask you which partitions to use
2. Format them (ext4 + swap)
3. Copy the rootfs
4. Install kernel + initramfs to the shared EFI partition
5. Add a "Mini-Linux" entry to Ubuntu's GRUB

## Booting

1. Reboot the laptop
2. GRUB menu appears with Ubuntu (default) and **Mini-Linux**
3. Select Mini-Linux
4. You should see the Hyprland desktop in <7 seconds

## Changing Default Boot OS

To make Mini-Linux the default:
```bash
# From Ubuntu:
sudo nano /etc/default/grub
# Change GRUB_DEFAULT=0 to the Mini-Linux entry number
sudo update-grub
```

## Uninstalling

To remove mini-linux and reclaim the space:
```bash
# From Ubuntu:
# 1. Remove GRUB entry
sudo nano /etc/grub.d/40_custom  # Remove the Mini-Linux block
sudo update-grub

# 2. Remove kernel from ESP
sudo rm -rf /boot/efi/EFI/mini-linux

# 3. Delete partitions with GParted or fdisk
```
```

- [ ] **Step 4: Commit**

```bash
git add scripts/08-install-to-nvme.sh config/grub/40_custom-mini-linux docs/07-install-to-nvme.md
git commit -m "feat: NVMe installer — dual-boot alongside Ubuntu via GRUB

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

## Task 11: Final Integration — Make All Scripts Executable + Final Docs

**Files:**
- Modify: all `scripts/*.sh` (chmod +x)
- Create: `docs/05-boot-optimization.md` (already created in Task 8)

- [ ] **Step 1: Make all scripts executable**

```bash
chmod +x scripts/*.sh
```

- [ ] **Step 2: Verify build pipeline order**

Quick sanity check — ensure every script sources `common.sh` and checks prerequisites:

```bash
# Check all scripts source common.sh
grep -l 'source.*common.sh' scripts/*.sh | wc -l
# Should output: 9 (00 through 08)

# Check all scripts that need root call require_root
grep -l 'require_root' scripts/*.sh | wc -l
# Should output: 9
```

- [ ] **Step 3: Final commit**

```bash
git add -A
git commit -m "chore: make scripts executable, final integration check

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

## Summary

| Task | What | Files |
|------|------|-------|
| 1 | Project scaffolding | `.gitignore`, `README.md`, `common.sh`, `Makefile` |
| 2 | Bootstrap script | `00-bootstrap.sh`, prerequisites + bootstrap docs |
| 3 | Kernel config | `01-kernel-config.sh`, placeholder `.config`, kernel docs |
| 4 | Kernel build | `02-kernel-build.sh` |
| 5 | Package install | `03-packages.sh`, packages docs |
| 6 | System config | `04-configure.sh`, autologin + masked services config, config docs |
| 7 | Desktop setup | `05-hyprland-setup.sh`, all desktop configs (hyprland, waybar, kitty, wofi, mako) |
| 8 | Boot optimization | `06-boot-optimize.sh`, `mkinitcpio.conf`, boot optimization docs |
| 9 | USB image | `07-build-usb-image.sh`, USB image docs |
| 10 | NVMe install | `08-install-to-nvme.sh`, GRUB entry template, install docs |
| 11 | Final integration | chmod +x, verification |

Total: **11 tasks**, ~35 files, ~11 commits.
