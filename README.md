# Mini-Linux

A minimal, fast-booting Linux distribution built on Arch Linux for the Dell XPS 13 9380.

## What You Get

- **<7 second cold boot** to a modern Wayland desktop
- **Hyprland** desktop environment (Wayland tiling compositor)
- **Firefox**, **Thunar** file manager, **foot** terminal
- Full hardware support: WiFi, Bluetooth, audio, camera, touchpad
- Dual-boots alongside Ubuntu via GRUB

## Architecture

```
┌─────────────────────────────────────────────┐
│  Firefox · Thunar · foot terminal           │
├─────────────────────────────────────────────┤
│  Hyprland + Waybar (TTY autologin)          │
├─────────────────────────────────────────────┤
│  systemd · NetworkManager · PipeWire        │
├─────────────────────────────────────────────┤
│  Unified Kernel Image (kernel+initrd+cmd)   │
├─────────────────────────────────────────────┤
│  systemd-boot / Direct UEFI boot            │
└─────────────────────────────────────────────┘
```

## Prerequisites

- Dell XPS 13 9380 (or similar Intel laptop) booted into Ubuntu
- ~10 GB free space in `/tmp` for the build workspace
- 30–50 GB unallocated NVMe space for the final install (check with `lsblk`)
- USB flash drive (8 GB+) for testing
- Stable internet connection (~2 GB of packages downloaded during build)

## Step 1 — Set up the host (run once)

This installs `pacman`, `pacstrap`, and other build tools on your Ubuntu host.
**Must be run before anything else.**

```bash
git clone <this-repo> && cd mini-linux
make setup
```

`make setup` will:
1. Install Ubuntu build dependencies (`arch-install-scripts`, `parted`, `qemu-utils`, etc.)
2. Build and install `pacman` from source (not available in Ubuntu repos)
3. Write `/etc/pacman.conf` with Arch Linux mirror entries
4. Download and install the Arch Linux keyring
5. Initialise the pacman GPG keyring and sync the package databases

## Step 2 — Build

### Full automated build

Runs all stages in order and produces a bootable USB image at `build/mini-linux.img`:

```bash
make all
```

### Step-by-step build

Run each stage manually if you want more control or need to re-run a single step:

| Step | Command | What it does |
|------|---------|--------------|
| 1 | `make bootstrap` | Creates the Arch Linux base rootfs (~2.3 GB) |
| 2 | `make kernel-config` | Downloads Linux source and sets up `.config` for the XPS 13 |
| 3 | `make kernel` | Compiles the kernel and installs it into the rootfs |
| 4 | `make packages` | Installs Hyprland, Waybar, Firefox, Thunar, PipeWire, etc. |
| 5 | `make configure` | Sets locale, timezone, hostname, user account, TTY autologin |
| 6 | `make desktop` | Configures Hyprland, Waybar, Wofi, foot, GTK theme |
| 7 | `make boot-optimize` | Strips initramfs, tunes systemd/journal, configures NVMe scheduler |
| 8 | `make usb-image` | Packages the rootfs into a bootable 8 GB USB image |

> **Note:** `make kernel-config` must be run before `make kernel`. If you skip it, the kernel build will fail with *"No kernel .config found"*.

#### About `make kernel-config`

- If `config/kernel/xps13-9380.config` exists it is used directly.
- Otherwise, the script generates a config from the **running** kernel using `localmodconfig`. For best results, run it on the target XPS 13 hardware with WiFi, Bluetooth, audio, and USB devices active.

## Step 3 — Test on USB

```bash
# Find your USB device
lsblk

# Flash the image (replace /dev/sdX with your USB drive)
sudo dd if=build/mini-linux.img of=/dev/sdX bs=4M status=progress
```

Boot from the USB to verify everything works before writing to NVMe.

**Default credentials:** username `user`, password `user` — change with `passwd` after first login.

## Step 4 — Install to NVMe (dual-boot)

> **Before running this step**, use GParted or `fdisk` to create unallocated partitions on your NVMe drive (30–50 GB for root, optional swap).

```bash
make install
```

The installer will:
1. Show current NVMe partition layout
2. Prompt for the target root and swap partitions
3. Format, copy the rootfs, and write `/etc/fstab`
4. Install the kernel and initramfs to the shared ESP (`/EFI/mini-linux/`)
5. Add a `Mini-Linux` entry to Ubuntu's GRUB and run `update-grub`

Reboot and select **Mini-Linux** from the GRUB menu.

## Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `MINI_LINUX_USER` | `user` | Username created in the rootfs |
| `MINI_LINUX_HOSTNAME` | `mini-linux` | Hostname written to `/etc/hostname` |
| `KERNEL_VERSION` | `6.12` | Linux kernel version to build |
| `BUILD_DIR` | `/var/tmp/mini-linux-build` | Scratch space for rootfs and kernel source |
| `IMAGE_SIZE` | `8G` | Size of the USB image |

Override on the command line, e.g.:

```bash
make configure MINI_LINUX_USER=chamika MINI_LINUX_HOSTNAME=mini
```

## Cleaning up

```bash
make clean   # removes /var/tmp/mini-linux-build (does not touch build/mini-linux.img)
```

## Documentation

Detailed notes for each stage are in [docs/](docs/).

## License

MIT
