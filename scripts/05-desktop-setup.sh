#!/usr/bin/env bash
# 05-desktop-setup.sh — Configure Hyprland desktop defaults in rootfs.

source "$(dirname "$0")/common.sh"
require_root

log_info "=== Hyprland Desktop Setup ==="

if [[ ! -d "${ROOTFS}/usr" ]]; then
    log_error "Rootfs not found. Run 00-bootstrap.sh first."
    exit 1
fi

# Bind-mount rootfs so arch-chroot sees it as a real mountpoint
mount --bind "${ROOTFS}" "${ROOTFS}"
trap 'umount "${ROOTFS}" 2>/dev/null || true' EXIT

USER_HOME="${ROOTFS}/home/${MINI_LINUX_USER}"
CONFIG_HOME="${USER_HOME}/.config"

mkdir -p "${CONFIG_HOME}"

# --- GTK Theme ---
log_info "Configuring GTK theme..."
mkdir -p "${CONFIG_HOME}/gtk-3.0"
cat > "${CONFIG_HOME}/gtk-3.0/settings.ini" <<EOF
[Settings]
gtk-theme-name=Adwaita-dark
gtk-icon-theme-name=Papirus-Dark
gtk-cursor-theme-name=Adwaita
gtk-cursor-theme-size=24
gtk-font-name=Noto Sans 11
gtk-application-prefer-dark-theme=1
EOF

mkdir -p "${CONFIG_HOME}/gtk-4.0"
cat > "${CONFIG_HOME}/gtk-4.0/settings.ini" <<EOF
[Settings]
gtk-application-prefer-dark-theme=1
gtk-icon-theme-name=Papirus-Dark
gtk-cursor-theme-name=Adwaita
gtk-cursor-theme-size=24
gtk-font-name=Noto Sans 11
EOF

# --- Autologin hook: launch Hyprland on tty1 ---
log_info "Writing .bash_profile autologin hook..."
cat >> "${USER_HOME}/.bash_profile" <<'EOF'

# Launch Hyprland automatically on tty1
if [[ -z "$WAYLAND_DISPLAY" && "$XDG_VTNR" == "1" ]]; then
    exec Hyprland
fi
EOF

# --- Hyprland config ---
log_info "Writing Hyprland config..."
mkdir -p "${CONFIG_HOME}/hypr"
cat > "${CONFIG_HOME}/hypr/hyprland.conf" <<'EOF'
# Monitor — auto-detect resolution and scale
monitor=,preferred,auto,1

# Autostart
exec-once = hyprpaper
exec-once = waybar
exec-once = swayidle -w timeout 900 'swaylock -f' timeout 1800 'systemctl suspend' before-sleep 'swaylock -f'
exec-once = /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1
exec-once = gnome-keyring-daemon --start --components=secrets

# Environment variables for Wayland compatibility
env = XCURSOR_THEME,Adwaita
env = XCURSOR_SIZE,24
env = GTK_THEME,Adwaita:dark

# Input
input {
    kb_layout = us
    follow_mouse = 1
    touchpad {
        natural_scroll = true
        tap-to-click = true
        scroll_method = two_finger
    }
    sensitivity = 0
}

# General appearance
general {
    gaps_in = 4
    gaps_out = 8
    border_size = 2
    col.active_border = rgb(cba6f7) rgb(89b4fa) 45deg
    col.inactive_border = rgb(313244)
    layout = dwindle
}

# Window decoration
decoration {
    rounding = 8
    blur {
        enabled = true
        size = 4
        passes = 2
    }
    drop_shadow = true
    shadow_range = 8
    shadow_render_power = 2
    col.shadow = rgba(1a1a2eee)
}

# Animations — simple and fast
animations {
    enabled = true
    bezier = easeOut, 0.05, 0.9, 0.1, 1.0
    animation = windows, 1, 3, easeOut, slide
    animation = fade, 1, 3, easeOut
    animation = workspaces, 1, 3, easeOut, slide
}

