# ~/.bashrc — interactive shell config

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

# --- TMUX ---
export TMUX_TMPDIR=/var/tmp/tmux

# --- PATH ---
export PATH="${HOME}/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:${HOME}/Android/Sdk/platform-tools/:/usr/lib/jvm/default/bin/:/var/lib/snapd/snap/bin/:/opt/cuda/bin/:/usr/lib/emscripten/"
export PATH="${PATH}:/usr/local/sbin:/opt/bin:/usr/bin/core_perl:/usr/games/bin:${HOME}/.local/bin/:${HOME}/go/bin/:~/.pyenv/versions/2.7.18/bin/"
export PATH="$HOME/.npm-global/bin:$PATH"
export PATH="$PATH:${HOME}/.local/share/JetBrains/Toolbox/scripts"

# --- Git branch for PS1 ---
parse_git_branch() {
  git branch 2>/dev/null | sed -n 's/^\* \(.*\)/ (\1)/p'
}

# --- PS1 / Prompt ---
RESET="\[\033[0m\]"
BOLD="\[\033[1m\]"
COLOR_YELLOW="\[\033[38;5;214m\]"
COLOR_WHITE="\[\033[38;5;15m\]"
COLOR_LIGHT_GREEN="\[\033[38;5;47m\]"
COLOR_ORANGE="\[\033[38;5;208m\]"
COLOR_GREEN="\[\033[38;5;118m\]"
COLOR_GRAY="\[\033[38;5;100m\]"
COLOR_LIME="\[\033[38;5;112m\]"
COLOR_RED="\[\033[38;5;166m\]"
COLOR_PATH="\[\033[38;5;214m\]"
COLOR_PATH_BRACKET="\[\033[38;5;202m\]"
COLOR_NONZERO="\[\033[38;5;238m\]"
COLOR_GIT="\[\033[38;5;141m\]"
COLOR_VERSIONS="\[\033[38;5;245m\]"
COLOR_EXTRAS="\[\033[38;5;203m\]"

# --- Command execution time tracking ---
__prompt_timer_start() {
  PROMPT_CMD_START="${PROMPT_CMD_START:-$SECONDS}"
}
__prompt_precmd() {
  PROMPT_EXIT_CODE=$?
  PROMPT_EXEC_TIME=$((SECONDS - ${PROMPT_CMD_START:-$SECONDS}))
  unset PROMPT_CMD_START
}
trap '__prompt_timer_start' DEBUG

PS1="${COLOR_YELLOW}{${RESET}${COLOR_WHITE} ${RESET}${COLOR_LIGHT_GREEN}\T${RESET}${COLOR_WHITE} ${RESET}${COLOR_ORANGE}}${RESET}${COLOR_WHITE} \
${BOLD}${RESET}${COLOR_GREEN}[${RESET}${COLOR_WHITE} ${BOLD}${RESET}${COLOR_GRAY}\u${RESET}${COLOR_WHITE} ${BOLD}${RESET}${COLOR_LIME}]${RESET}${COLOR_WHITE} - \
${BOLD}${RESET}${COLOR_RED}[${RESET}${COLOR_WHITE} ${BOLD}${RESET}${COLOR_PATH}\w${RESET}${COLOR_WHITE} ${BOLD}${RESET}${COLOR_PATH_BRACKET}]${RESET}${COLOR_GIT}\$(parse_git_branch)${RESET}${COLOR_VERSIONS}\$(prompt-versions)${RESET}${COLOR_EXTRAS}\$(prompt-extras \$PROMPT_EXIT_CODE \j \$PROMPT_EXEC_TIME)${RESET}${COLOR_WHITE} \n\
${RESET}${COLOR_NONZERO} \$${RESET}${COLOR_WHITE} ${RESET}"

reset-cursor() {
  printf '\033]50;CursorShape=1\x7'
}
PS1="$(reset-cursor)$PS1"

# Window title
updateWindowTitle() { printf '\033]0;%s@%s:%s\007' "${USER}" "${HOSTNAME%%.*}" "${PWD/#$HOME/\~}"; }

