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
