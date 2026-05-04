# ~/.bashrc — interactive shell config

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

# --- PATH ---
export PATH="${HOME}/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:${HOME}/Android/Sdk/platform-tools/:/usr/lib/jvm/default/bin/:/var/lib/snapd/snap/bin/:/opt/cuda/bin/:/usr/lib/emscripten/"
export PATH="${PATH}:/usr/local/sbin:/opt/bin:/usr/bin/core_perl:/usr/games/bin:${HOME}/.local/bin/:${HOME}/go/bin/:~/.pyenv/versions/2.7.18/bin/"
export PATH="$HOME/.npm-global/bin:$PATH"
export PATH="$PATH:/home/awcator/.local/share/JetBrains/Toolbox/scripts"

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

PS1="${COLOR_YELLOW}{${RESET}${COLOR_WHITE} ${RESET}${COLOR_LIGHT_GREEN}\T${RESET}${COLOR_WHITE} ${RESET}${COLOR_ORANGE}}${RESET}${COLOR_WHITE} \
${BOLD}${RESET}${COLOR_GREEN}[${RESET}${COLOR_WHITE} ${BOLD}${RESET}${COLOR_GRAY}\u${RESET}${COLOR_WHITE} ${BOLD}${RESET}${COLOR_LIME}]${RESET}${COLOR_WHITE} - \
${BOLD}${RESET}${COLOR_RED}[${RESET}${COLOR_WHITE} ${BOLD}${RESET}${COLOR_PATH}\w${RESET}${COLOR_WHITE} ${BOLD}${RESET}${COLOR_PATH_BRACKET}]${RESET}${COLOR_WHITE} \n\
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
shopt -s cmdhist
MY_BASH_BLUE="\033[0;34m"
MY_BASH_NOCOLOR="\033[0m"
HISTTIMEFORMAT=$(echo -e "${MY_BASH_BLUE}[%F %T] ${MY_BASH_NOCOLOR}")
PROMPT_COMMAND="history -a; history -n; updateWindowTitle"

# Ensure IntelliJ terminals also use the main history file
if [ -n "$__INTELLIJ_COMMAND_HISTFILE__" ]; then
    unset __INTELLIJ_COMMAND_HISTFILE__
fi

# --- Exports ---
export LD_PRELOAD=""
export EDITOR="vim"
export OLLAMA_NOPRUNE=true
export BUILDKIT_PROGRESS=plain
export COLORTERM=truecolor

# --- Aliases ---
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

# --- Claude Code ---
export ANTHROPIC_BASE_URL=http://localhost:4141
export ANTHROPIC_AUTH_TOKEN=dummy
export ANTHROPIC_MODEL=claude-opus-4.6
export ANTHROPIC_DEFAULT_SONNET_MODEL=claude-opus-4.6
export ANTHROPIC_SMALL_FAST_MODEL=claude-haiku-4.5
export ANTHROPIC_DEFAULT_HAIKU_MODEL=claude-haiku-4.5
export DISABLE_NON_ESSENTIAL_MODEL_CALLS=1
export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1

# --- Kitty word highlighting ---
if [[ "$TERM" == "xterm-kitty" ]]; then
    kitty @ create-marker --self iregex \
        1 '\b(FAIL|NXDOMAIN|loss|down|crash|tear|remove|unable|miss|not|end|quit|exit|negative|duplicate|delete|error|exception|warning|destroy|fatal|critical|failure|invalid|timeout|timedout|denied|caught|failed|refused|unavailable|unsuccessful|unresolved|unhealthy|unstable|broken|wrong|incorrect|bad|aborted|panic|oops|segfault|dump|killed|unhandled|dropped|forbidden|rejected|unauthorized|corrupt|malformed|dead|degraded|terminated|shutdown|inconsistent|rollback|conflict|overflow|underflow|severe|unexpected|unknown|unsupported|assertion|stacktrace|traceback|missing|truncated|stopped|halted|hung|frozen|unreachable|disconnected|lost|expired|banned|404|403|500|502|503|504|400|401|429|408|422|501)\b' \
        2 '\b(PASS|NOERROR|found|install|deploy|win|able|start|success|passed|complete|create|available|ready|connected|running|valid|approved|enabled|authorized|granted|active|resolved|healthy|stable|worked|succeeded|accepted|correct|good|fine|ok|okay|successful|done|finished|operational|restored|listening|validated|verified|consistent|synced|upgraded|initialized|registered|confirmed|acknowledged|delivered|recovered|fixed|patched|committed|alive|online|reachable|clean|safe|secure|trusted|cached|compiled|built|merged|deployed|saved|authenticated|200|201|202|203|204|206|301|302|304)\b' \
        3 '\b(load|status|find|work|update|draw|ignore|deprecate|waiting|loading|pending|processing|busy|working|progress|queued|initiated|executing|mandatory|required|needed|essential|imperative|vital|must|should|initializing|preparing|booting|scheduled|spawning|retrying|reconnecting|resuming|pausing|sleeping|idling|monitoring|tracing|logging|migrating|syncing|flushing|rotating|checkpoint|notifier|observer|listener|handler|dispatcher|thread|worker|heartbeat|keepalive|apply|transition|eval|unused|starting|stopping|restarting|reloading|connecting|downloading|uploading|sending|receiving|reading|writing|parsing|scanning|compiling|building|fetching|pulling|pushing|checking|calculating|rendering|info|notice|debug|verbose|trace|hint)\b' \
        2>/dev/null
fi
