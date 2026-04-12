# Mini-Linux Distribution Specification

## Overview

A minimal, fast-booting Linux distribution built on Arch Linux, targeting the Dell XPS 13 9380 as a personal daily driver. Designed for web browsing, file management, and development, with <7 second cold boot time. Dual-boots alongside an existing Ubuntu installation.

## Target Hardware

| Component | Spec | Kernel Driver |
|-----------|------|---------------|
| CPU | Intel i7-8565U (Whiskey Lake) | intel_pstate |
| GPU | Intel UHD Graphics 620 | i915 |
| RAM | 16GB DDR4 | - |
| Storage | 512GB NVMe SSD | nvme |
| WiFi | Intel Wireless-AC 9560 | iwlwifi (iwlmvm) |
| Bluetooth | Intel BT (integrated with WiFi) | btusb, btintel |
| Audio | Realtek ALC3271 (via Intel HDA) | snd_hda_intel, snd_soc_skl |
| Camera | Integrated USB webcam | uvcvideo |
| Touchpad | Synaptics/I2C HID | i2c_hid, hid_multitouch |
| Keyboard | PS/2 via Intel LPC | atkbd, i8042 |
| Card Reader | Realtek RTS525A | rtsx_pci |
| Thunderbolt | Intel JHL6240 (Alpine Ridge) | thunderbolt |
| USB | xHCI (USB 3.1) | xhci_hcd |

## Architecture

```
┌─────────────────────────────────────────────────┐
│               User Applications                  │
│  Chrome · VS Code · Thunar · Kitty               │
├─────────────────────────────────────────────────┤
│         Hyprland (Wayland Compositor)            │
│    + Waybar · Wofi · Mako · Theme                │
├─────────────────────────────────────────────────┤
│            System Services (systemd)             │
│  NetworkManager · PipeWire · BlueZ               │
├─────────────────────────────────────────────────┤
│       Custom Linux Kernel (XPS 13 only)          │
│  i915 · iwlwifi · nvme · snd_hda · uvcvideo     │
├─────────────────────────────────────────────────┤
│     Ubuntu GRUB (shared UEFI bootloader)         │
│        EFI System Partition (shared)             │
└─────────────────────────────────────────────────┘
```

## Dual-Boot Strategy

### Partitioning

Mini-linux installs into the unallocated NVMe space alongside the existing Ubuntu installation.

```
NVMe Partition Layout:
┌──────────┬───────────────┬───────────────┬───────┬────────────────┐
│ ESP      │ Ubuntu /      │ Ubuntu swap   │ swap  │ mini-linux /   │
│ (shared) │ (existing)    │ (existing)    │ 2GB   │ 30-50GB ext4   │
│ ~512MB   │               │               │       │                │
└──────────┴───────────────┴───────────────┴───────┴────────────────┘
```

