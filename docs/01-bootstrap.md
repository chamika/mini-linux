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
