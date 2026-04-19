# Step 5: Boot Optimization

## Target: <7 seconds (UEFI POST to GNOME ready)

## What We Optimize

### 1. Unified Kernel Image — UKI (saves ~3.5s)

Instead of loading the kernel, initramfs, and microcode as separate files,
we bundle them into a **single EFI executable** (`.efi` file). This is the
same technique used by BlendOS to eliminate the "Initrd" phase entirely.

Our `06-boot-optimize.sh` uses `systemd-ukify` (via mkinitcpio) to produce:
- `/boot/EFI/Linux/mini-linux.efi` — the UKI (kernel + initramfs + cmdline + microcode)
- `/boot/initramfs-mini-linux.img` — traditional initramfs (GRUB fallback)

The UKI is booted directly by **systemd-boot** (USB) or a **direct UEFI boot
entry** (NVMe), completely bypassing GRUB and eliminating the separate initrd
loading phase.

### 2. systemd-boot (saves ~4.5s vs GRUB)

The USB image uses **systemd-boot** instead of GRUB:
- Near-zero overhead (~0ms vs GRUB's 1-5s)
- Auto-discovers UKI files in `EFI/Linux/`
- `timeout 0` — boots immediately

For NVMe dual-boot, a **direct UEFI boot entry** is registered via
`efibootmgr`. GRUB is kept as a fallback for selecting Ubuntu.

### 3. Kernel Optimizations (saves ~0.5s)

- **LZ4 kernel compression** — decompresses ~2x faster than zstd
- **Built-in drivers** — NVMe, i915, ext4, HID are compiled into the kernel
  (not modules), so the initramfs doesn't need to load them
- **Built-in cmdline** — fallback command line embedded in kernel binary

### 4. Initramfs (saves ~1s)

Our `mkinitcpio.conf` uses:
- **systemd hook** instead of busybox (parallel init inside initramfs)
- **autodetect** — only includes modules for hardware actually present
- **Empty MODULES=()** — all boot-critical drivers are built into the kernel
- **No kms hook** — i915 is built-in, modesetting happens automatically
- **lz4 compression** — fastest decompression

### 5. Kernel Command Line (saves ~0.5s)

- `quiet loglevel=3` — suppress boot messages
- `nowatchdog nmi_watchdog=0` — disable hardware watchdog checks
- `tsc=reliable` — skip TSC calibration delay

### 6. systemd Services (saves ~1-2s)

Masked services (in `config/systemd/masked-services.list`):
- `lvm2-monitor` — no LVM on this system
- `remote-fs.target` — no network mounts
- `ModemManager` — no cellular modem

Socket-activated (start on demand, not at boot):
- PipeWire (starts when an app needs audio)
- BlueZ (starts when Bluetooth is used)

### 7. Filesystem (saves ~0.3s)

- `/tmp` mounted as tmpfs (no disk I/O for temp files)
- NVMe scheduler set to `none` (NVMe has internal scheduling)
- Journal size capped at 50MB

## Boot Architecture

```
USB Boot:
  UEFI → systemd-boot → UKI (kernel+initrd+cmdline) → systemd → GNOME
  ~11s    ~0s             ~1.5s                         ~3.5s     = ~16s

NVMe Boot:
  UEFI → Direct EFI entry → UKI → systemd → GNOME
  ~11s   ~0s                 ~1.5s  ~3.5s     = ~16s

NVMe Fallback (dual-boot):
  UEFI → GRUB → kernel + initrd → systemd → GNOME
  ~11s   ~1s    ~3.5s              ~3.5s     = ~19s
```

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

**Note:** With UKI, `systemd-analyze` shows the kernel+initrd as a single
"Kernel" time — the separate "Initrd" line disappears because the initramfs
is embedded in the kernel image.