- **EFI System Partition:** Shared with Ubuntu. Mini-linux kernel + initramfs placed under `/boot/efi/EFI/mini-linux/`.
- **Swap:** Dedicated 2GB swap partition (separate from Ubuntu's). Sized small — with 16GB RAM this is mostly for hibernate if needed later.
- **Root (/):** 30-50GB ext4 partition. No separate /home — keeps it simple.

### Bootloader

- Uses **Ubuntu's existing GRUB** as the boot menu.
- After installing mini-linux, run `update-grub` from Ubuntu — GRUB's `os-prober` auto-detects the new OS.
- Alternatively, a manual GRUB entry is added at `/etc/grub.d/40_custom` pointing to mini-linux's kernel + initramfs on the ESP.
- Ubuntu remains the default boot entry; user selects mini-linux from GRUB menu.

### GRUB Entry (manual fallback)

```bash
menuentry "Mini-Linux" {
    search --no-floppy --fs-uuid --set=root <MINI_LINUX_ROOT_UUID>
    linux /EFI/mini-linux/vmlinuz root=UUID=<MINI_LINUX_ROOT_UUID> rw quiet
    initrd /EFI/mini-linux/initramfs.img
}
```

## Component Selection

### Core System

| Role | Component | Version | Notes |
|------|-----------|---------|-------|
| Base | Arch Linux (pacstrap) | Rolling | glibc, pacman, base packages |
| Init | systemd | Latest | Parallel boot, socket activation |
| Kernel | Custom mainline Linux | 6.x | Stripped to XPS 13 hardware only |

### Desktop Environment

| Role | Component | Notes |
|------|-----------|-------|
| Compositor | Hyprland | Wayland tiling + animations |
| Status Bar | Waybar | Customizable, Wayland-native |
| App Launcher | Wofi | Wayland-native dmenu/rofi alternative |
| Notifications | Mako | Lightweight Wayland notification daemon |
| Screen Lock | Swaylock-effects | Wayland screen locker with blur effects |
| Wallpaper | Hyprpaper | Hyprland's native wallpaper utility |

### Applications

| Role | Component | Notes |
|------|-----------|-------|
| Browser | Google Chrome | AUR: `google-chrome` |
| File Manager | Thunar | Lightweight GTK file manager |
| Terminal | Kitty | GPU-accelerated, native splits |
| Code Editor | VS Code | AUR: `visual-studio-code-bin` (installed later by user) |

### System Services

| Role | Component | Notes |
|------|-----------|-------|
| Audio | PipeWire + WirePlumber | Replaces PulseAudio, handles audio + video routing |
| Network | NetworkManager | WiFi/ethernet management, nmtui for terminal UI |
| Bluetooth | BlueZ | Standard Linux BT stack, managed via `bluetoothctl` |
| Display Manager | None (TTY autologin) | Direct Hyprland launch from TTY for faster boot |
| Power Management | TLP | Battery optimization for laptop |
| Firmware | linux-firmware + intel-ucode | WiFi firmware, CPU microcode updates |

### Theming & Fonts

| Role | Component |
|------|-----------|
| GTK Theme | Adwaita-dark or Catppuccin |
| Icon Theme | Papirus-Dark |
| Cursor | Bibata-Modern-Classic |
| Fonts | noto-fonts, noto-fonts-cjk, noto-fonts-emoji |
| Terminal/Bar Font | ttf-jetbrains-mono-nerd |

## Boot Time Optimization Strategy

Target: **<7 seconds** from UEFI POST to Hyprland desktop ready.

### Kernel Optimizations

1. **Strip kernel to XPS 13 hardware only**
   - Disable all unused drivers (1000+ modules → ~50)
   - Built-in (=y) for boot-critical drivers: NVMe, i915, ext4
   - Module (=m) for non-boot: WiFi, BT, audio, camera, USB peripherals
   - Disable: SCSI, IDE, old network drivers, non-Intel GPU, legacy input, virtualization (if not needed)

2. **Kernel command line tuning**
   ```
   quiet loglevel=3 rd.systemd.show_status=false rd.udev.log_level=3
   nowatchdog nmi_watchdog=0 tsc=reliable
   ```

### Initramfs Optimizations

1. **Minimal mkinitcpio.conf**
   ```
   MODULES=(i915 nvme ext4)
   HOOKS=(base systemd autodetect modconf kms block filesystems)
   ```
   - Remove: `keyboard`, `keymap`, `consolefont` (not needed for boot → graphical login)
   - `autodetect` ensures only hardware-present modules are included
   - `kms` for early Intel GPU modesetting (faster display init)

2. **Use systemd hook** instead of busybox (parallel init in initramfs)

### systemd Service Optimization

1. **Disable unnecessary services:**
   - `systemd-timesyncd` → defer or replace with one-shot
   - `systemd-journal-flush` → defer
   - `remote-fs.target` → mask
   - `lvm2-monitor` → mask (no LVM)
   - `ModemManager` → mask (no cellular modem)

2. **Optimize remaining services:**
   - NetworkManager: delay WiFi scan until after desktop
   - PipeWire: socket-activated (starts on first audio use)
   - BlueZ: socket-activated

3. **Autologin to TTY1:**
   ```ini
   # /etc/systemd/system/getty@tty1.service.d/autologin.conf
   [Service]
   ExecStart=
   ExecStart=-/sbin/agetty -o '-p -f -- \\u' --noclear --autologin <username> %I $TERM
   ```

4. **Auto-start Hyprland from .bash_profile:**
   ```bash
   if [ -z "$WAYLAND_DISPLAY" ] && [ "$XDG_VTNR" -eq 1 ]; then
       exec Hyprland
   fi
   ```

### Filesystem Optimizations

- **ext4 mount options:** `noatime,commit=60`
- **NVMe scheduler:** `none` (NVMe doesn't benefit from I/O schedulers)

### Expected Boot Timeline

```
0.0s  ─── UEFI POST ───────────────────
0.5s  ─── GRUB (timeout=0 for mini-linux, but shared with Ubuntu) ──
1.0s  ─── Kernel loading ──────────────
2.0s  ─── Kernel init + initramfs ─────
3.0s  ─── systemd PID 1 ──────────────
4.5s  ─── Core services ready ─────────
5.5s  ─── TTY autologin ──────────────
6.0s  ─── Hyprland launching ──────────
6.5s  ─── Desktop ready ──────────────
```

Note: GRUB adds ~0.5-1s vs systemd-boot, but this is the tradeoff for safe dual-boot with Ubuntu.

## Build Pipeline

### Phase 1: Bootstrap (on build machine)

Create a minimal Arch root filesystem using `pacstrap`. This runs on any existing Linux machine (including the Ubuntu install on the XPS 13).

**Packages (base):**
```
base linux-firmware intel-ucode
networkmanager pipewire wireplumber pipewire-pulse pipewire-alsa
bluez bluez-utils
sudo
```

### Phase 2: Custom Kernel

Compile a kernel stripped to XPS 13 hardware:
1. Start from `make localmodconfig` on the XPS 13 (captures only loaded modules)
2. Further strip unused subsystems manually
3. Build-in boot-critical drivers (NVMe, i915, ext4)
4. Install to the rootfs

### Phase 3: Desktop Packages

```
hyprland waybar wofi mako swaylock-effects hyprpaper
xdg-desktop-portal-hyprland
kitty thunar
noto-fonts noto-fonts-cjk noto-fonts-emoji ttf-jetbrains-mono-nerd
papirus-icon-theme
polkit-gnome
grim slurp wl-clipboard
```

### Phase 4: AUR Packages (via makepkg)

```
google-chrome
```

(VS Code installed later by user when needed)

### Phase 5: Configuration

- systemd service enable/disable/mask
- mkinitcpio.conf for minimal initramfs
- Hyprland config (keybinds, monitors, autostart)
- Waybar config (clock, battery, network, audio, bluetooth)
- Autologin + auto-start Hyprland
- User creation + sudo setup
- Locale, timezone, hostname

### Phase 6: Boot Optimization

- Kernel command line tuning
- Service profiling with `systemd-analyze blame`
- Initramfs stripping
- Filesystem mount options

### Phase 7: Image Generation

1. Package rootfs into a bootable USB image (for testing)
2. Create install script that:
   - Formats target partitions
   - Copies rootfs to NVMe
   - Installs kernel + initramfs to ESP under `/EFI/mini-linux/`
   - Runs `update-grub` on Ubuntu (or adds manual GRUB entry)

## Repository Structure

```
mini-linux/
├── README.md                          # Project overview + quick start
├── docs/
│   ├── 00-prerequisites.md            # What you need before building
│   ├── 01-bootstrap.md                # Creating the base rootfs
│   ├── 02-kernel.md                   # Custom kernel compilation
│   ├── 03-packages.md                 # Package installation
│   ├── 04-configuration.md            # System + desktop config
│   ├── 05-boot-optimization.md        # Boot time tuning guide
│   ├── 06-usb-image.md                # Building the USB test image
│   ├── 07-install-to-nvme.md          # Installing alongside Ubuntu
│   └── superpowers/specs/
│       └── mini-linux-spec.md         # This specification
├── scripts/
│   ├── 00-bootstrap.sh                # Create Arch base rootfs
│   ├── 01-kernel-config.sh            # Generate kernel config
│   ├── 02-kernel-build.sh             # Compile custom kernel
│   ├── 03-packages.sh                 # Install desktop + app packages
│   ├── 04-configure.sh                # System configuration
│   ├── 05-hyprland-setup.sh           # Desktop environment setup
│   ├── 06-boot-optimize.sh            # Apply boot optimizations
│   ├── 07-build-usb-image.sh          # Generate bootable USB image
│   └── 08-install-to-nvme.sh          # Install to NVMe alongside Ubuntu
├── config/
│   ├── kernel/
│   │   └── xps13-9380.config          # Custom kernel .config
│   ├── hyprland/
│   │   └── hyprland.conf              # Hyprland configuration
│   ├── waybar/
│   │   ├── config.jsonc               # Waybar layout
│   │   └── style.css                  # Waybar styling
│   ├── kitty/
│   │   └── kitty.conf                 # Kitty terminal config
│   ├── wofi/
│   │   └── config                     # Wofi launcher config
│   ├── mako/
│   │   └── config                     # Notification config
│   ├── systemd/
│   │   ├── getty-autologin.conf        # TTY autologin override
│   │   └── masked-services.list       # Services to mask
│   ├── mkinitcpio.conf                # Initramfs configuration
│   └── grub/
│       └── 40_custom-mini-linux       # GRUB menu entry
└── Makefile                           # Top-level build orchestration
```

## Build Requirements

The build process requires an existing Linux machine (the XPS 13 running Ubuntu works well).

- **OS:** Any Linux with `pacstrap` available (install `arch-install-scripts` on Ubuntu)
- **Disk:** ~10GB free for build workspace
- **Internet:** Required for downloading packages
- **Privileges:** Root/sudo for chroot, mounting, partitioning
- **Time:** ~30-60 minutes (mostly kernel compilation)

## Security Considerations

- UFW or nftables firewall enabled by default
- No SSH server installed (add manually if needed)
- Automatic screen lock after 5 min idle
- User account requires password for sudo
- UEFI Secure Boot: custom kernel needs signing, or disable Secure Boot

## Future Enhancements (Out of Scope for v1)

- Hibernate support (requires swap >= RAM or swap file)
- Fingerprint reader support (if XPS 13 has one)
- Automatic system updates via timer
- Snapper/btrfs snapshots for rollback (would require btrfs instead of ext4)
- Custom Plymouth boot splash
