# colors
#python .fb.py &
darkgrey="$(tput bold ; tput setaf 0)"
white="$(tput bold ; tput setaf 3)"
red="$(tput bold; tput setaf 1)"
nc="$(tput sgr0)"
# exports
export PATH="${HOME}/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:${HOME}/Android/Sdk/platform-tools/:/usr/lib/jvm/default/bin/:/var/lib/snapd/snap/bin/"
export PATH="${PATH}:/usr/local/sbin:/opt/bin:/usr/bin/core_perl:/usr/games/bin:${HOME}/.gem/ruby/2.6.0/bin/:${HOME}/.local/bin/:/opt/cuda/bin/"
#export PS1="\[$red\][ \[$darkgrey\]\H \[$white\]\W\[$darkgrey\] \[$red\]]\\[$darkgrey\] $ \[$nc\]"
function nonzero_return() {
	RETVAL=$?
	[ $RETVAL -ne 0 ] && echo "[$RETVAL]"
}

#export PS1="\[\033[38;5;214m\]{\[$(tput sgr0)\]\[\033[38;5;15m\] \[$(tput sgr0)\]\[\033[38;5;47m\]\T\[$(tput sgr0)\]\[\033[38;5;15m\] \[$(tput sgr0)\]\[\033[38;5;208m\]}\[$(tput sgr0)\]\[\033[38;5;15m\] \[$(tput bold)\]\[$(tput sgr0)\]\[\033[38;5;118m\][\[$(tput sgr0)\]\[$(tput sgr0)\]\[\033[38;5;15m\] \[$(tput bold)\]\[$(tput sgr0)\]\[\033[38;5;100m\]Awcator\[$(tput sgr0)\]\[$(tput sgr0)\]\[\033[38;5;15m\] \[$(tput bold)\]\[$(tput sgr0)\]\[\033[38;5;112m\]]\[$(tput sgr0)\]\[$(tput sgr0)\]\[\033[38;5;15m\] - \[$(tput bold)\]\[$(tput sgr0)\]\[\033[38;5;166m\][\[$(tput sgr0)\]\[$(tput sgr0)\]\[\033[38;5;15m\] \[$(tput bold)\]\[$(tput sgr0)\]\[\033[38;5;214m\]\w\[$(tput sgr0)\]\[$(tput sgr0)\]\[\033[38;5;15m\] \[$(tput bold)\]\[$(tput sgr0)\]\[\033[38;5;202m\]]\[$(tput sgr0)\]\[$(tput sgr0)\]\[\033[38;5;15m\]\n\[$(tput sgr0)\]\[\033[38;5;238m\]\`nonzero_return\` $\[$(tput sgr0)\]\[\033[38;5;15m\] \[$(tput sgr0)\]"

# Define colors
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
COLOR_BLUE="\[\033[38;5;33m\]"
COLOR_ERROR="\[\033[38;5;196m\]"

# Function to get the current Git branch
get_git_branch() {
  branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
  [ -n "$branch" ] && echo " $branch"
}

# Function to display exit code and Git details
custom_prompt_details() {
  local exit_code=$?  # Capture the exit code of the last command
  local branchTempVar=""
  local exitTempVar=""
  # Add exit code if nonzero
  if [ $exit_code -ne 0 ]; then
    # if exit status not equal to 130 then
 #   if [ $exit_code -ne 130 ]; then
#	{
#	    tmux capture-pane -p > /tmp/last_command_output
#	    output=$(tgpt -q -w --provider duckduckgo "$(cat /tmp/last_command_output)")
#	    notify-send "AwcatorCommandHelper" "$output"
#	} &
	#echo -e "\e3[31mPhind AI-helper: \e[0m";
    	#tgpt --provider phind "$(cat /tmp/last_command_output)"
#    fi

    exitTempVar="[✖ Exit Code: $exit_code] "
  fi

  # Add Git branch details
  local branch
  branch=$(get_git_branch)
  if [ -n "$branch" ]; then
    branchTempVar="[${branch}]"
  fi

  echo -e "\033[31m$exitTempVar\033[0m \033[32m$branchTempVar\033[0m"
}

# Updated PS1
PS1="${COLOR_YELLOW}{${RESET}${COLOR_WHITE} ${RESET}${COLOR_LIGHT_GREEN}\T${RESET}${COLOR_WHITE} ${RESET}${COLOR_ORANGE}}${RESET}${COLOR_WHITE} \
${BOLD}${RESET}${COLOR_GREEN}[${RESET}${COLOR_WHITE} ${BOLD}${RESET}${COLOR_GRAY}Awcator${RESET}${COLOR_WHITE} ${BOLD}${RESET}${COLOR_LIME}]${RESET}${COLOR_WHITE} - \
${BOLD}${RESET}${COLOR_RED}[${RESET}${COLOR_WHITE} ${BOLD}${RESET}${COLOR_PATH}\w${RESET}${COLOR_WHITE} ${BOLD}${RESET}${COLOR_PATH_BRACKET}]${RESET}${COLOR_WHITE} \n\
${RESET}${COLOR_NONZERO} \$${RESET}${COLOR_WHITE} ${RESET}"



export LD_PRELOAD=""
export EDITOR="nvim"

# alias
alias ls="ls --color"
alias vi="vim"
alias shred="shred -zf"
#alias python="python2"
alias wget="wget -U 'noleak'"
alias curl="curl --user-agent 'noleak'"
#Expand hiddenfiles with *
shopt -s dotglob
# source files
if [ -f ~/.bash_aliases ]; then
. ~/.bash_aliases
fi
[ -r /usr/share/bash-completion/completions ] &&
  . /usr/share/bash-completion/completions/*
# Avoid duplicates
export HISTCONTROL=ignoredups:erasedups  
# When the shell exits, append to the history file instead of overwriting it
shopt -s histappend

# After each command, append to the history file and reread it
export PROMPT_COMMAND="${PROMPT_COMMAND:+$PROMPT_COMMAND$'\n'}history -a; history -c; history -r"

MY_BASH_BLUE="\033[0;34m" #Blue
MY_BASH_NOCOLOR="\033[0m"
HISTTIMEFORMAT=`echo -e ${MY_BASH_BLUE}[%F %T] $MY_BASH_NOCOLOR `

export DRI_PRIME=1
export __NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia __VK_LAYER_NV_optimus=NVIDIA_only
shopt -s histappend    
# Save multi-line commands as one command
shopt -s cmdhist
export PROMPT_COMMAND='history -a'    
export HISTCONTROL=ignoredups    
export HISTSIZE=9999
export HISTFILESIZE=999999
export HISTFILE="$HOME/.bash_history"    
export OLLAMA_NOPRUNE=true