# Layout
dwindle {
    pseudotile = true
    preserve_split = true
}

# Miscellaneous
misc {
    force_default_wallpaper = 0
    disable_hyprland_logo = true
}

# Keybindings
$mod = SUPER

bind = $mod, Return, exec, foot
bind = $mod, B, exec, firefox
bind = $mod, E, exec, thunar
bind = $mod, Space, exec, wofi --show drun
bind = $mod, Q, killactive
bind = $mod SHIFT, Q, exit
bind = $mod, F, fullscreen
bind = $mod SHIFT, space, togglefloating

# Focus movement
bind = $mod, h, movefocus, l
bind = $mod, l, movefocus, r
bind = $mod, k, movefocus, u
bind = $mod, j, movefocus, d

# Window movement
bind = $mod SHIFT, h, movewindow, l
bind = $mod SHIFT, l, movewindow, r
bind = $mod SHIFT, k, movewindow, u
bind = $mod SHIFT, j, movewindow, d

# Workspace switching
bind = $mod, 1, workspace, 1
bind = $mod, 2, workspace, 2
bind = $mod, 3, workspace, 3
bind = $mod, 4, workspace, 4
bind = $mod, 5, workspace, 5

# Move window to workspace
bind = $mod SHIFT, 1, movetoworkspace, 1
bind = $mod SHIFT, 2, movetoworkspace, 2
bind = $mod SHIFT, 3, movetoworkspace, 3
bind = $mod SHIFT, 4, movetoworkspace, 4
bind = $mod SHIFT, 5, movetoworkspace, 5

# Mouse binds
bindm = $mod, mouse:272, movewindow
bindm = $mod, mouse:273, resizewindow

# Brightness and volume
bind = , XF86MonBrightnessUp, exec, brightnessctl set +5%
bind = , XF86MonBrightnessDown, exec, brightnessctl set 5%-
bind = , XF86AudioRaiseVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+
bind = , XF86AudioLowerVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-
bind = , XF86AudioMute, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
EOF

# --- Hyprpaper config (solid colour wallpaper) ---
log_info "Writing hyprpaper config..."
cat > "${CONFIG_HOME}/hypr/hyprpaper.conf" <<'EOF'
preload = /usr/share/backgrounds/mini-linux.png
wallpaper = ,/usr/share/backgrounds/mini-linux.png
EOF

# Create a solid-colour PNG as the wallpaper (1x1 pixel, scaled by hyprpaper)
# This avoids a dependency on imagemagick — write a minimal PNG directly via Python
arch-chroot "${ROOTFS}" python3 -c "
import struct, zlib, os
os.makedirs('/usr/share/backgrounds', exist_ok=True)
def png_1x1(r, g, b):
    def chunk(tag, data):
        c = zlib.crc32(tag + data) & 0xffffffff
        return struct.pack('>I', len(data)) + tag + data + struct.pack('>I', c)
    ihdr = struct.pack('>IIBBBBB', 1, 1, 8, 2, 0, 0, 0)
    idat_raw = b'\x00' + bytes([r, g, b])
    idat = zlib.compress(idat_raw)
    return b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', ihdr) + chunk(b'IDAT', idat) + chunk(b'IEND', b'')
with open('/usr/share/backgrounds/mini-linux.png', 'wb') as f:
    f.write(png_1x1(0x1e, 0x1e, 0x2e))
" 2>/dev/null || log_warn "Could not write wallpaper PNG — hyprpaper will show black background"

