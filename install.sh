#!/usr/bin/env bash
# install.sh — Deploy dotfiles from this repo to $HOME
# Usage: git clone <repo> && cd MyDots && ./install.sh

set -e

DOTDIR="$(cd "$(dirname "$0")" && pwd)"
BACKUP="$HOME/.dotfiles_backup_$(date +%Y%m%d_%H%M%S)"

echo "==> Installing dotfiles from: $DOTDIR"
echo "==> Backup of existing files: $BACKUP"
mkdir -p "$BACKUP"

# --- Symlink helper ---
link_file() {
    local src="$1"  # relative to repo
    local dest="$HOME/$src"
    local dest_dir="$(dirname "$dest")"

    mkdir -p "$dest_dir"

    # Backup existing file/dir (not symlinks pointing to us)
    if [[ -e "$dest" && ! -L "$dest" ]]; then
        mkdir -p "$BACKUP/$(dirname "$src")"
        mv "$dest" "$BACKUP/$src"
        echo "  backed up: ~/$src"
    elif [[ -L "$dest" ]]; then
        rm "$dest"
    fi

    ln -sf "$DOTDIR/$src" "$dest"
    echo "  linked: ~/$src -> $DOTDIR/$src"
}

# --- Home dotfiles ---
echo ""
echo "==> Linking dotfiles..."
for f in .bashrc .bash_profile .bash_aliases .bash_logout .inputrc .vimrc \
         .gitconfig .tmux.conf .xinitrc .Xresources .Xdefaults .i3status.conf; do
    [[ -f "$DOTDIR/$f" ]] && link_file "$f"
done

# --- bin/ ---
echo ""
echo "==> Linking ~/bin scripts..."
mkdir -p "$HOME/bin"
for f in "$DOTDIR"/bin/*; do
    [[ -f "$f" ]] || continue
    name="$(basename "$f")"
    link_file "bin/$name"
done
chmod +x "$HOME"/bin/* 2>/dev/null

# --- .config/ ---
echo ""
echo "==> Linking .config/ dirs..."
find "$DOTDIR/.config" -type f 2>/dev/null | while read -r f; do
    rel="${f#$DOTDIR/}"
    link_file "$rel"
done

# --- .claude/ settings ---
echo ""
echo "==> Linking .claude/ configs..."
for f in settings.json settings.local.json CLAUDE.md statusline.sh claude-mirror.sh; do
    [[ -f "$DOTDIR/.claude/$f" ]] && link_file ".claude/$f"
done
chmod +x "$HOME/.claude/statusline.sh" "$HOME/.claude/claude-mirror.sh" 2>/dev/null

# --- etc/ (requires sudo) ---
if [[ -d "$DOTDIR/etc" ]]; then
    echo ""
    echo "==> System configs in etc/ (requires sudo)..."
    read -rp "   Install system configs to /etc? [y/N] " ans
    if [[ "$ans" =~ ^[Yy] ]]; then
        find "$DOTDIR/etc" -type f | while read -r f; do
            dest="/etc/${f#$DOTDIR/etc/}"
            sudo mkdir -p "$(dirname "$dest")"
            sudo cp "$f" "$dest"
            echo "  copied: $dest"
        done
    else
        echo "  skipped."
    fi
fi

echo ""
echo "==> Done! Open a new terminal or run: source ~/.bashrc"
