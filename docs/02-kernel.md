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
