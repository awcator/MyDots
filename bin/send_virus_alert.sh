#!/bin/bash
# ClamAV Virus Event Handler — Desktop notification + structured log + forensics
export DISPLAY=:0

FILENAME="$CLAM_VIRUSEVENT_FILENAME"
VIRUSNAME="$CLAM_VIRUSEVENT_VIRUSNAME"
TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
LOG_FILE="/home/awcator/Documents/log/clamav/virus_alert.log"
JSON_LOG="/home/awcator/Documents/log/clamav/virus_alert.json"

# ─── Gather forensic context ────────────────────────────────────────────────
FILE_HASH=""
FILE_SIZE=""
FILE_TYPE=""
FILE_OWNER=""

if [[ -f "$FILENAME" ]]; then
    FILE_HASH=$(sha256sum "$FILENAME" 2>/dev/null | awk '{print $1}')
    FILE_SIZE=$(stat -c%s "$FILENAME" 2>/dev/null)
    FILE_TYPE=$(file -b "$FILENAME" 2>/dev/null | head -c 80)
    FILE_OWNER=$(stat -c '%U:%G' "$FILENAME" 2>/dev/null)
fi

# ─── Classify threat severity ───────────────────────────────────────────────
SEVERITY="MEDIUM"
ICON="/usr/share/icons/breeze-dark/status/64/security-medium.svg"

case "$VIRUSNAME" in
    *Dropper*|*Backdoor*|*Trojan*|*Rootkit*|*Exploit*)
        SEVERITY="CRITICAL"
        ICON="/usr/share/icons/breeze-dark/status/64/security-low.svg"
        ;;
    *Malware*|*Worm*|*Ransomware*|*Miner*)
        SEVERITY="HIGH"
        ICON="/usr/share/icons/breeze-dark/status/64/security-low.svg"
        ;;
    *PUA*|*Adware*|*Heuristics*)
        SEVERITY="LOW"
        ICON="/usr/share/icons/breeze-dark/status/64/security-high.svg"
        ;;
esac

# ─── Format human-readable size ─────────────────────────────────────────────
HUMAN_SIZE=""
if [[ -n "$FILE_SIZE" ]]; then
    if (( FILE_SIZE > 1048576 )); then
        HUMAN_SIZE="$(( FILE_SIZE / 1048576 ))MB"
    elif (( FILE_SIZE > 1024 )); then
        HUMAN_SIZE="$(( FILE_SIZE / 1024 ))KB"
    else
        HUMAN_SIZE="${FILE_SIZE}B"
    fi
fi

# ─── Desktop notification ───────────────────────────────────────────────────
NOTIFY_BODY="<b>Severity:</b> ${SEVERITY}
<b>Threat:</b> ${VIRUSNAME}
<b>File:</b> $(basename "$FILENAME")
<b>Path:</b> ${FILENAME}"

if [[ -n "$FILE_HASH" ]]; then
    NOTIFY_BODY="${NOTIFY_BODY}
<b>SHA256:</b> ${FILE_HASH:0:16}...
<b>Size:</b> ${HUMAN_SIZE} | <b>Type:</b> ${FILE_TYPE:0:40}"
fi

NOTIFY_BODY="${NOTIFY_BODY}
<b>Action:</b> Quarantined + blocked"

sudo -u awcator \
    DISPLAY=:0 \
    DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus \
    notify-send \
    -i "$ICON" \
    -u critical \
    -t 0 \
    -h "string:x-dunst-stack-tag:clamav" \
    "THREAT DETECTED [$SEVERITY]" \
    "$NOTIFY_BODY"

# ─── Play alert sound ───────────────────────────────────────────────────────
if command -v paplay &>/dev/null; then
    sudo -u awcator \
        XDG_RUNTIME_DIR=/run/user/1000 \
        paplay /usr/share/sounds/freedesktop/stereo/dialog-warning.oga 2>/dev/null &
fi

# ─── Structured text log ────────────────────────────────────────────────────
{
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "[$TIMESTAMP] THREAT DETECTED — Severity: $SEVERITY"
    echo "  Virus:   $VIRUSNAME"
    echo "  File:    $FILENAME"
    echo "  Hash:    ${FILE_HASH:-N/A (file already removed)}"
    echo "  Size:    ${HUMAN_SIZE:-N/A}"
    echo "  Type:    ${FILE_TYPE:-N/A}"
    echo "  Owner:   ${FILE_OWNER:-N/A}"
    echo "  Action:  Quarantined → ~/Documents/log/clamav/quarantine/"
} >> "$LOG_FILE"

# ─── JSON log (machine-parseable for forensics) ─────────────────────────────
printf '{"timestamp":"%s","severity":"%s","virus":"%s","file":"%s","sha256":"%s","size":"%s","type":"%s","owner":"%s","action":"quarantined"}\n' \
    "$TIMESTAMP" "$SEVERITY" "$VIRUSNAME" "$FILENAME" \
    "${FILE_HASH:-}" "${FILE_SIZE:-}" "${FILE_TYPE:-}" "${FILE_OWNER:-}" \
    >> "$JSON_LOG"
