#xrandr --setprovideroutputsource modesetting NVIDIA-G0
#xrandr --auto
#export DISPLAY=:0  # removed: was preventing multiple X sessions
export XDG_CURRENT_DESKTOP=i3
export GTK_USE_PORTAL=1
#export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus
#export GSK_RENDERER=cairo  # disabled - NVIDIA primary handles GTK4 GPU rendering

# Crash recovery: if sunshinemode left the virtual config active, warn only.
# Do NOT sudo here - .xinitrc runs inside the X session with no controlling
# terminal, so a password prompt has nowhere to go and fails with
# "x11 failed to open". sunshinemode does the actual recovery at startup,
# from the tty where it can prompt.
XCONF_DIR="/etc/X11/xorg.conf.d"
if [ -f "$XCONF_DIR/10-nvidia-virtual.conf" ] && [ ! -f "$XCONF_DIR/10-nvidia-primary.conf" ]; then
    echo ".xinitrc: virtual xorg config still active - run sunshinemode to restore" >&2
fi

systemctl --user import-environment DISPLAY XAUTHORITY
dbus-update-activation-environment --systemd DISPLAY XAUTHORITY XDG_CURRENT_DESKTOP

# PRIME output offload, only when NVIDIA-G0 advertises "Source Output".
# Under sunshinemode's virtual config the provider is Sink-Output-only, and this
# call then fails BadValue and leaves outputs half-configured ("Configure crtc N failed").
if xrandr --listproviders 2>/dev/null | grep 'NVIDIA-G0' | grep -q 'Source Output'; then
    xrandr --setprovideroutputsource modesetting NVIDIA-G0 && xrandr --auto
fi

sleep 2
# Find and enable the real external monitor (CND MAG 342CQ) if connected.
# The mm filter skips virtual/Sunshine outputs, which report no physical size.
EXT_MON=$(xrandr | grep " connected" | grep -v eDP | grep "[1-9][0-9][0-9]mm" | head -1 | awk '{print $1}')
if [ -n "$EXT_MON" ]; then
    xrandr --output "$EXT_MON" --mode 3440x1440 --rate 100 --primary --right-of eDP-1 2>/dev/null || \
    xrandr --output "$EXT_MON" --auto --primary --right-of eDP-1 2>/dev/null
fi
exec i3
