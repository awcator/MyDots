#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════════╗
# ║  Claude Code — Beautiful Status Line                            ║
# ║  Nerd Font icons • ANSI TrueColor • Git integration • Caching  ║
# ╚══════════════════════════════════════════════════════════════════╝
set -euo pipefail

# ── Read JSON from stdin ──────────────────────────────────────────
INPUT=$(cat)

# ── Parse fields via jq ──────────────────────────────────────────
MODEL=$(echo "$INPUT"       | jq -r '.model.display_name // "Unknown"')
CWD=$(echo "$INPUT"         | jq -r '.cwd // ""')
CTX_USED=$(echo "$INPUT"    | jq -r '.context_window.used_percentage // 0')
COST=$(echo "$INPUT"        | jq -r '.session.cost_usd // 0')
DURATION=$(echo "$INPUT"    | jq -r '.session.duration_ms // 0')
TURNS=$(echo "$INPUT"       | jq -r '.session.turns // 0')
ACTIVE=$(echo "$INPUT"      | jq -r '.session.is_active // false')
VIM_MODE=$(echo "$INPUT"    | jq -r '.vim_mode // ""')
WORKTREE=$(echo "$INPUT"    | jq -r '.worktree.is_active // false')

# ── Colors (TrueColor ANSI) ──────────────────────────────────────
RST='\033[0m'
BOLD='\033[1m'
DIM='\033[2m'
ITALIC='\033[3m'

# Palette — soft pastels that look great on dark terminals
C_PURPLE='\033[38;2;180;130;255m'      # lavender
C_BLUE='\033[38;2;110;180;255m'        # sky blue
C_CYAN='\033[38;2;100;220;220m'        # teal
C_GREEN='\033[38;2;130;220;130m'       # mint
C_YELLOW='\033[38;2;240;210;100m'      # warm gold
C_ORANGE='\033[38;2;255;170;80m'       # peach
C_RED='\033[38;2;255;110;110m'         # coral
C_PINK='\033[38;2;255;140;200m'        # pink
C_GRAY='\033[38;2;120;120;140m'        # muted gray
C_WHITE='\033[38;2;220;220;230m'       # soft white
C_BG_BAR='\033[48;2;40;40;55m'         # dark bar background

# ── Nerd Font Icons ───────────────────────────────────────────────
ICON_MODEL="󰧑"        # brain / AI
ICON_FOLDER=""        # folder
ICON_GIT=""          # git branch
ICON_CLOCK=""        # clock
ICON_DOLLAR="󰄛"       # dollar
ICON_TURNS="󰑐"        # cycle/turns
ICON_CTX="󰍛"          # memory/context
ICON_VIM=""          # vim
ICON_TREE=""         # tree/worktree
ICON_ACTIVE="●"        # active indicator
ICON_SEP=""          # powerline separator
ICON_SEP_THIN=""     # thin separator

# ── Cached Git Info (cache for 10 seconds) ────────────────────────
GIT_CACHE="/tmp/.claude-statusline-git-$$"
GIT_INFO=""
if [ -n "$CWD" ] && [ -d "$CWD" ]; then
    if [ -f "$GIT_CACHE" ] && [ "$(( $(date +%s) - $(stat -c %Y "$GIT_CACHE" 2>/dev/null || echo 0) ))" -lt 10 ]; then
        GIT_INFO=$(cat "$GIT_CACHE" 2>/dev/null || true)
    else
        GIT_BRANCH=$(git -C "$CWD" symbolic-ref --short HEAD 2>/dev/null || git -C "$CWD" rev-parse --short HEAD 2>/dev/null || echo "")
        if [ -n "$GIT_BRANCH" ]; then
            GIT_DIRTY=$(git -C "$CWD" status --porcelain 2>/dev/null | head -1)
            if [ -n "$GIT_DIRTY" ]; then
                GIT_INFO="${GIT_BRANCH} ✱"
            else
                GIT_INFO="${GIT_BRANCH}"
            fi
        fi
        echo "$GIT_INFO" > "$GIT_CACHE" 2>/dev/null || true
    fi
fi

# ── Format duration ──────────────────────────────────────────────
format_duration() {
    local ms=$1
    local secs=$(( ms / 1000 ))
    if [ "$secs" -lt 60 ]; then
        echo "${secs}s"
    elif [ "$secs" -lt 3600 ]; then
        echo "$(( secs / 60 ))m $(( secs % 60 ))s"
    else
        echo "$(( secs / 3600 ))h $(( secs % 3600 / 60 ))m"
    fi
}

