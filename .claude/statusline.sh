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
COST=$(echo "$INPUT"        | jq -r '.cost.total_cost_usd // 0')
DURATION=$(echo "$INPUT"    | jq -r '.cost.total_duration_ms // 0')
TURNS=$(echo "$INPUT"       | jq -r '.session.turns // 0')
ACTIVE=$(echo "$INPUT"      | jq -r '.session.is_active // false')
VIM_MODE=$(echo "$INPUT"    | jq -r '.vim_mode // ""')
WORKTREE=$(echo "$INPUT"    | jq -r '.worktree.is_active // false')
VERSION=$(echo "$INPUT"     | jq -r '.version // ""')
SESSION_ID=$(echo "$INPUT"  | jq -r '.session_id // ""')

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

# ── Nerd Font Icons ───────────────────────────────────────────────
ICON_MODEL="󰧑"        # brain / AI
ICON_FOLDER=""        # folder
ICON_GIT="󰘬"         # git branch
ICON_CLOCK=""        # clock
ICON_DOLLAR="󰄛"       # dollar
ICON_TURNS="󰑐"        # cycle/turns
ICON_CTX="󰍛"          # memory/context
ICON_VIM=""          # vim
ICON_TREE=""         # tree/worktree
ICON_ACTIVE="●"        # active indicator
ICON_SEP_THIN="|"    # thin separator
ICON_CRON="⏱"         # cron/timer
ICON_TASK="⚡"         # active tasks

# ── Cached Git Info (cache for 10 seconds) ────────────────────────
GIT_CACHE="/tmp/.claude-statusline-git-$$"
GIT_INFO=""
GIT_DIFF=""
if [ -n "$CWD" ] && [ -d "$CWD" ]; then
    if [ -f "$GIT_CACHE" ] && [ "$(( $(date +%s) - $(stat -c %Y "$GIT_CACHE" 2>/dev/null || echo 0) ))" -lt 10 ]; then
        read -r GIT_INFO < "$GIT_CACHE" || true
        GIT_DIFF=$(sed -n '2p' "$GIT_CACHE" 2>/dev/null || true)
    else
        GIT_BRANCH=$(git -C "$CWD" symbolic-ref --short HEAD 2>/dev/null || git -C "$CWD" rev-parse --short HEAD 2>/dev/null || echo "")
        if [ -n "$GIT_BRANCH" ]; then
            GIT_DIRTY=$(git -C "$CWD" status --porcelain 2>/dev/null | head -1)
            if [ -n "$GIT_DIRTY" ]; then
                GIT_INFO="${GIT_BRANCH} ✱"
            else
                GIT_INFO="${GIT_BRANCH}"
            fi

            # Diff stats (+X -Y)
            GIT_STATS=$(git -C "$CWD" diff --shortstat 2>/dev/null || echo "")
            if [ -n "$GIT_STATS" ]; then
                INS=$(echo "$GIT_STATS" | grep -oP '\d+(?=\s*insertion)' || echo 0)
                DEL=$(echo "$GIT_STATS" | grep -oP '\d+(?=\s*deletion)' || echo 0)
                if [ -z "$INS" ] || [ "$INS" = "0" ]; then INS=$(echo "$GIT_STATS" | awk '{for(i=1;i<=NF;i++) if($i~/insertion/) print $(i-1)}' || echo 0); fi
                if [ -z "$DEL" ] || [ "$DEL" = "0" ]; then DEL=$(echo "$GIT_STATS" | awk '{for(i=1;i<=NF;i++) if($i~/deletion/) print $(i-1)}' || echo 0); fi

                [ "${INS:-0}" -gt 0 ] && GIT_DIFF+="${C_GREEN}+${INS}${RST} "
                [ "${DEL:-0}" -gt 0 ] && GIT_DIFF+="${C_RED}-${DEL}${RST} "
                GIT_DIFF=$(echo -e "$GIT_DIFF" | sed 's/ $//')
            fi
        fi
        echo "$GIT_INFO" > "$GIT_CACHE" 2>/dev/null || true
        echo -E "$GIT_DIFF" >> "$GIT_CACHE" 2>/dev/null || true
    fi
fi

