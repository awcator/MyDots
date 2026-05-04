#!/usr/bin/env bash
# OSD notifications for volume & brightness using dunst progress bar

VOLUME_ID=2593
BRIGHTNESS_ID=2594
VOLUME_STEP=5
BRIGHTNESS_STEP=10

get_volume() {
    pactl get-sink-volume @DEFAULT_SINK@ | grep -oP '\d+%' | head -1 | tr -d '%'
}

get_mute() {
    pactl get-sink-mute @DEFAULT_SINK@ | grep -oP '(yes|no)'
}

get_brightness() {
    brightnessctl -m | grep -oP '\d+(?=%)'
}

get_all_sinks_status() {
    local default_sink_name
    default_sink_name=$(pactl get-default-sink 2>/dev/null)
    local result=""
    while IFS=$'\t' read -r idx name driver format state; do
        local vol mute mute_str short_name is_default=""
        vol=$(pactl get-sink-volume "$idx" 2>/dev/null | grep -oP '\d+%' | head -1 | tr -d '%')
        mute=$(pactl get-sink-mute "$idx" 2>/dev/null | grep -oP '(yes|no)')
        # Friendly short name
        if [[ "$name" == *Speaker* ]]; then
            short_name="Speaker"
        elif [[ "$name" == *HDMI1* ]]; then
            short_name="HDMI1"
        elif [[ "$name" == *HDMI2* ]]; then
            short_name="HDMI2"
        elif [[ "$name" == *HDMI3* ]]; then
            short_name="HDMI3"
        elif [[ "$name" == *Headphones* || "$name" == *headphone* ]]; then
            short_name="Headphones"
        elif [[ "$name" == *bluez* || "$name" == *bluetooth* ]]; then
            short_name="Bluetooth"
        else
            short_name="${name##*.}"
        fi
        # Mark default sink
        if [[ "$name" == "$default_sink_name" ]]; then
            is_default=" ★"
        fi
        # Build status string
        if [[ "$mute" == "yes" ]]; then
            mute_str="🔇MUTED"
        else
            mute_str="${vol}%"
        fi
        result+="${short_name}${is_default}: ${mute_str} [${state}]\n"
    done < <(pactl list sinks short 2>/dev/null)
    echo -e "$result"
}

get_all_sources_status() {
    local default_source_name
    default_source_name=$(pactl get-default-source 2>/dev/null)
    local result=""
    while IFS=$'\t' read -r idx name driver format state; do
        # Skip monitor sources (they mirror sinks)
        [[ "$name" == *".monitor" ]] && continue
        local vol mute mute_str short_name is_default=""
        vol=$(pactl get-source-volume "$idx" 2>/dev/null | grep -oP '\d+%' | head -1 | tr -d '%')
        mute=$(pactl get-source-mute "$idx" 2>/dev/null | grep -oP '(yes|no)')
        # Friendly short name
        if [[ "$name" == *Mic1* ]]; then
            short_name="Mic1"
        elif [[ "$name" == *Mic2* ]]; then
            short_name="Mic2"
        elif [[ "$name" == *bluez* || "$name" == *bluetooth* ]]; then
            short_name="BT-Mic"
        else
            short_name="${name##*.}"
        fi
        if [[ "$name" == "$default_source_name" ]]; then
            is_default=" ★"
        fi
        if [[ "$mute" == "yes" ]]; then
            mute_str="🔇MUTED"
        else
            mute_str="${vol}%"
        fi
        result+="${short_name}${is_default}: ${mute_str} [${state}]\n"
    done < <(pactl list sources short 2>/dev/null)
    echo -e "$result"
}

notify_volume() {
    local vol mute icon body
    vol=$(get_volume)
    mute=$(get_mute)

    if [[ "$mute" == "yes" ]]; then
        icon="🔇"
    elif (( vol >= 60 )); then
        icon="🔊"
    elif (( vol >= 30 )); then
        icon="🔉"
    else
        icon="🔈"
    fi

    # Build the full status body
    body="<b>── Sinks (Output) ──</b>\n$(get_all_sinks_status)\n<b>── Sources (Input) ──</b>\n$(get_all_sources_status)"

    if [[ "$mute" == "yes" ]]; then
        dunstify -a "osd" -r "$VOLUME_ID" -u low -h "int:value:$vol" "$icon  Muted" "$body"
    else
        dunstify -a "osd" -r "$VOLUME_ID" -u low -h "int:value:$vol" "$icon  $vol%" "$body"
    fi
}

notify_brightness() {
    local bri icon
    bri=$(get_brightness)

    if (( bri >= 50 )); then
        icon="☀️"
    else
        icon="🔅"
    fi

    dunstify -a "osd" -r "$BRIGHTNESS_ID" -u low -h "int:value:$bri" "$icon  $bri%"
}

case "$1" in
    vol-up)
        for i in $(seq 0 10); do pactl set-sink-volume "$i" "+${VOLUME_STEP}%" 2>/dev/null; done
        notify_volume
        ;;
    vol-down)
        for i in $(seq 0 10); do pactl set-sink-volume "$i" "-${VOLUME_STEP}%" 2>/dev/null; done
        notify_volume
        ;;
    vol-mute)
        for i in $(seq 0 10); do pactl set-sink-mute "$i" toggle 2>/dev/null; done
        notify_volume
        ;;
    mic-mute)
        for i in $(seq 0 10); do pactl set-source-mute "$i" toggle 2>/dev/null; done
        local mic_mute mic_icon mic_body
        mic_mute=$(pactl get-source-mute @DEFAULT_SOURCE@ 2>/dev/null | grep -oP '(yes|no)')
        if [[ "$mic_mute" == "yes" ]]; then
            mic_icon="🎙️  Mic Muted"
        else
            mic_icon="🎙️  Mic On"
        fi
        mic_body="<b>── Sinks (Output) ──</b>\n$(get_all_sinks_status)\n<b>── Sources (Input) ──</b>\n$(get_all_sources_status)"
        dunstify -a "osd" -r "$VOLUME_ID" -u low "$mic_icon" "$mic_body"
        ;;
    bright-up)
        brightnessctl set "+${BRIGHTNESS_STEP}%"
        notify_brightness
        ;;
    bright-down)
        brightnessctl set "${BRIGHTNESS_STEP}%-"
        notify_brightness
        ;;
    *)
        echo "Usage: $0 {vol-up|vol-down|vol-mute|mic-mute|bright-up|bright-down}"
        exit 1
        ;;
esac