# --- Waybar config ---
log_info "Writing waybar config..."
mkdir -p "${CONFIG_HOME}/waybar"
cat > "${CONFIG_HOME}/waybar/config.json" <<'EOF'
{
    "layer": "top",
    "position": "top",
    "height": 28,
    "spacing": 4,
    "modules-left": ["hyprland/workspaces", "hyprland/window"],
    "modules-center": ["clock"],
    "modules-right": ["pulseaudio", "network", "battery", "tray"],
    "hyprland/workspaces": {
        "format": "{id}",
        "on-click": "activate"
    },
    "hyprland/window": {
        "max-length": 50
    },
    "clock": {
        "format": "{:%a %d %b  %H:%M}",
        "tooltip-format": "<tt>{calendar}</tt>"
    },
    "battery": {
        "states": {"warning": 30, "critical": 15},
        "format": "{capacity}% {icon}",
        "format-icons": ["", "", "", "", ""]
    },
    "network": {
        "format-wifi": "{essid} ",
        "format-ethernet": "eth ",
        "format-disconnected": "disconnected ⚠"
    },
    "pulseaudio": {
        "format": "{volume}% {icon}",
        "format-muted": "muted ",
        "format-icons": {"default": ["", "", ""]},
        "on-click": "pavucontrol"
    },
    "tray": {
        "spacing": 8
    }
}
EOF

cat > "${CONFIG_HOME}/waybar/style.css" <<'EOF'
* {
    font-family: "Noto Sans", sans-serif;
    font-size: 12px;
    border: none;
    border-radius: 0;
    min-height: 0;
}

window#waybar {
    background-color: #1e1e2e;
    color: #cdd6f4;
}

#workspaces button {
    padding: 0 8px;
    color: #6c7086;
    background: transparent;
}

#workspaces button.active {
    color: #cba6f7;
    border-bottom: 2px solid #cba6f7;
}

#clock, #battery, #network, #pulseaudio, #tray {
    padding: 0 10px;
    color: #cdd6f4;
}

#battery.warning { color: #f9e2af; }
#battery.critical { color: #f38ba8; }

#window {
    padding: 0 10px;
    color: #a6adc8;
}
EOF

# --- Wofi config ---
log_info "Writing wofi config..."
mkdir -p "${CONFIG_HOME}/wofi"
cat > "${CONFIG_HOME}/wofi/style.css" <<'EOF'
window {
    background-color: #1e1e2e;
    color: #cdd6f4;
    border: 1px solid #313244;
    border-radius: 8px;
}

#input {
    background-color: #313244;
    color: #cdd6f4;
    border: none;
    border-radius: 4px;
    padding: 6px 10px;
    margin: 6px;
}

#outer-box { padding: 6px; }

#entry {
    padding: 4px 10px;
    border-radius: 4px;
}

#entry:selected {
    background-color: #45475a;
}

#text { color: #cdd6f4; }
#text:selected { color: #cba6f7; }
EOF

# --- Foot terminal config ---
log_info "Writing foot config..."
mkdir -p "${CONFIG_HOME}/foot"
cat > "${CONFIG_HOME}/foot/foot.ini" <<'EOF'
[main]
font=JetBrainsMono Nerd Font:size=11
dpi-aware=yes

[colors]
background=1e1e2e
foreground=cdd6f4
regular0=45475a
regular1=f38ba8
regular2=a6e3a1
regular3=f9e2af
regular4=89b4fa
regular5=f5c2e7
regular6=94e2d5
regular7=bac2de
bright0=585b70
bright1=f38ba8
bright2=a6e3a1
bright3=f9e2af
bright4=89b4fa
bright5=f5c2e7
bright6=94e2d5
bright7=a6adc8
EOF

# Fix ownership using numeric UID/GID
USER_UID=$(grep "^${MINI_LINUX_USER}:" "${ROOTFS}/etc/passwd" | cut -d: -f3)
USER_GID=$(grep "^${MINI_LINUX_USER}:" "${ROOTFS}/etc/passwd" | cut -d: -f4)
if [[ -n "${USER_UID}" ]]; then
    chown -R "${USER_UID}:${USER_GID}" "${USER_HOME}"
else
    log_warn "Could not find UID for '${MINI_LINUX_USER}' — skipping chown"
fi

log_ok "Hyprland desktop configured."
umount "${ROOTFS}" 2>/dev/null || true
trap - EXIT