# ── Version Update Check (cache for 1 hour) ────────────────────────
VERSION_CACHE="/tmp/.claude-statusline-version-$$"
UPDATE_INFO=""
if [ -n "$VERSION" ]; then
    if [ -f "$VERSION_CACHE" ] && [ "$(( $(date +%s) - $(stat -c %Y "$VERSION_CACHE" 2>/dev/null || echo 0) ))" -lt 3600 ]; then
        LATEST_VERSION=$(cat "$VERSION_CACHE" 2>/dev/null || true)
    else
        # Run npm check in the background so it doesn't block the UI
        (npm view @anthropic-ai/claude-code version > "$VERSION_CACHE" 2>/dev/null) &
        LATEST_VERSION=$(cat "$VERSION_CACHE" 2>/dev/null || true)
    fi
    if [ -n "$LATEST_VERSION" ] && [ "$LATEST_VERSION" != "$VERSION" ]; then
        UPDATE_INFO=" 🔄 ${C_GREEN}v${LATEST_VERSION}${RST}"
    fi
fi

# ── Active Crons ─────────────────────────────────────────────────
CRONS_COUNT=0
if [ -n "$CWD" ] && [ -f "$CWD/.claude/scheduled_tasks.json" ]; then
    CRONS=$(cat "$CWD/.claude/scheduled_tasks.json" 2>/dev/null || echo "{}")
    if [ "$CRONS" != "{}" ] && [ "$CRONS" != "[]" ] && [ "$CRONS" != "" ]; then
        CRONS_COUNT=$(echo "$CRONS" | jq '.tasks | length' 2>/dev/null || echo 0)
    fi
fi

# ── Active Tasks (Subagents) ─────────────────────────────────────
TASKS_COUNT=0
if [ -n "$SESSION_ID" ]; then
    # Find the tasks directory for this session
    TASK_DIR=$(find /tmp/claude-$(id -u) -type d -name "$SESSION_ID" 2>/dev/null | head -n 1)
    if [ -n "$TASK_DIR" ] && [ -d "$TASK_DIR/tasks" ]; then
        TASKS_COUNT=$(ls -1 "$TASK_DIR/tasks"/*.output 2>/dev/null | wc -l || echo 0)
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

    if [ "$pct" -lt 50 ]; then color="$C_GREEN"
    elif [ "$pct" -lt 75 ]; then color="$C_YELLOW"
    elif [ "$pct" -lt 90 ]; then color="$C_ORANGE"
    else color="$C_RED"
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

# ── Build Line 1: Model + Version + Project + Git ────────────────
PROJECT_NAME=""
if [ -n "$CWD" ]; then
    PROJECT_NAME="$CWD"
fi

LINE1=""

# Status dot
LINE1+="${STATUS_DOT} "

# Model badge
LINE1+="${C_PURPLE}${BOLD}${ICON_MODEL} ${MODEL}${RST}"

# Version and Update Check
if [ -n "$VERSION" ]; then
    LINE1+=" ${C_GRAY}v${VERSION}${RST}${UPDATE_INFO}"
fi

# Separator
LINE1+=" ${C_GRAY}${ICON_SEP_THIN}${RST} "

# Project folder
if [ -n "$PROJECT_NAME" ]; then
    LINE1+="${C_BLUE}${ICON_FOLDER} ${PROJECT_NAME}${RST}"
fi

# Git branch & diff stats
if [ -n "$GIT_INFO" ]; then
    LINE1+=" ${C_GRAY}${ICON_SEP_THIN}${RST} "
    LINE1+="${C_ORANGE}${ICON_GIT} ${GIT_INFO}${RST}"
    if [ -n "$GIT_DIFF" ]; then
        LINE1+=" [${GIT_DIFF}]"
    fi
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

# ── Build Line 2: Context + Cost + Duration + Turns + Tasks ──────
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

# Turns (only if present)
if [ "$TURNS" != "0" ] && [ -n "$TURNS" ]; then
    LINE2+=" ${C_GRAY}${ICON_SEP_THIN}${RST} "
    LINE2+="${C_PINK}${ICON_TURNS} ${TURNS}${RST}"
fi

# Crons and Tasks
if [ "$CRONS_COUNT" -gt 0 ] || [ "$TASKS_COUNT" -gt 0 ]; then
    LINE2+=" ${C_GRAY}${ICON_SEP_THIN}${RST} "

    if [ "$CRONS_COUNT" -gt 0 ]; then
        LINE2+="${C_ORANGE}${ICON_CRON} ${CRONS_COUNT}${RST} "
    fi

    if [ "$TASKS_COUNT" -gt 0 ]; then
        LINE2+="${C_BLUE}${ICON_TASK} ${TASKS_COUNT}${RST}"
    fi
fi

# ── Output ────────────────────────────────────────────────────────
echo -e "$LINE1"
echo -e "$LINE2"