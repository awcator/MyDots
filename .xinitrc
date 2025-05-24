#xrandr --setprovideroutputsource modesetting NVIDIA-0
#xrandr --auto
export DISPLAY=:0
export XDG_CURRENT_DESKTOP=i3
export GTK_USE_PORTAL=1
#export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus
export GSK_RENDERER=cairo

systemctl --user import-environment DISPLAY XAUTHORITY
dbus-update-activation-environment --systemd DISPLAY XAUTHORITY XDG_CURRENT_DESKTOP
exec i3
