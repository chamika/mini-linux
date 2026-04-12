# Step 3: Packages

## What Gets Installed

### Desktop Environment (~120MB)
Hyprland compositor, Waybar status bar, Wofi launcher, Mako notifications, screen lock, wallpaper utility, screenshot tools.

### Applications (~250MB)
- **Kitty** — GPU-accelerated terminal with native splits
- **Thunar** — Lightweight file manager with thumbnail support
- **Google Chrome** — Built from AUR

### Audio (~5MB)
PipeWire JACK bridge and PulseAudio volume control (PipeWire base installed in bootstrap).

### Fonts & Theming (~150MB)
Noto fonts (full Unicode), JetBrains Mono Nerd Font (terminal/bar), Papirus icons, Qt Wayland support.

### System Utilities (~30MB)
TLP (battery), brightness/media controls, Bluetooth manager, firewall, archive tools.

## Running

```bash
make packages
```

## Adding More Packages Later

After installing to NVMe and booting into mini-linux:
```bash
sudo pacman -S <package-name>
```

For AUR packages, install an AUR helper first:
```bash
sudo pacman -S --needed git base-devel
git clone https://aur.archlinux.org/yay-bin.git
cd yay-bin && makepkg -si
yay -S visual-studio-code-bin
```
