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
