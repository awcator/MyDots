#!/usr/bin/env bash
# install.sh — Sync & deploy dotfiles from this repo to $HOME
#
# Usage:
#   ./install.sh                 # Sync system→repo, then deploy repo→system
#   ./install.sh --prefer-repo   # Force repo versions (skip sync, remove existing)
#   ./install.sh --sync-only     # Only copy newer system files into repo
#   ./install.sh --link-only     # Only deploy repo files (symlink home, copy /etc)
#   ./install.sh --dry-run       # Show what would happen, change nothing
#   ./install.sh --verify        # Run Docker-based verification after install

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
            echo "  --sync-only     Only sync system files → repo (no deploy)"
            echo "  --link-only     Only deploy repo files (no sync)"
            echo "  --prefer-local  Keep local files when conflicts exist (default)"
            echo "  --prefer-repo   Force repo versions (skips sync), removing existing files"
            echo "  --verify        Run Docker archlinux verification after install"
            echo "  --dry-run       Show what would be done without changing anything"
            echo ""
            echo "Default: sync + deploy, prefer local"
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

top_level_component() {
    local rel="$1"
    printf '%s\n' "${rel%%/*}"
}

should_ignore_repo_path() {
    local rel="$1"

    case "$rel" in
        .git|.git/*|.githooks|.githooks/*|docs|docs/*|install.sh|README.md|nice.jpg)
            return 0
            ;;
        .gitignore|.gitmodules)
            return 0
            ;;
        .claude/mcp-servers/*/node_modules|.claude/mcp-servers/*/node_modules/*)
            return 0
            ;;
        .claude/mcp-servers/*/.git|.claude/mcp-servers/*/.git/*)
            return 0
            ;;
        .claude/mcp-servers/*/tts-venv|.claude/mcp-servers/*/tts-venv/*)
            return 0
            ;;
        */node_modules/*|*/__pycache__/*|*/.git/*)
            return 0
            ;;
        *.pyc|*.log|*.sqlite|*.sqlite-shm|*.sqlite-wal)
            return 0
            ;;
        *.pem|*.key|*.crt|*.p12|*.pfx)
            return 0
            ;;
        .env|.env.*|*/.env|*/.env.*)
            return 0
            ;;
        */id_rsa|*/id_ed25519|*/credentials.json|*/auth.json|*/history.jsonl|*/session_index.jsonl)
            return 0
            ;;
        .otp_secrets|*/.otp_secrets)
            return 0
            ;;
        *credentials*|*cache*|*_state.json|*.tmp|*.swp)
            return 0
            ;;
        .claude/mcp-servers)
            return 0
            ;;
    esac

    return 1
}

