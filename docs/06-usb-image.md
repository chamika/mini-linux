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
