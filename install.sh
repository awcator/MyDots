#!/usr/bin/env bash
# install.sh — Sync & deploy dotfiles from this repo to $HOME
#
# Usage:
#   ./install.sh              # Sync system→repo, then symlink repo→home
#   ./install.sh --prefer-repo  # Force repo versions (skip sync, remove existing)
#   ./install.sh --sync-only  # Only copy newer system files into repo
#   ./install.sh --link-only  # Only create symlinks (skip sync)
#   ./install.sh --dry-run    # Show what would happen, change nothing
#   ./install.sh --verify     # Run Docker-based verification after install

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────────────────────────────────────

DOTDIR="$(cd "$(dirname "$0")" && pwd)"
BACKUP_DIR="$HOME/.dotfiles_backup_$(date +%Y%m%d_%H%M%S)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# Flags
DO_SYNC=true
DO_LINK=true
DO_VERIFY=false
DRY_RUN=false
PREFER="local"  # "local" or "repo"

# ─────────────────────────────────────────────────────────────────────────────
# Manifest: all managed dotfile paths (relative to $HOME and $DOTDIR)
# ─────────────────────────────────────────────────────────────────────────────

# Home-directory dotfiles
HOME_DOTS=(
    .gtkrc-2.0
    .bashrc
    .bash_profile
    .bash_aliases
    .bash_logout
    .inputrc
    .vimrc
    .gitconfig
    .tmux.conf
    .xinitrc
    .Xresources
    .Xdefaults
    .i3status.conf
    .zshrc
)

# .config directories to manage (entire directory trees)
CONFIG_DIRS=(
    Thunar
    gtk-3.0
    xfce4
    alacritty
    btop
    cmus
    compton
    dunst
    i3
    kitty
    mpv
    neofetch
    nvim
    parcellite
    picom
    rofi
    sunshine
)

# .claude files to manage
CLAUDE_FILES=(
    settings.json
    settings.local.json
    CLAUDE.md
    statusline.sh
    claude-mirror.sh
)

# System config files (/etc/) that should ideally be managed,
# but are currently commented out because system files MUST be copied, not symlinked.
# We moved these to ETC_COPY_FILES below to prevent privilege escalation vulnerabilities.
ETC_FILES=(
)

# System config files that must be COPIED (not symlinked)
# Format: "repo_path:system_path"
ETC_COPY_FILES=(
    "etc/clamav/clamd.conf:/etc/clamav/clamd.conf"
    "etc/pacman.conf:/etc/pacman.conf"
    "etc/systemd/system/clamav-clamonacc.service.d/override.conf:/etc/systemd/system/clamav-clamonacc.service.d/override.conf"
    "bin/send_virus_alert.sh:/opt/send_virus_alert_sms.sh"
    "etc/pam.d/login:/etc/pam.d/login"
    "etc/modprobe.d/nvidia.conf:/etc/modprobe.d/nvidia.conf"
    "etc/modprobe.d/blacklist-nouveau.conf:/etc/modprobe.d/blacklist-nouveau.conf"
    "etc/mkinitcpio.conf:/etc/mkinitcpio.conf"
    "etc/default/grub:/etc/default/grub"
    "etc/environment:/etc/environment"
    "etc/udev/rules.d/80-nvidia-pm.rules:/etc/udev/rules.d/80-nvidia-pm.rules"
    "etc/hostname:/etc/hostname"
    "etc/fstab:/etc/fstab"
)

# ─────────────────────────────────────────────────────────────────────────────
# Parse arguments
# ─────────────────────────────────────────────────────────────────────────────

for arg in "$@"; do
    case "$arg" in
        --sync-only)    DO_SYNC=true; DO_LINK=false ;;
        --link-only)    DO_SYNC=false; DO_LINK=true ;;
        --verify)       DO_VERIFY=true ;;
        --dry-run)      DRY_RUN=true ;;
        --prefer-local) PREFER="local" ;;
        # Repo wins: skip the sync phase entirely so the system's current
        # files don't overwrite the fixed repo versions before linking.
        --prefer-repo)  PREFER="repo"; DO_SYNC=false ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --sync-only     Only sync system files → repo (no linking)"
            echo "  --link-only     Only create symlinks (skip sync)"
            echo "  --prefer-local  Keep local files when conflicts exist (default)"
            echo "  --prefer-repo   Force repo versions (skips sync), removing existing files"
            echo "  --verify        Run Docker archlinux verification after install"
            echo "  --dry-run       Show what would be done without changing anything"
            echo ""
            echo "Default: sync + link, prefer local"
            exit 0
            ;;
        *) echo "Unknown option: $arg"; exit 1 ;;
    esac