# ── Format cost ──────────────────────────────────────────────────
format_cost() {
    local cost=$1
    # Use awk for float formatting
    echo "$cost" | awk '{
        if ($1 < 0.01) printf "%.4f", $1
        else if ($1 < 1) printf "%.3f", $1
        else printf "%.2f", $1
    }'
}

# ── Context Window Bar ────────────────────────────────────────────
make_ctx_bar() {
    local pct=$1
    local bar_width=12
    local filled=$(( pct * bar_width / 100 ))
    local empty=$(( bar_width - filled ))
    local bar=""
    local color

    if [ "$pct" -lt 50 ]; then
        color="$C_GREEN"
    elif [ "$pct" -lt 75 ]; then
        color="$C_YELLOW"
    elif [ "$pct" -lt 90 ]; then
        color="$C_ORANGE"
    else
        color="$C_RED"
    fi

    bar="${color}"
    for (( i=0; i<filled; i++ )); do bar+="█"; done
    bar+="${C_GRAY}"
    for (( i=0; i<empty; i++ )); do bar+="░"; done
    bar+="${RST}"

    echo -e "${bar} ${color}${pct}%${RST}"
}

# ── Activity indicator ────────────────────────────────────────────
if [ "$ACTIVE" = "true" ]; then
    STATUS_DOT="${C_GREEN}${BOLD}${ICON_ACTIVE}${RST}"
else
    STATUS_DOT="${C_GRAY}${DIM}${ICON_ACTIVE}${RST}"
fi

# ── Build Line 1: Model + Project + Git ──────────────────────────
PROJECT_NAME=""
if [ -n "$CWD" ]; then
    PROJECT_NAME=$(basename "$CWD")
fi

LINE1=""

# Status dot
LINE1+="${STATUS_DOT} "

# Model badge
LINE1+="${C_PURPLE}${BOLD}${ICON_MODEL} ${MODEL}${RST}"

# Separator
LINE1+=" ${C_GRAY}${ICON_SEP_THIN}${RST} "

# Project folder
if [ -n "$PROJECT_NAME" ]; then
    LINE1+="${C_BLUE}${ICON_FOLDER} ${PROJECT_NAME}${RST}"
fi

# Git branch
if [ -n "$GIT_INFO" ]; then
    LINE1+=" ${C_GRAY}${ICON_SEP_THIN}${RST} "
    LINE1+="${C_ORANGE}${ICON_GIT} ${GIT_INFO}${RST}"
fi

# Worktree indicator
if [ "$WORKTREE" = "true" ]; then
    LINE1+=" ${C_PINK}${ICON_TREE}${RST}"
fi

# Vim mode
if [ -n "$VIM_MODE" ] && [ "$VIM_MODE" != "null" ]; then
    LINE1+=" ${C_GRAY}${ICON_SEP_THIN}${RST} "
    case "$VIM_MODE" in
        NORMAL)  LINE1+="${C_BLUE}${BOLD}${ICON_VIM} NOR${RST}" ;;
        INSERT)  LINE1+="${C_GREEN}${BOLD}${ICON_VIM} INS${RST}" ;;
        VISUAL)  LINE1+="${C_PURPLE}${BOLD}${ICON_VIM} VIS${RST}" ;;
        *)       LINE1+="${C_GRAY}${ICON_VIM} ${VIM_MODE}${RST}" ;;
    esac
fi

# ── Build Line 2: Context + Cost + Duration + Turns ──────────────
LINE2=""

# Context bar
CTX_INT=${CTX_USED%.*}  # strip decimal
CTX_INT=${CTX_INT:-0}
LINE2+="${C_CYAN}${ICON_CTX}${RST} $(make_ctx_bar "$CTX_INT")"

# Separator
LINE2+="  ${C_GRAY}${ICON_SEP_THIN}${RST}  "

# Cost
COST_FMT=$(format_cost "$COST")
LINE2+="${C_GREEN}${ICON_DOLLAR} \$${COST_FMT}${RST}"

# Separator
LINE2+=" ${C_GRAY}${ICON_SEP_THIN}${RST} "

# Duration
DUR_FMT=$(format_duration "$DURATION")
LINE2+="${C_YELLOW}${ICON_CLOCK} ${DUR_FMT}${RST}"

# Separator
LINE2+=" ${C_GRAY}${ICON_SEP_THIN}${RST} "

# Turns
LINE2+="${C_PINK}${ICON_TURNS} ${TURNS}${RST}"

# ── Output ────────────────────────────────────────────────────────
echo -e "$LINE1"
echo -e "$LINE2"
