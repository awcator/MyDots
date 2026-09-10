#!/bin/bash
# one_time_setup.sh
# A collection of one-time setup activities and fixes.
# All activities are separated into individual functions.

# Fix xdg-open defaults for various file types
fix_mime_defaults() {
    echo "Setting feh for static images (png, jpeg, jpg, webp)..."
    xdg-mime default feh.desktop image/png image/jpeg image/jpg image/webp

    echo "Setting mpv for animated GIFs and video formats..."
    xdg-mime default mpv.desktop image/gif video/mp4 video/x-matroska video/webm

    echo "Setting Evince for PDF documents..."
    xdg-mime default org.gnome.Evince.desktop application/pdf

    echo "Setting Brave for web formats..."
    xdg-mime default brave-browser.desktop text/html application/xhtml+xml x-scheme-handler/http x-scheme-handler/https

    echo "Done updating MIME defaults."
}

# ---------------------------------------------------------
# Add future one-time activities below as new functions
# ---------------------------------------------------------
# example_setup_task() {
#     echo "Doing some setup..."
# }



protect_sensitive_files() {
    echo "Protecting sensitive dotfiles and directories from unwanted modifications..."
    
    # List of files and directories to protect
    # Core configuration files and directories to lock down
    local targets=(
        # Shell and environment profiles
        ~/.bashrc
        ~/.bash_profile
        ~/.bash_aliases
        ~/.zshrc
        ~/.xinitrc
        
        # Startup and service configurations
        ~/.config/autostart
        ~/.config/systemd/user
        
        # Dynamically include ALL SSH files (keys, configs, etc.)
        ~/.ssh/*
        
        # Application configs and secrets
        ~/.tmux.conf
        ~/.inputrc
        ~/.claude/settings.json
        ~/.otp_secrets
    )
    
    for target in "${targets[@]}"; do
        # Skip known_hosts so normal SSH connections don't break when connecting to new servers
        if [[ "$target" == *"/.ssh/known_hosts"* ]]; then
            continue
        fi

        # Resolve the real path in case it's a symlink
        local real_path="$target"
        if [ -L "$real_path" ]; then
            real_path=$(readlink -f "$real_path")
        fi
        
        if [ -e "$real_path" ]; then
            echo "Making $real_path immutable..."
            sudo chattr -R +i "$real_path" 2>/dev/null || sudo chattr +i "$real_path"
        else
            echo "Skipping $target: not found."
        fi
    done
    
    echo "Done protecting sensitive files."
}

# =========================================================
# Main execution logic

# =========================================================

show_help() {
    echo "Usage: $0 [function_name | --all]"
    echo ""
    echo "Run a specific setup task or all of them."
    echo ""
    echo "Available activities:"
    declare -F | awk '{print $3}' | grep -v 'show_help' | sed 's/^/  - /'
}

# If no arguments are provided (or -h/--help), show help dialog
if [ -z "$1" ] || [ "$1" == "--help" ] || [ "$1" == "-h" ]; then
    show_help
    exit 1
fi

# Run all functions if --all is passed
if [ "$1" == "--all" ]; then
    echo "Running all one-time setup activities..."
    echo "========================================"
    for func in $(declare -F | awk '{print $3}' | grep -v 'show_help'); do
        echo -e "\n---> Running: $func"
        "$func"
    done
    echo -e "\n========================================"
    echo "All tasks completed!"
    exit 0
fi

# Check if the provided argument is a valid function
if declare -f "$1" > /dev/null && [ "$1" != "show_help" ]; then
    # Call the function
    "$1"
else
    echo "Error: '$1' is not a known function."
    echo ""
    show_help
    exit 1
fi
