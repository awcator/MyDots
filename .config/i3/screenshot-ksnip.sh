#!/bin/bash
mkdir -p ~/Pictures/screenshots
f=~/Pictures/screenshots/ksnip_$(date +%Y%m%d_%H%M%S).png

if [ "$1" == "-a" ]; then
    ksnip -a -p "$f"
    msg="Active window screenshot saved"
else
    ksnip -r -p "$f"
    msg="Screenshot saved"
fi

# Poll up to 15 seconds waiting for the file to be created
for i in {1..30}; do
    if [ -f "$f" ]; then
        xclip -selection clipboard -t image/png -i "$f"
        notify-send "$msg"
        break
    fi
    sleep 0.5
done
