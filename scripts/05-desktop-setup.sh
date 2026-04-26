#!/usr/bin/env bash
# 05-desktop-setup.sh — Configure XFCE 4 desktop defaults in rootfs.

source "$(dirname "$0")/common.sh"
require_root

log_info "=== XFCE 4 Desktop Setup ==="

if [[ ! -d "${ROOTFS}/usr" ]]; then
    log_error "Rootfs not found. Run 00-bootstrap.sh first."
    exit 1
fi

# Bind-mount rootfs so arch-chroot sees it as a real mountpoint
mount --bind "${ROOTFS}" "${ROOTFS}"
trap 'umount "${ROOTFS}" 2>/dev/null || true' EXIT

USER_HOME="${ROOTFS}/home/${MINI_LINUX_USER}"
CONFIG_HOME="${USER_HOME}/.config"
XFCONF_DIR="${CONFIG_HOME}/xfce4/xfconf/xfce-perchannel-xml"

mkdir -p "${CONFIG_HOME}" "${XFCONF_DIR}"

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

# --- LightDM greeter ---
log_info "Configuring LightDM greeter..."
mkdir -p "${ROOTFS}/etc/lightdm"
cat > "${ROOTFS}/etc/lightdm/lightdm-gtk-greeter.conf" <<EOF
[greeter]
theme-name=Adwaita-dark
icon-theme-name=Papirus-Dark
font-name=Noto Sans 11
cursor-theme-name=Adwaita
cursor-theme-size=24
background=#1e1e2e
EOF

# --- XFCE: appearance (GTK theme, icons, fonts) ---
log_info "Configuring XFCE appearance..."
cat > "${XFCONF_DIR}/xsettings.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xsettings" version="1.0">
  <property name="Net" type="empty">
    <property name="ThemeName" type="string" value="Adwaita-dark"/>
    <property name="IconThemeName" type="string" value="Papirus-Dark"/>
    <property name="CursorThemeName" type="string" value="Adwaita"/>
    <property name="CursorThemeSize" type="int" value="24"/>
  </property>
  <property name="Gtk" type="empty">
    <property name="FontName" type="string" value="Noto Sans 11"/>
    <property name="MonospaceFontName" type="string" value="JetBrainsMono Nerd Font 11"/>
    <property name="CursorThemeSize" type="int" value="24"/>
    <property name="DecorationLayout" type="string" value="menu:minimize,maximize,close"/>
  </property>
</channel>
EOF

# --- XFCE: window manager ---
log_info "Configuring XFWM4..."
cat > "${XFCONF_DIR}/xfwm4.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfwm4" version="1.0">
  <property name="general" type="empty">
    <property name="theme" type="string" value="Default-dark"/>
    <property name="title_font" type="string" value="Noto Sans Bold 11"/>
    <property name="button_layout" type="string" value="O|HMC"/>
    <property name="use_compositing" type="bool" value="true"/>
    <property name="frame_opacity" type="int" value="100"/>
    <property name="inactive_opacity" type="int" value="90"/>
  </property>
</channel>
EOF

# --- XFCE: desktop (solid colour, no icons on desktop) ---
log_info "Configuring XFCE desktop..."
cat > "${XFCONF_DIR}/xfce4-desktop.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-desktop" version="1.0">
  <property name="backdrop" type="empty">
    <property name="screen0" type="empty">
      <property name="monitorVirtual1" type="empty">
        <property name="workspace0" type="empty">
          <property name="color-style" type="int" value="0"/>
          <property name="rgba1" type="array">
            <value type="double" value="0.117647"/>
            <value type="double" value="0.117647"/>
            <value type="double" value="0.180392"/>
            <value type="double" value="1.000000"/>
          </property>
          <property name="image-style" type="int" value="0"/>
        </property>
      </property>
    </property>
  </property>
  <property name="desktop-icons" type="empty">
    <property name="style" type="int" value="0"/>
  </property>
