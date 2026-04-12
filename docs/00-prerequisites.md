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
sudo apt install -y arch-install-scripts qemu-utils dosfstools e2fsprogs parted wget rsync

# Verify pacstrap is available
which pacstrap
```

## Disk Space

- ~10GB free for the build workspace (`/tmp/mini-linux-build/`)
- 30-50GB unallocated NVMe space for the final install (check with `lsblk`)

## Network

The build process downloads ~2GB of packages. A stable internet connection is required.
