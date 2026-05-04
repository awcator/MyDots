#!/usr/bin/env bash
# Rofi Power Menu — Fullscreen Blur

# Confirmation dialog
confirm_action() {
    local ans
    ans=$(echo -e "✅  Yes\n❌  No" | rofi -dmenu \
        -i \
        -p "Are you sure?" \
        -theme ~/.config/rofi/powermenu-confirm.rasi \
    )
    [[ "$ans" == *"Yes"* ]] && return 0 || return 1
}

# Uptime
uptime_info=$(uptime -p | sed 's/up //')

# Menu entries with emojis
options="🔒  Lock\n🚪  Logout\n💤  Sleep\n❄️  Hibernate\n🔄  Reboot\n⏻  Shutdown"

chosen=$(echo -e "$options" | rofi -dmenu \
    -i \
    -p "Power" \
    -mesg "🕐 Uptime: $uptime_info" \
    -theme ~/.config/rofi/powermenu.rasi \
    -theme-str 'listview { columns: 6; lines: 1; }' \
)

case "$chosen" in
    *Lock*)
        betterlockscreen -l dimblur --off 10
        ;;
    *Logout*)
        confirm_action && i3-msg exit
        ;;
    *Sleep*)
        confirm_action && (betterlockscreen -l dimblur --off 10 & sleep 1 && systemctl suspend)
        ;;
    *Hibernate*)
        confirm_action && systemctl hibernate
        ;;
    *Reboot*)
        confirm_action && systemctl reboot
        ;;
    *Shutdown*)
        confirm_action && systemctl poweroff
        ;;
    *)
        exit 0
        ;;
esac
