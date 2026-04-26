# Step 3: Packages

## What Gets Installed

### Desktop Environment (~400MB)
XFCE 4 desktop with panel, window manager, and goodies pack. LightDM display manager with GTK greeter. Xorg server with libinput touchpad driver. xdg-desktop-portal-gtk for file dialogs and notifications. polkit agent and gnome-keyring for credentials.

### Applications (~100MB)
- **Firefox** — Fast, privacy-respecting web browser (from official repos)
- **Thunar** — XFCE file manager with volume and thumbnail support (included in xfce4-goodies)
- **xfce4-terminal** — Lightweight terminal emulator (included in xfce4-goodies)

### Audio (~5MB)
PipeWire JACK bridge and PulseAudio volume control (PipeWire base installed in bootstrap).

### Fonts & Theming (~150MB)
Noto fonts (full Unicode), JetBrains Mono Nerd Font, Papirus icons, GTK3/GTK4 theme support.

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
