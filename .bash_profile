# colors
#python .fb.py &
darkgrey="$(tput bold ; tput setaf 0)"
white="$(tput bold ; tput setaf 3)"
red="$(tput bold; tput setaf 1)"
nc="$(tput sgr0)"
# exports
export PATH="${HOME}/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:"
export PATH="${PATH}/usr/local/sbin:/opt/bin:/usr/bin/core_perl:/usr/games/bin:${HOME}/.gem/ruby/2.6.0/bin/:${HOME}/.local/bin/"
#export PS1="\[$red\][ \[$darkgrey\]\H \[$white\]\W\[$darkgrey\] \[$red\]]\\[$darkgrey\] $ \[$nc\]"
export PS1="\[\033[38;5;214m\]{\[$(tput sgr0)\]\[\033[38;5;15m\] \[$(tput sgr0)\]\[\033[38;5;47m\]\T\[$(tput sgr0)\]\[\033[38;5;15m\] \[$(tput sgr0)\]\[\033[38;5;208m\]}\[$(tput sgr0)\]\[\033[38;5;15m\] \[$(tput bold)\]\[$(tput sgr0)\]\[\033[38;5;118m\][\[$(tput sgr0)\]\[$(tput sgr0)\]\[\033[38;5;15m\] \[$(tput bold)\]\[$(tput sgr0)\]\[\033[38;5;100m\]Awcator\[$(tput sgr0)\]\[$(tput sgr0)\]\[\033[38;5;15m\] \[$(tput bold)\]\[$(tput sgr0)\]\[\033[38;5;112m\]]\[$(tput sgr0)\]\[$(tput sgr0)\]\[\033[38;5;15m\] - \[$(tput bold)\]\[$(tput sgr0)\]\[\033[38;5;166m\][\[$(tput sgr0)\]\[$(tput sgr0)\]\[\033[38;5;15m\] \[$(tput bold)\]\[$(tput sgr0)\]\[\033[38;5;214m\]\w\[$(tput sgr0)\]\[$(tput sgr0)\]\[\033[38;5;15m\] \[$(tput bold)\]\[$(tput sgr0)\]\[\033[38;5;202m\]]\[$(tput sgr0)\]\[$(tput sgr0)\]\[\033[38;5;15m\]\n\[$(tput sgr0)\]\[\033[38;5;238m\]  $\[$(tput sgr0)\]\[\033[38;5;15m\] \[$(tput sgr0)\]"



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
export PROMPT_COMMAND='history -a'    
export HISTCONTROL=ignoredups    
export HISTSIZE=9999    
export HISTFILESIZE=999999    
export HISTFILE="$HOME/.bash_history"    