is_copy_managed_path() {
    local rel="$1"
    [[ "$rel" == etc/* ]]
}

is_mcp_server_path() {
    local rel="$1"
    [[ "$rel" == .claude/mcp-servers/* ]]
}

repo_path_to_home_dest() {
    local rel="$1"
    printf '%s\n' "$HOME/$rel"
}

repo_path_to_system_dest() {
    local rel="$1"
    printf '/%s\n' "$rel"
}

is_home_managed_path() {
    local rel="$1"
    local top

    [[ "$rel" == etc || "$rel" == etc/* ]] && return 1
    should_ignore_repo_path "$rel" && return 1
    is_mcp_server_path "$rel" && return 1

    top="$(top_level_component "$rel")"
    [[ -e "$DOTDIR/$top" ]]
}

is_repo_managed_file() {
    local rel="$1"
    local abs="$DOTDIR/$rel"

    [[ -f "$abs" ]] || return 1
    should_ignore_repo_path "$rel" && return 1
    is_mcp_server_path "$rel" && return 1
    return 0
}

list_repo_managed_files() {
    local rel abs
    while IFS= read -r -d '' abs; do
        rel="${abs#"$DOTDIR"/}"
        is_repo_managed_file "$rel" || continue
        printf '%s\0' "$rel"
    done < <(find -P "$DOTDIR" \
        \( -path "$DOTDIR/.git" -o -path "$DOTDIR/.git/*" \) -prune -o \
        -type f -print0)
    return 0
}

list_home_sync_roots() {
    local abs rel top seen="|"

    while IFS= read -r -d '' abs; do
        rel="${abs#"$DOTDIR"/}"
        should_ignore_repo_path "$rel" && continue
        top="$(top_level_component "$rel")"
        [[ "$top" == "etc" ]] && continue
        [[ "$seen" == *"|$top|"* ]] && continue
        seen+="$top|"
        printf '%s\0' "$HOME/$top"
    done < <(find -P "$DOTDIR" \
        \( -path "$DOTDIR/.git" -o -path "$DOTDIR/.git/*" \) -prune -o \
        -mindepth 1 -maxdepth 1 -print0)
    return 0
}

list_home_managed_files() {
    local root abs rel

    while IFS= read -r -d '' root; do
        [[ -e "$root" ]] || continue

        if [[ -f "$root" ]]; then
            rel="${root#"$HOME"/}"
            is_home_managed_path "$rel" || continue
            printf '%s\0' "$rel"
            continue
        fi

        while IFS= read -r -d '' abs; do
            rel="${abs#"$HOME"/}"
            is_home_managed_path "$rel" || continue
            printf '%s\0' "$rel"
        done < <(find -P "$root" -type f -print0 2>/dev/null)
    done < <(list_home_sync_roots)
    return 0
}

list_repo_mcp_server_dirs() {
    local server_dir server_name

    [[ -d "$DOTDIR/.claude/mcp-servers" ]] || return 0

    for server_dir in "$DOTDIR/.claude/mcp-servers"/*; do
        [[ -d "$server_dir" ]] || continue
        server_name="$(basename "$server_dir")"
        [[ "$server_name" == node_modules || "$server_name" == .git ]] && continue
        printf '%s\0' "$server_name"
    done
    return 0
}

show_diff() {
    local old_file="$1"
    local new_file="$2"
    diff --color=always -u "$old_file" "$new_file" 2>/dev/null | head -30 || true
}

# Sync a single home-managed file: system → repo (if system version is newer/different)
sync_file() {
    local rel="$1"
    local sys_file
    local repo_file

    sys_file="$(repo_path_to_home_dest "$rel")"
    repo_file="$DOTDIR/$rel"

    # Skip if system file doesn't exist
    if [[ ! -f "$sys_file" ]]; then
        return 0
    fi

    # Skip if it's already a symlink pointing to our repo
    if [[ -L "$sys_file" ]]; then
        local target
        target="$(readlink -f "$sys_file")"
        if [[ "$target" == "$DOTDIR/"* ]]; then
            return
        fi
        log_skip "$HOME/$rel (is a symlink outside repo, skipping sync)"
        return
    fi

    # If repo file doesn't exist → new file to add
    if [[ ! -f "$repo_file" ]]; then
        log_new "$HOME/$rel (new file, not yet in repo)"
        if [[ "$DRY_RUN" == true ]]; then
            log_dry "Would copy: ~/$rel → repo"
        else
            mkdir -p "$(dirname "$repo_file")"
            cp -p "$sys_file" "$repo_file"
            log_sync "Copied ~/$rel → repo"
        fi
        return
    fi

    # Both exist — compare
    if ! diff -q "$sys_file" "$repo_file" &>/dev/null; then
        log_diff "$HOME/$rel differs from repo version"
        show_diff "$repo_file" "$sys_file"
        echo ""
        if [[ "$DRY_RUN" == true ]]; then
            log_dry "Would copy: ~/$rel → repo (system version is newer)"
        else
            cp -p "$sys_file" "$repo_file"
            log_sync "Updated repo: $rel (copied system version)"
        fi
    fi
}

sync_system_file() {
    local rel="$1"
    local sys_file
    local repo_file

    sys_file="$(repo_path_to_system_dest "$rel")"
    repo_file="$DOTDIR/$rel"

    [[ -f "$sys_file" ]] || return 0

    if [[ -L "$sys_file" ]]; then
        log_skip "$sys_file (is a symlink, refusing to sync into repo)"
        return
    fi

    if [[ ! -f "$repo_file" ]]; then
        log_new "$sys_file (new file, not yet in repo)"
        if [[ "$DRY_RUN" == true ]]; then
            log_dry "Would copy: $sys_file → repo/$rel"
        else
            mkdir -p "$(dirname "$repo_file")"
            cp -p "$sys_file" "$repo_file"
            log_sync "Copied $sys_file → repo/$rel"
        fi
        return
    fi

    if ! diff -q "$sys_file" "$repo_file" &>/dev/null; then
        log_diff "$sys_file differs from repo version"
        show_diff "$repo_file" "$sys_file"
        echo ""
        if [[ "$DRY_RUN" == true ]]; then
            log_dry "Would copy: $sys_file → repo/$rel"
        else
            cp -p "$sys_file" "$repo_file"
            log_sync "Updated repo: $rel"
        fi
    fi
}

# Create a symlink: repo → home
link_file() {
    local rel="$1"
    local src="$DOTDIR/$rel"
    local dest
    local dest_dir

    dest="$(repo_path_to_home_dest "$rel")"
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
                return
            fi
        fi
        log_dry "Would link: ~/$rel → $src"
        return
    fi

    if ! mkdir -p "$dest_dir" 2>/dev/null; then
        log_skip "$HOME/$rel (cannot create parent dir: $dest_dir)"
        return
    fi

    # Already a symlink pointing to the right place
    if [[ -L "$dest" ]]; then
        local current_target
        current_target="$(readlink -f "$dest")"
        if [[ "$current_target" == "$src" || "$current_target" == "$(readlink -f "$src")" ]]; then
            return
        fi
        rm "$dest"
    elif [[ -e "$dest" ]]; then
        if [[ "$PREFER" == "repo" ]]; then
            rm -rf "$dest" 2>/dev/null || sudo rm -rf "$dest" 2>/dev/null || {
                log_skip "$HOME/$rel (cannot remove even with sudo, skipping)"
                return
            }
            log_info "Removed (prefer-repo): ~/$rel"
        else
            mkdir -p "$BACKUP_DIR/$(dirname "$rel")" 2>/dev/null || true
            if ! mv "$dest" "$BACKUP_DIR/$rel" 2>/dev/null; then
                if sudo chattr -i "$dest" 2>/dev/null; then
                    mv "$dest" "$BACKUP_DIR/$rel"
                    log_info "Backed up (removed immutable): ~/$rel → $BACKUP_DIR/$rel"
                else
                    log_skip "$HOME/$rel (cannot move — immutable or permission denied, skipping)"
                    return
                fi
            else
                log_info "Backed up: ~/$rel → $BACKUP_DIR/$rel"
            fi
        fi
    fi

    if ! ln -sf "$src" "$dest" 2>/dev/null; then
        log_skip "$HOME/$rel (cannot create symlink — permission denied)"
        return
    fi
    log_link "$HOME/$rel → $src"
}

copy_system_file() {
    local rel="$1"
    local src="$DOTDIR/$rel"
    local dest
    local dest_dir

    dest="$(repo_path_to_system_dest "$rel")"
    dest_dir="$(dirname "$dest")"

    [[ -f "$src" ]] || return

    if [[ "$DRY_RUN" == true ]]; then
        if [[ -f "$dest" && ! -L "$dest" ]] && diff -q "$dest" "$src" &>/dev/null; then
            return
        fi
        log_dry "Would copy (sudo): $src → $dest"
        return
    fi

    if [[ -L "$dest" ]]; then
        local backup
        backup="${dest}.bak.$(date +%Y%m%d_%H%M%S)"
        if ! sudo cp -a --no-dereference "$dest" "$backup" 2>/dev/null; then
            log_skip "$dest (cannot back up existing symlink, skipping)"
            return
        fi
        if ! sudo rm "$dest" 2>/dev/null; then
            log_skip "$dest (cannot remove existing symlink, skipping)"
            return
        fi
        log_info "Backed up symlink: $dest → $backup"
    elif [[ -f "$dest" ]]; then
        if diff -q "$dest" "$src" &>/dev/null; then
            return
        fi
        local backup
        backup="${dest}.bak.$(date +%Y%m%d_%H%M%S)"
        if ! sudo cp -p "$dest" "$backup" 2>/dev/null; then
            log_warn "Could not back up $dest (sudo failed)"
        else
            log_info "Backed up: $dest → $backup"
        fi
    elif [[ -e "$dest" ]]; then
        log_skip "$dest (exists and is not a regular file/symlink, skipping)"
        return
    fi

    if ! sudo mkdir -p "$dest_dir" 2>/dev/null; then
        log_skip "$dest (sudo failed creating parent dir)"
        return
    fi

    local tmp_dest="${dest}.tmp.$$"
    if ! sudo cp -p "$src" "$tmp_dest" 2>/dev/null || ! sudo mv -f "$tmp_dest" "$dest" 2>/dev/null; then
        sudo rm -f "$tmp_dest" 2>/dev/null || true
        log_skip "$dest (sudo failed — skipping)"
        return
    fi

    log_info "Copied (system): $rel → $dest"
}

sync_mcp_server_files() {
    local home_mcp="$HOME/.claude/mcp-servers"
    local abs rel

    [[ -d "$home_mcp" ]] || return 0

    log_info "Checking .claude/mcp-servers/..."
    while IFS= read -r -d '' abs; do
        rel="${abs#"$HOME"/}"
        should_ignore_repo_path "$rel" && continue
        sync_file "$rel"
    done < <(find -P "$home_mcp" \
        \( -path '*/node_modules' -o -path '*/node_modules/*' -o -path '*/.git' -o -path '*/.git/*' -o -path '*/tts-venv' -o -path '*/tts-venv/*' \) -prune -o \
        -type f -print0 2>/dev/null)
    return 0
}

link_mcp_server_dirs() {
    local server_name server_dir target

    [[ -d "$DOTDIR/.claude/mcp-servers" ]] || return

    log_info "Linking .claude/mcp-servers/..."
    mkdir -p "$HOME/.claude/mcp-servers"

    while IFS= read -r -d '' server_name; do
        server_dir="$DOTDIR/.claude/mcp-servers/$server_name"
        target="$HOME/.claude/mcp-servers/$server_name"

        if [[ "$DRY_RUN" == true ]]; then
            if [[ -L "$target" ]] && [[ "$(readlink -f "$target")" == "$(readlink -f "$server_dir")" ]]; then
                continue
            fi
            log_dry "Would link mcp-server: $target → $server_dir"
            continue
        fi

        if [[ -L "$target" ]]; then
            if [[ "$(readlink -f "$target")" == "$(readlink -f "$server_dir")" ]]; then
                :
            else
                rm "$target"
                ln -s "$server_dir" "$target"
                log_ok "Linked mcp-server: $server_name"
            fi
        elif [[ -e "$target" ]]; then
            if [[ "$PREFER" == "repo" ]]; then
                rm -rf "$target"
                ln -s "$server_dir" "$target"
                log_ok "Linked mcp-server: $server_name"
            else
                mkdir -p "$BACKUP_DIR/.claude/mcp-servers" 2>/dev/null || true
                mv "$target" "$BACKUP_DIR/.claude/mcp-servers/$server_name"
                ln -s "$server_dir" "$target"
                log_ok "Linked mcp-server: $server_name"
            fi
        else
            ln -s "$server_dir" "$target"
            log_ok "Linked mcp-server: $server_name"
        fi

        if [[ -f "$target/package-lock.json" ]]; then
            if [[ ! -d "$target/node_modules" ]]; then
                log_info "Installing deps for mcp-server: $server_name"
                (cd "$target" && npm ci --silent 2>/dev/null) || log_warn "npm ci failed for $server_name"
            fi
        elif [[ -f "$target/package.json" && ! -d "$target/node_modules" ]]; then
            log_info "Installing deps for mcp-server: $server_name"
            (cd "$target" && npm install --silent 2>/dev/null) || log_warn "npm install failed for $server_name"
        fi
    done < <(list_repo_mcp_server_dirs)
}

# ─────────────────────────────────────────────────────────────────────────────
# Phase 1: SYNC (system → repo)
# ─────────────────────────────────────────────────────────────────────────────

do_sync() {
    log_header "Phase 1: Syncing system dotfiles → repo"
    local rel

    log_info "Checking managed repo paths..."
    while IFS= read -r -d '' rel; do
        if is_copy_managed_path "$rel"; then
            sync_system_file "$rel"
        else
            sync_file "$rel"
        fi
    done < <(list_repo_managed_files)

    log_info "Discovering new local managed files..."
    while IFS= read -r -d '' rel; do
        is_repo_managed_file "$rel" && continue
        sync_file "$rel"
    done < <(list_home_managed_files)

    sync_mcp_server_files

    echo ""
    if [[ "$DRY_RUN" == true ]]; then
        log_info "Dry run complete — no files were modified."
    else
        log_info "Sync complete. Review changes with: cd $DOTDIR && git diff"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Phase 2: DEPLOY (repo → home/system)
# ─────────────────────────────────────────────────────────────────────────────

do_link() {
    log_header "Phase 2: Deploying repo files (symlink home, copy /etc)"
    local rel

    if [[ "$DRY_RUN" != true ]]; then
        mkdir -p "$BACKUP_DIR"
    fi

    while IFS= read -r -d '' rel; do
        if is_copy_managed_path "$rel"; then
            copy_system_file "$rel"
        else
            link_file "$rel"
        fi
    done < <(list_repo_managed_files)

    if [[ "$DRY_RUN" != true ]]; then
        chmod +x "$HOME"/bin/* 2>/dev/null || true
        chmod +x "$HOME/.claude/statusline.sh" "$HOME/.claude/claude-mirror.sh" 2>/dev/null || true
    fi

    link_mcp_server_dirs

    if [[ "$DRY_RUN" != true ]]; then
        if ! rmdir "$BACKUP_DIR" 2>/dev/null; then
            log_info "Backups saved to: $BACKUP_DIR"
        fi
    fi

    echo ""
    log_info "Deploy phase complete."
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

    local verify_script
    verify_script=$(cat <<'INNEREOF'
#!/usr/bin/env bash
set -euo pipefail

DOTDIR="/dotfiles"
export HOME="/home/testuser"
mkdir -p "$HOME"

top_level_component() {
    local rel="$1"
    printf '%s\n' "${rel%%/*}"
}

should_ignore_repo_path() {
    local rel="$1"

    case "$rel" in
        .git|.git/*|.githooks|.githooks/*|docs|docs/*|install.sh|README.md|nice.jpg)
            return 0
            ;;
        .gitignore|.gitmodules)
            return 0
            ;;
        .claude/mcp-servers/*/node_modules|.claude/mcp-servers/*/node_modules/*)
            return 0
            ;;
        .claude/mcp-servers/*/.git|.claude/mcp-servers/*/.git/*)
            return 0
            ;;
        .claude/mcp-servers/*/tts-venv|.claude/mcp-servers/*/tts-venv/*)
            return 0
            ;;
        */node_modules/*|*/__pycache__/*|*/.git/*)
            return 0
            ;;
        *.pyc|*.log|*.sqlite|*.sqlite-shm|*.sqlite-wal)
            return 0
            ;;
        *.pem|*.key|*.crt|*.p12|*.pfx)
            return 0
            ;;
        .env|.env.*|*/.env|*/.env.*)
            return 0
            ;;
        */id_rsa|*/id_ed25519|*/credentials.json|*/auth.json|*/history.jsonl|*/session_index.jsonl)
            return 0
            ;;
        .otp_secrets|*/.otp_secrets)
            return 0
            ;;
        *credentials*|*cache*|*_state.json|*.tmp|*.swp)
            return 0
            ;;
        .claude/mcp-servers)
            return 0
            ;;
    esac

    return 1
}