done

# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

log_info()    { echo -e "${BLUE}[INFO]${RESET} $*"; }
log_sync()    { echo -e "${CYAN}[SYNC]${RESET} $*"; }
log_link()    { echo -e "${GREEN}[LINK]${RESET} $*"; }
log_ok()      { echo -e "${GREEN}[OK]${RESET}   $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${RESET} $*"; }
log_skip()    { echo -e "${YELLOW}[SKIP]${RESET} $*"; }
log_new()     { echo -e "${GREEN}[NEW]${RESET}  $*"; }
log_diff()    { echo -e "${RED}[DIFF]${RESET} $*"; }
log_dry()     { echo -e "${YELLOW}[DRY-RUN]${RESET} $*"; }
log_header()  { echo -e "\n${BOLD}═══ $* ═══${RESET}\n"; }

# Sync a single file: system → repo (if system version is newer/different)
sync_file() {
    local rel="$1"  # relative path (e.g., .bashrc or .config/kitty/kitty.conf)
    local sys_file="$HOME/$rel"
    local repo_file="$DOTDIR/$rel"

    # Skip if system file doesn't exist
    if [[ ! -f "$sys_file" ]]; then
        return
    fi

    # Skip if it's already a symlink pointing to our repo
    if [[ -L "$sys_file" ]]; then
        local target
        target="$(readlink -f "$sys_file")"
        if [[ "$target" == "$DOTDIR/"* ]]; then
            return
        fi
    fi

    # If repo file doesn't exist → new file to add
    if [[ ! -f "$repo_file" ]]; then
        log_new "~/$rel (new file, not yet in repo)"
        if [[ "$DRY_RUN" == true ]]; then
            log_dry "Would copy: ~/$rel → repo"
        else
            mkdir -p "$(dirname "$repo_file")"
            cp "$sys_file" "$repo_file"
            log_sync "Copied ~/$rel → repo"
        fi
        return
    fi

    # Both exist — compare
    if ! diff -q "$sys_file" "$repo_file" &>/dev/null; then
        log_diff "~/$rel differs from repo version"
        # Show brief diff
        diff --color=always -u "$repo_file" "$sys_file" 2>/dev/null | head -30 || true
        echo ""
        if [[ "$DRY_RUN" == true ]]; then
            log_dry "Would copy: ~/$rel → repo (system version is newer)"
        else
            cp "$sys_file" "$repo_file"
            log_sync "Updated repo: $rel (copied system version)"
        fi
    fi
}

# Create a symlink: repo → system
link_file() {
    local rel="$1"  # relative path
    local src="$DOTDIR/$rel"
    local dest="$HOME/$rel"
    local dest_dir
    dest_dir="$(dirname "$dest")"

    # Source must exist in repo
    if [[ ! -e "$src" ]]; then
        return
    fi

    if [[ "$DRY_RUN" == true ]]; then
        if [[ -L "$dest" ]]; then
            local current_target
            current_target="$(readlink -f "$dest")"
            if [[ "$current_target" == "$src" || "$current_target" == "$(readlink -f "$src")" ]]; then
                return  # Already correctly linked
            fi
        fi
        log_dry "Would link: ~/$rel → $src"
        return
    fi

    if ! mkdir -p "$dest_dir" 2>/dev/null; then
        log_skip "~/$rel (cannot create parent dir: $dest_dir)"
        return
    fi

    # Already a symlink pointing to the right place
    if [[ -L "$dest" ]]; then
        local current_target
        current_target="$(readlink -f "$dest")"
        if [[ "$current_target" == "$src" || "$current_target" == "$(readlink -f "$src")" ]]; then
            return  # Already correct
        fi
        rm "$dest"
    elif [[ -e "$dest" ]]; then
        if [[ "$PREFER" == "repo" ]]; then
            # Force remove existing file/dir to replace with symlink
            rm -rf "$dest" 2>/dev/null || sudo rm -rf "$dest" 2>/dev/null || {
                log_skip "~/$rel (cannot remove even with sudo, skipping)"
                return
            }
            log_info "Removed (prefer-repo): ~/$rel"
        else
            # Backup existing regular file (handle immutable files)
            mkdir -p "$BACKUP_DIR/$(dirname "$rel")" 2>/dev/null || true
            if ! mv "$dest" "$BACKUP_DIR/$rel" 2>/dev/null; then
                # Try removing immutable attribute (needs sudo)
                if sudo chattr -i "$dest" 2>/dev/null; then
                    mv "$dest" "$BACKUP_DIR/$rel"
                    log_info "Backed up (removed immutable): ~/$rel → $BACKUP_DIR/$rel"
                else
                    log_skip "~/$rel (cannot move — immutable or permission denied, skipping)"
                    return
                fi
            else
                log_info "Backed up: ~/$rel → $BACKUP_DIR/$rel"
            fi
        fi
    fi

    if ! ln -sf "$src" "$dest" 2>/dev/null; then
        log_skip "~/$rel (cannot create symlink — permission denied)"
        return
    fi
    log_link "~/$rel → $src"
}

