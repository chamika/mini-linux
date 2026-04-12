# Step 4: Configuration

## What This Configures

| Setting | Value | Change by |
|---------|-------|-----------|
| Timezone | UTC | Edit `04-configure.sh` or run `timedatectl set-timezone <zone>` after boot |
| Locale | en_US.UTF-8 | Edit `04-configure.sh` |
| Hostname | mini-linux | Set `MINI_LINUX_HOSTNAME=myhost` environment variable |
| Username | user | Set `MINI_LINUX_USER=myname` environment variable |
| Default password | Same as username | **Change on first boot!** Run `passwd` |

## Services Enabled

| Service | Purpose |
|---------|---------|
| NetworkManager | WiFi and ethernet management |
| bluetooth | Bluetooth device support |
| tlp | Battery power optimization |
| nftables | Firewall |
| systemd-timesyncd | Time synchronization |

## Services Masked

Services in `config/systemd/masked-services.list` are masked (permanently disabled). Edit that file to change which services are masked.

## Autologin Flow

```
Boot → systemd → getty@tty1 (autologin) → .bash_profile → Hyprland
```

No display manager (GDM/SDDM/LightDM) is used. The user is logged in directly to TTY1, and `.bash_profile` launches Hyprland automatically. This saves 1-2 seconds on boot.

## Customization

```bash
# Change username
MINI_LINUX_USER=chamika make configure

# Change hostname
MINI_LINUX_HOSTNAME=mybox make configure
```