is_copy_managed_path() {
    local rel="$1"
    [[ "$rel" == etc/* ]]
}

is_mcp_server_path() {
    local rel="$1"
    [[ "$rel" == .claude/mcp-servers/* ]]
}

list_repo_managed_files() {
    local rel abs
    while IFS= read -r -d '' abs; do
        rel="${abs#"$DOTDIR"/}"
        [[ -f "$abs" ]] || continue
        should_ignore_repo_path "$rel" && continue
        is_mcp_server_path "$rel" && continue
        printf '%s\0' "$rel"
    done < <(find -P "$DOTDIR" \
        \( -path "$DOTDIR/.git" -o -path "$DOTDIR/.git/*" \) -prune -o \
        -type f -print0)
}

list_repo_mcp_server_dirs() {
    local server_dir server_name

    [[ -d "$DOTDIR/.claude/mcp-servers" ]] || return 0

    for server_dir in "$DOTDIR/.claude/mcp-servers"/*; do
        [[ -d "$server_dir" ]] || continue
        server_name="$(basename "$server_dir")"
        [[ "$server_name" == node_modules || "$server_name" == .git ]] && continue
        printf '%s\0' "$server_name"
    done
    return 0
}

ERRORS=0
TOTAL=0

check_link() {
    local rel="$1"
    local path="$HOME/$rel"
    TOTAL=$((TOTAL + 1))

    if [[ -L "$path" ]]; then
        local target expected
        target="$(readlink -f "$path")"
        expected="$(readlink -f "$DOTDIR/$rel")"
        if [[ "$target" == "$expected" ]]; then
            echo "[OK]   $path → $target"
        else
            echo "[BROKEN] $path → $target (expected $expected)"
            ERRORS=$((ERRORS + 1))
        fi
    elif [[ -e "$path" ]]; then
        echo "[NOT LINKED] $path (regular file, not a symlink)"
        ERRORS=$((ERRORS + 1))
    else
        echo "[MISSING] $path"
        ERRORS=$((ERRORS + 1))
    fi
}

check_copy() {
    local rel="$1"
    local path="/$rel"
    TOTAL=$((TOTAL + 1))

    if [[ -L "$path" ]]; then
        echo "[BAD SYMLINK] $path must be a copied regular file"
        ERRORS=$((ERRORS + 1))
    elif [[ ! -f "$path" ]]; then
        echo "[MISSING] $path"
        ERRORS=$((ERRORS + 1))
    elif cmp -s "$path" "$DOTDIR/$rel"; then
        echo "[OK]   $path matches repo"
    else
        echo "[DIFF] $path differs from repo"
        ERRORS=$((ERRORS + 1))
    fi
}

echo "=== Running install.sh --link-only inside archlinux container ==="
echo ""
cd "$DOTDIR"
bash ./install.sh --link-only
echo ""
echo "=== Verifying deployed paths ==="
echo ""

while IFS= read -r -d '' rel; do
    if is_copy_managed_path "$rel"; then
        check_copy "$rel"
    else
        check_link "$rel"
    fi
done < <(list_repo_managed_files)

while IFS= read -r -d '' server_name; do
    TOTAL=$((TOTAL + 1))
    path="$HOME/.claude/mcp-servers/$server_name"
    expected="$(readlink -f "$DOTDIR/.claude/mcp-servers/$server_name")"
    if [[ -L "$path" ]] && [[ "$(readlink -f "$path")" == "$expected" ]]; then
        echo "[OK]   $path → $expected"
    else
        echo "[BROKEN] $path mcp-server link missing or wrong"
        ERRORS=$((ERRORS + 1))
    fi
done < <(list_repo_mcp_server_dirs)

echo ""
echo "════════════════════════════════════════════"
echo " Total checked: ${TOTAL}"
echo " Errors: ${ERRORS}"
echo "════════════════════════════════════════════"

if [[ "$ERRORS" -eq 0 ]]; then
    echo "All managed paths verified successfully!"
    exit 0
else
    echo "$ERRORS managed path(s) failed verification."
    exit 1
fi
INNEREOF
)

    docker run --rm \
        --network none \
        --cap-add SYS_ADMIN \
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