# ─────────────────────────────────────────────────────────────────────────────
# Phase 1: SYNC (system → repo)
# ─────────────────────────────────────────────────────────────────────────────

do_sync() {
    log_header "Phase 1: Syncing system dotfiles → repo"
    local synced=0

    # Home dotfiles
    log_info "Checking home dotfiles..."
    for f in "${HOME_DOTS[@]}"; do
        sync_file "$f"
    done

    # .vim directory
    if [[ -d "$HOME/.vim" ]]; then
        find "$HOME/.vim" -type f \
            ! -path "*/.git/*" ! -path "*/__pycache__/*" ! -name "*.pyc" \
            2>/dev/null | while read -r sys_file; do
            local rel="${sys_file#$HOME/}"
            sync_file "$rel"
        done
    fi

    # bin/ scripts
    log_info "Checking ~/bin scripts..."
    if [[ -d "$HOME/bin" ]]; then
        for f in "$HOME"/bin/*; do
            [[ -f "$f" ]] || continue
            local name
            name="$(basename "$f")"
            sync_file "bin/$name"
        done
    fi

    # .config/ directories
    log_info "Checking .config/ directories..."
    for dir in "${CONFIG_DIRS[@]}"; do
        if [[ -d "$HOME/.config/$dir" ]]; then
            find "$HOME/.config/$dir" -type f \
                ! -path "*/.git/*" ! -path "*/__pycache__/*" ! -name "*.pyc" \
                ! -path "*/node_modules/*" \
                2>/dev/null | while read -r sys_file; do
                local rel="${sys_file#$HOME/}"
                # Skip cache/log/credential files
                case "$rel" in
                    *.log|*credentials*|*cache*|*_state.json) continue ;;
                esac
                sync_file "$rel"
            done
        fi
    done

    # .claude files
    log_info "Checking .claude/ configs..."
    for f in "${CLAUDE_FILES[@]}"; do
        sync_file ".claude/$f"
    done

    # .claude/mcp-servers (sync individual files, skip node_modules)
    log_info "Checking .claude/mcp-servers/..."
    find "$HOME/.claude/mcp-servers" -type f \
        ! -path "*/node_modules/*" \
        2>/dev/null | while read -r f; do
        rel="${f#$HOME/}"
        sync_file "$rel"
    done

    # System /etc/ files
    log_info "Checking /etc/ configs..."
    for entry in "${ETC_FILES[@]}"; do
        local repo_path="${entry%%:*}"
        local sys_path="${entry##*:}"
        local repo_file="$DOTDIR/$repo_path"

        if [[ ! -f "$sys_path" ]]; then
            continue
        fi
        # Skip if already a symlink to our repo
        if [[ -L "$sys_path" ]]; then
            local target
            target="$(readlink -f "$sys_path")"
            if [[ "$target" == "$DOTDIR/"* ]]; then
                continue
            fi
        fi
        if [[ ! -f "$repo_file" ]]; then
            log_new "$sys_path (new file, not yet in repo)"
            if [[ "$DRY_RUN" == true ]]; then
                log_dry "Would copy: $sys_path → repo/$repo_path"
            else
                mkdir -p "$(dirname "$repo_file")"
                sudo cp "$sys_path" "$repo_file"
                sudo chown "$(id -u):$(id -g)" "$repo_file"
                log_sync "Copied $sys_path → repo/$repo_path"
            fi
        elif ! diff -q "$sys_path" "$repo_file" &>/dev/null; then
            log_diff "$sys_path differs from repo version"
            diff --color=always -u "$repo_file" "$sys_path" 2>/dev/null | head -30 || true
            if [[ "$DRY_RUN" == true ]]; then
                log_dry "Would copy: $sys_path → repo/$repo_path"
            else
                sudo cp "$sys_path" "$repo_file"
                sudo chown "$(id -u):$(id -g)" "$repo_file"
                log_sync "Updated repo: $repo_path"
            fi
        fi
    done

    # Boot-critical /etc/ files (sync system → repo)
    log_info "Checking boot-critical /etc/ configs..."
    for entry in "${ETC_COPY_FILES[@]}"; do
        local repo_path="${entry%%:*}"
        local sys_path="${entry##*:}"
        local repo_file="$DOTDIR/$repo_path"

        [[ -f "$sys_path" ]] || continue
        if [[ ! -f "$repo_file" ]]; then
            log_new "$sys_path (new file, not yet in repo)"
            if [[ "$DRY_RUN" != true ]]; then
                mkdir -p "$(dirname "$repo_file")"
                cp "$sys_path" "$repo_file"
                log_sync "Copied $sys_path → repo/$repo_path"
            fi
        elif ! diff -q "$sys_path" "$repo_file" &>/dev/null; then
            log_diff "$sys_path differs from repo version"
            diff --color=always -u "$repo_file" "$sys_path" 2>/dev/null | head -20 || true
            if [[ "$DRY_RUN" != true ]]; then
                cp "$sys_path" "$repo_file"
                log_sync "Updated repo: $repo_path"
            fi
        fi
    done

    echo ""
    if [[ "$DRY_RUN" == true ]]; then
        log_info "Dry run complete — no files were modified."
    else
        log_info "Sync complete. Review changes with: cd $DOTDIR && git diff"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Phase 2: SYMLINK (repo → system)
# ─────────────────────────────────────────────────────────────────────────────

do_link() {
    log_header "Phase 2: Creating symlinks (repo → home)"

    if [[ "$DRY_RUN" != true ]]; then
        mkdir -p "$BACKUP_DIR"
    fi

    # Home dotfiles
    log_info "Linking home dotfiles..."
    for f in "${HOME_DOTS[@]}"; do
        [[ -f "$DOTDIR/$f" ]] && link_file "$f"
    done

    # .vim directory
    if [[ -d "$DOTDIR/.vim" ]]; then
        find "$DOTDIR/.vim" -type f \
            ! -path "*/.git/*" ! -path "*/__pycache__/*" ! -name "*.pyc" \
            2>/dev/null | while read -r f; do
            local rel="${f#$DOTDIR/}"
            link_file "$rel"
        done
    fi

    # bin/ scripts
    log_info "Linking ~/bin scripts..."
    mkdir -p "$HOME/bin"
    for f in "$DOTDIR"/bin/*; do
        [[ -f "$f" ]] || continue
        local name
        name="$(basename "$f")"
        link_file "bin/$name"
    done
    if [[ "$DRY_RUN" != true ]]; then
        chmod +x "$HOME"/bin/* 2>/dev/null || true
    fi

    # .config/ directories
    log_info "Linking .config/ directories..."
    for dir in "${CONFIG_DIRS[@]}"; do
        if [[ -d "$DOTDIR/.config/$dir" ]]; then
            find "$DOTDIR/.config/$dir" -type f \
                ! -path "*/.git/*" ! -path "*/__pycache__/*" ! -name "*.pyc" \
                ! -path "*/node_modules/*" \
                2>/dev/null | while read -r f; do
                local rel="${f#$DOTDIR/}"
                link_file "$rel"
            done
        fi
    done

    # .claude files
    log_info "Linking .claude/ configs..."
    for f in "${CLAUDE_FILES[@]}"; do
        [[ -f "$DOTDIR/.claude/$f" ]] && link_file ".claude/$f"
    done
    if [[ "$DRY_RUN" != true ]]; then
        chmod +x "$HOME/.claude/statusline.sh" "$HOME/.claude/claude-mirror.sh" 2>/dev/null || true
    fi

    # .claude/mcp-servers (symlink each server dir, then npm install)
    log_info "Linking .claude/mcp-servers/..."
    if [[ -d "$DOTDIR/.claude/mcp-servers" ]]; then
        mkdir -p "$HOME/.claude/mcp-servers"
        for server_dir in "$DOTDIR/.claude/mcp-servers"/*/; do
            [[ -d "$server_dir" ]] || continue
            local server_name
            server_name="$(basename "$server_dir")"
            local target="$HOME/.claude/mcp-servers/$server_name"
            if [[ "$DRY_RUN" == true ]]; then
                log_info "[dry-run] Would link mcp-server: $server_name"
            else
                rm -rf "$target"
                ln -sfn "$server_dir" "$target"
                log_ok "Linked mcp-server: $server_name"
                # Install node dependencies if package.json exists
                if [[ -f "$target/package.json" && ! -d "$target/node_modules" ]]; then
                    log_info "Installing deps for mcp-server: $server_name"
                    (cd "$target" && npm install --silent 2>/dev/null) || log_warn "npm install failed for $server_name"
                fi
            fi
        done
    fi

    # System /etc/ files (require sudo)
    log_info "Linking /etc/ configs (requires sudo)..."
    for entry in "${ETC_FILES[@]}"; do
        local repo_path="${entry%%:*}"
        local sys_path="${entry##*:}"
        local repo_file="$DOTDIR/$repo_path"

        [[ -f "$repo_file" ]] || continue

        # Already correctly linked?
        if [[ -L "$sys_path" ]]; then
            local current_target
            current_target="$(readlink -f "$sys_path")"
            if [[ "$current_target" == "$(readlink -f "$repo_file")" ]]; then
                continue
            fi
        fi

        if [[ "$DRY_RUN" == true ]]; then
            log_dry "Would link (sudo): $sys_path → $repo_file"
        else
            # Backup existing file
            if [[ -f "$sys_path" && ! -L "$sys_path" ]]; then
                if ! sudo cp "$sys_path" "${sys_path}.bak.$(date +%Y%m%d)" 2>/dev/null; then
                    log_warn "Could not back up $sys_path (sudo failed)"
                else
                    log_info "Backed up: $sys_path → ${sys_path}.bak.$(date +%Y%m%d)"
                fi
            fi
            if ! sudo ln -sf "$repo_file" "$sys_path" 2>/dev/null; then
                log_skip "$sys_path (sudo failed — skipping)"
                continue
            fi
            log_link "$sys_path → $repo_file"
        fi
    done

    # Boot-critical /etc/ files (COPY, not symlink — needed before /home mounts)
    log_info "Copying boot-critical /etc/ configs (cannot symlink — needed before /home mounts)..."
    for entry in "${ETC_COPY_FILES[@]}"; do
        local repo_path="${entry%%:*}"
        local sys_path="${entry##*:}"
        local repo_file="$DOTDIR/$repo_path"

        [[ -f "$repo_file" ]] || continue

        if [[ -f "$sys_path" ]] && diff -q "$sys_path" "$repo_file" &>/dev/null; then
            continue  # Already matches
        fi

        if [[ "$DRY_RUN" == true ]]; then
            log_dry "Would copy (sudo): $repo_file → $sys_path"
        else
            if ! sudo mkdir -p "$(dirname "$sys_path")" 2>/dev/null \
               || ! sudo cp "$repo_file" "$sys_path" 2>/dev/null; then
                log_skip "$sys_path (sudo failed — skipping)"
                continue
            fi
            log_info "Copied (boot-critical): $repo_path → $sys_path"
        fi
    done

    # Cleanup empty backup dir
    if [[ "$DRY_RUN" != true ]]; then
        rmdir "$BACKUP_DIR" 2>/dev/null && true || log_info "Backups saved to: $BACKUP_DIR"
    fi

    echo ""
    log_info "Symlink phase complete."
}

