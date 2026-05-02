#xrandr --setprovideroutputsource modesetting NVIDIA-G0
#xrandr --auto
#export DISPLAY=:0  # removed: was preventing multiple X sessions
export XDG_CURRENT_DESKTOP=i3
export GTK_USE_PORTAL=1
#export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus
#export GSK_RENDERER=cairo  # disabled - NVIDIA primary handles GTK4 GPU rendering

# Crash recovery: if sunshinemode crashed, restore real xorg config
XCONF_DIR="/etc/X11/xorg.conf.d"
if [ -f "$XCONF_DIR/10-nvidia-virtual.conf" ] && [ ! -f "$XCONF_DIR/10-nvidia-primary.conf" ]; then
    sudo mv "$XCONF_DIR/10-nvidia-virtual.conf" "$XCONF_DIR/10-nvidia-virtual.conf.disabled" 2>/dev/null
    sudo mv "$XCONF_DIR/10-nvidia-primary.conf.disabled" "$XCONF_DIR/10-nvidia-primary.conf" 2>/dev/null
fi

systemctl --user import-environment DISPLAY XAUTHORITY
dbus-update-activation-environment --systemd DISPLAY XAUTHORITY XDG_CURRENT_DESKTOP
xrandr --setprovideroutputsource modesetting NVIDIA-G0
xrandr --auto
sleep 2
# Find and enable the real external monitor (CND MAG 342CQ) if connected
EXT_MON=$(xrandr | grep " connected" | grep -v eDP | grep -v "1024x768" | head -1 | awk '{print $1}')
if [ -n "$EXT_MON" ]; then
    xrandr --output "$EXT_MON" --mode 3440x1440 --rate 100 --primary --right-of eDP-1 2>/dev/null || \
    xrandr --output "$EXT_MON" --auto --primary --right-of eDP-1 2>/dev/null
fi
exec i3
