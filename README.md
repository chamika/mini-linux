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
