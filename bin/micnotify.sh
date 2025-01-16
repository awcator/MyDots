#!/bin/bash

# Get the default microphone name
get_default_mic() {
  pactl info | grep "Default Source:" | awk '{print $3}'
}

# Get the mute status of the default microphone
get_mic_status() {
  pactl list sources | grep -A 10 "$(get_default_mic)" | grep "Mute:" | awk '{print $2}'
}

# Monitor microphone state
previous_status=$(get_mic_status)

pactl subscribe | while read -r event; do
  # Check if the event relates to the default microphone source
  if [[ $event == *"source #"* ]]; then
    current_status=$(get_mic_status)

    if [[ $current_status == "no" && $previous_status != "no" ]]; then
      notify-send -i /usr/share/icons/breeze/status/24/mic-on.svg "Microphone Activated" "Your microphone is now ON."
    elif [[ $current_status == "yes" && $previous_status != "yes" ]]; then
      notify-send -i /usr/share/icons/breeze/status/24/mic-off.svg "Microphone Deactivated" "Your microphone is now OFF."
    fi

    # Update the previous status
    previous_status=$current_status
  fi
done
