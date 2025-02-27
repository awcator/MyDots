export DISPLAY=:0
export XDG_CURRENT_DESKTOP=i3
export GTK_USE_PORTAL=1
export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus
exec i3
