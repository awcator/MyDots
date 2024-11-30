#!/bin/bash
#pactl set-sink-volume 0 0%
#sudo systemctl restart bluetooth.service
#blueman-applet &
#blueman-manager &
LANG=C pactl subscribe | grep --line-buffered "Event 'remove' on sink" | xargs -L 1 ~/bin/realpause