# --- History ---
export HISTCONTROL=ignoredups:erasedups
export HISTSIZE=-1
export HISTFILESIZE=-1
export HISTFILE="$HOME/.bash_history"
shopt -s histappend
# Store multi-line commands in one history entry
shopt -s cmdhist

# Daily bash_history backup (runs once per day on first shell open)
_bash_history_backup() {
    local bdir="$HOME/.bash_history_backups"
    local marker="$bdir/.last_backup"
    mkdir -p "$bdir"
    # Skip if already backed up today
    if [[ -f "$marker" ]] && [[ "$(date +%Y%m%d)" == "$(cat "$marker")" ]]; then
        return
    fi
    cp "$HOME/.bash_history" "$bdir/bash_history_$(date +%Y%m%d)"
    date +%Y%m%d > "$marker"
    # Clean backups older than 90 days
    find "$bdir" -name "bash_history_*" -mtime +90 -delete
}
_bash_history_backup
MY_BASH_BLUE="\033[0;34m"
MY_BASH_NOCOLOR="\033[0m"
HISTTIMEFORMAT=$(echo -e "${MY_BASH_BLUE}[%F %T] ${MY_BASH_NOCOLOR}")
PROMPT_COMMAND="__prompt_precmd; history -a; history -n; updateWindowTitle"

# Ensure IntelliJ terminals also use the main history file
if [ -n "$__INTELLIJ_COMMAND_HISTFILE__" ]; then
    unset __INTELLIJ_COMMAND_HISTFILE__
fi

# --- Exports ---
export LD_PRELOAD=""
export EDITOR="vim"
export QWEN_STREAM_IDLE_TIMEOUT_MS=0
export OLLAMA_NOPRUNE=true
export OLLAMA_MODELS=/home/awcator/workbench/llm
export OLLAMA_FLASH_ATTENTION=1
export OLLAMA_KEEP_ALIVE=-1
export QWEN_STREAM_IDLE_TIMEOUT=0
export BUILDKIT_PROGRESS=plain
export COLORTERM=truecolor

# --- Aliases ---
alias ollama-restart='pkill -9 ollama; pkill -9 llama-server; sleep 2; ollama serve &'
alias ls="ls --color"
alias shred="shred -zf"
alias curl="curl --user-agent 'noleak'"

# --- Completions & Sources ---
if [ -f ~/.bash_aliases ]; then
    . ~/.bash_aliases
fi
[ -r /usr/share/bash-completion/completions ] &&
  . /usr/share/bash-completion/completions/*

# --- Tool inits ---
source /usr/share/nvm/init-nvm.sh
eval "$(zoxide init bash --cmd cd)"

export PYENV_ROOT="$HOME/.pyenv"
[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init - bash)"

# --- OTP secrets (not in repo) ---
[[ -f "$HOME/.otp_secrets" ]] && source "$HOME/.otp_secrets"

# claudeload as a plain command — sources the script so its env vars persist here
claudeload() { source "$HOME/Documents/MyDots/bin/claudeload" "$@"; }

# HSTR configuration (history size managed above - keep unlimited)
alias hh=hstr
export HSTR_CONFIG=hicolor,raw-history-view,keywords-matching,no-confirm,blacklist,hide-basic-help
export HSTR_TIOCSTI=n
function hstrnotiocsti {
    { READLINE_LINE="$( { </dev/tty hstr -- ${READLINE_LINE}; } 2>&1 1>&3 3>&- )"; } 3>&1;
    READLINE_POINT=${#READLINE_LINE}
}
if [[ $- =~ .*i.* ]]; then bind -x '"\C-r": "hstrnotiocsti"'; fi

#sonarqube
export SONAR_SCANNER_HOME="/opt/sonar-scanner"
export PATH="${SONAR_SCANNER_HOME}/bin:${PATH}"


# Added by Antigravity CLI installer
export PATH="/home/awcator/.local/bin:$PATH"
export PATH="$HOME/flutter/bin:$PATH"

# >>> Claude Code Router CLI >>>
# Added by Claude Code Router. Enables the ccr-app command in new shells.
case ":$PATH:" in
  *":$HOME/.claude-code-router/bin:"*) ;;
  *) export PATH="$HOME/.claude-code-router/bin:$PATH" ;;
esac