# ─────────────────────────────────────────────────────────────────────────────
# Phase 3: DOCKER VERIFICATION
# ─────────────────────────────────────────────────────────────────────────────

do_verify() {
    log_header "Phase 3: Docker Verification (archlinux)"

    if ! command -v docker &>/dev/null; then
        echo -e "${RED}ERROR:${RESET} Docker not found. Install docker to use --verify."
        exit 1
    fi

    log_info "Ensuring archlinux:latest is available..."
    if ! docker image inspect archlinux:latest &>/dev/null; then
        docker pull archlinux:latest
    else
        log_info "archlinux:latest already available locally."
    fi

    log_info "Launching verification container..."

    # Create a verification script to run inside the container
    local verify_script
    verify_script=$(cat <<'INNEREOF'
#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RESET='\033[0m'

DOTDIR="/dotfiles"
export HOME="/home/testuser"
mkdir -p "$HOME"

echo "=== Running install.sh --link-only inside archlinux container ==="
echo ""

cd "$DOTDIR"
bash ./install.sh --link-only

echo ""
echo "=== Verifying all symlinks resolve correctly ==="
echo ""

ERRORS=0
TOTAL=0

check_link() {
    local path="$1"
    TOTAL=$((TOTAL + 1))
    if [[ -L "$path" ]]; then
        local target
        target="$(readlink "$path")"
        if [[ -e "$path" ]]; then
            echo -e "${GREEN}[OK]${RESET} $path → $target"
        else
            echo -e "${RED}[BROKEN]${RESET} $path → $target (target missing)"
            ERRORS=$((ERRORS + 1))
        fi
    elif [[ -e "$path" ]]; then
        echo -e "${YELLOW}[NOT LINKED]${RESET} $path (regular file, not a symlink)"
        ERRORS=$((ERRORS + 1))
    fi
}

# Check home dotfiles
for f in .gtkrc-2.0 .bashrc .bash_profile .bash_aliases .bash_logout .inputrc .vimrc \
         .gitconfig .tmux.conf .xinitrc .Xresources .Xdefaults .i3status.conf .zshrc; do
    [[ -f "$DOTDIR/$f" ]] && check_link "$HOME/$f"
done

# Check bin/
for f in "$DOTDIR"/bin/*; do
    [[ -f "$f" ]] || continue
    name="$(basename "$f")"
    check_link "$HOME/bin/$name"
done

# Check .config/
find "$DOTDIR/.config" -type f 2>/dev/null | while read -r f; do
    rel="${f#$DOTDIR/}"
    check_link "$HOME/$rel"
done

# Check .claude/
for f in settings.json settings.local.json CLAUDE.md statusline.sh claude-mirror.sh; do
    [[ -f "$DOTDIR/.claude/$f" ]] && check_link "$HOME/.claude/$f"
done
for server_dir in "$DOTDIR/.claude/mcp-servers"/*/; do
    [[ -d "$server_dir" ]] || continue
    check_link "$HOME/.claude/mcp-servers/$(basename "$server_dir")"
done

echo ""
echo "════════════════════════════════════════════"
echo -e " Total checked: ${TOTAL}"
echo -e " Errors: ${ERRORS}"
echo "════════════════════════════════════════════"

if [[ "$ERRORS" -eq 0 ]]; then
    echo -e "${GREEN}${RESET} All symlinks verified successfully!"
    exit 0
else
    echo -e "${RED}${RESET} $ERRORS symlink(s) failed verification."
    exit 1
fi
INNEREOF
)

    docker run --rm --network none \
        -v "$DOTDIR:/dotfiles:ro" \
        archlinux:latest \
        bash -c "$verify_script"

    local exit_code=$?
    echo ""
    if [[ $exit_code -eq 0 ]]; then
        log_info "Docker verification PASSED!"
    else
        echo -e "${RED}Docker verification FAILED!${RESET}"
        exit 1
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────

echo -e "${BOLD}╔══════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}║     Dotfiles Manager — Sync & Symlink        ║${RESET}"
echo -e "${BOLD}╚══════════════════════════════════════════════╝${RESET}"
echo ""
echo -e "  Repo:  ${CYAN}$DOTDIR${RESET}"
echo -e "  Home:  ${CYAN}$HOME${RESET}"
echo -e "  Flags: sync=${DO_SYNC} link=${DO_LINK} verify=${DO_VERIFY} dry-run=${DRY_RUN} prefer=${PREFER}"
echo ""

if [[ "$DO_SYNC" == true ]]; then
    do_sync
fi

if [[ "$DO_LINK" == true ]]; then
    do_link
fi

if [[ "$DO_VERIFY" == true ]]; then
    do_verify
fi

echo ""
echo -e "${GREEN}${BOLD}Done!${RESET} Open a new terminal or run: ${CYAN}source ~/.bashrc${RESET}"