</channel>
EOF

# --- XFCE: power manager ---
log_info "Configuring XFCE power manager..."
cat > "${XFCONF_DIR}/xfce4-power-manager.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-power-manager" version="1.0">
  <property name="xfce4-power-manager" type="empty">
    <property name="inactivity-on-ac" type="uint" value="60"/>
    <property name="inactivity-on-battery" type="uint" value="15"/>
    <property name="blank-on-ac" type="int" value="0"/>
    <property name="blank-on-battery" type="int" value="0"/>
    <property name="dpms-on-ac-sleep" type="uint" value="0"/>
    <property name="dpms-on-battery-sleep" type="uint" value="0"/>
    <property name="lid-action-on-ac" type="uint" value="1"/>
    <property name="lid-action-on-battery" type="uint" value="1"/>
    <property name="critical-power-action" type="uint" value="2"/>
    <property name="show-tray-icon" type="bool" value="true"/>
  </property>
</channel>
EOF

# --- XFCE: session (disable session saving for faster cold start) ---
log_info "Configuring XFCE session..."
cat > "${XFCONF_DIR}/xfce4-session.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-session" version="1.0">
  <property name="general" type="empty">
    <property name="SaveOnExit" type="bool" value="false"/>
    <property name="AutoSave" type="bool" value="false"/>
  </property>
  <property name="startup" type="empty">
    <property name="screensaver-off" type="bool" value="true"/>
  </property>
</channel>
EOF

# --- XFCE: keyboard shortcuts ---
log_info "Configuring XFCE keyboard shortcuts..."
cat > "${XFCONF_DIR}/xfce4-keyboard-shortcuts.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-keyboard-shortcuts" version="1.0">
  <property name="commands" type="empty">
    <property name="default" type="empty">
      <property name="&lt;Super&gt;t" type="string" value="xfce4-terminal"/>
      <property name="&lt;Super&gt;b" type="string" value="firefox"/>
      <property name="&lt;Super&gt;e" type="string" value="thunar"/>
      <property name="&lt;Super&gt;l" type="string" value="xflock4"/>
    </property>
    <property name="custom" type="empty">
      <property name="&lt;Super&gt;t" type="string" value="xfce4-terminal"/>
      <property name="&lt;Super&gt;b" type="string" value="firefox"/>
      <property name="&lt;Super&gt;e" type="string" value="thunar"/>
      <property name="&lt;Super&gt;l" type="string" value="xflock4"/>
    </property>
  </property>
</channel>
EOF

# --- Touchpad: tap-to-click, natural scroll via X11 ---
log_info "Configuring touchpad (libinput)..."
mkdir -p "${ROOTFS}/etc/X11/xorg.conf.d"
cat > "${ROOTFS}/etc/X11/xorg.conf.d/40-libinput.conf" <<'EOF'
Section "InputClass"
    Identifier "touchpad"
    MatchIsTouchpad "on"
    Driver "libinput"
    Option "Tapping" "on"
    Option "TappingButtonMap" "lrm"
    Option "NaturalScrolling" "true"
    Option "ScrollMethod" "twofinger"
    Option "DisableWhileTyping" "true"
EndSection
EOF

# Fix ownership using numeric UID/GID
USER_UID=$(grep "^${MINI_LINUX_USER}:" "${ROOTFS}/etc/passwd" | cut -d: -f3)
USER_GID=$(grep "^${MINI_LINUX_USER}:" "${ROOTFS}/etc/passwd" | cut -d: -f4)
if [[ -n "${USER_UID}" ]]; then
    chown -R "${USER_UID}:${USER_GID}" "${USER_HOME}"
else
    log_warn "Could not find UID for '${MINI_LINUX_USER}' — skipping chown"
fi

log_ok "XFCE 4 desktop configured."
umount "${ROOTFS}" 2>/dev/null || true
trap - EXIT
