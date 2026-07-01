#!/bin/bash
# Backup .bash_history daily, keep last 30 copies
BACKUP_DIR="$HOME/.bash_history_backups"
mkdir -p "$BACKUP_DIR"

# Full copy with date
cp "$HOME/.bash_history" "$BACKUP_DIR/bash_history_$(date +%Y%m%d_%H%M%S)"

# Remove backups older than 90 days
find "$BACKUP_DIR" -name "bash_history_*" -mtime +90 -delete
