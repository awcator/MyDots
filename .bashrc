# colors
#PS1="\n\[\033[1;37m\]\342\224\214($(if [[ ${EUID} == 0 ]]; then echo '\[\033[01;31m\]\h'; else echo '\[\033[01;34m\]\u@\h'; fi)\[\033[1;37m\])\$([[ \$? != 0 ]] && echo \"\342\224\200(\[\033[0;31m\]\342\234\227\[\033[1;37m\])\")\342\224\200(\[\033[1;34m\]\@ \d\[\033[1;37m\])\[\033[1;37m\]\n\342\224\224\342\224\200(\[\033[1;32m\]\W\[\033[1;37m\])\342\224\200> \[\033[0m\]"

darkgrey="$(tput bold ; tput setaf 2)"
white="$(tput bold;tput setaf 0)"
red="$(tput bold; tput setaf 1)"
nc="$(tput sgr0)"
# exports
export PATH="${HOME}/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/home/xicor/Android/Sdk/platform-tools/:"
export PATH="${PATH}/usr/local/sbin:/opt/bin:/usr/bin/core_perl:/usr/games/bin:${HOME}/.local/bin/"
#export PS1="\[$red\][ \[$darkgrey\]\H \[$white\]\W\[$darkgrey\] \[$red\]]\\[$darkgrey\] $ \[$nc\]"
PS1="\[\033[0;31m\]\342\224\214\342\224\200\$([[ \$? != 0 ]] && echo \"[\[\033[0;31m\]\342\234\227\[\033[0;37m\]]\342\224\200\")[$(if [[ ${EUID} == 0 ]]; then echo '\[\033[01;31m\]root\[\033[01;33m\]@\[\033[01;96m\]\h'; else echo '\[\033[0;39m\]\u\[\033[01;33m\]@\[\033[01;96m\]\h'; fi)\[\033[0;31m\]]\342\224\200[\[\033[0;32m\]\w\[\033[0;31m\]]\n\[\033[0;31m\]\342\224\224\342\224\200\342\224\200\342\225\274 \[\033[0m\]\[\e[01;33m\]\\$\[\e[0m\]"
#export PS1="\[\033[38;5;214m\]{\[$(tput sgr0)\]\[\033[38;5;15m\] \[$(tput sgr0)\]\[\033[38;5;80m\]\T\[$(tput sgr0)\]\[\033[38;5;15m\] \[$(tput sgr0)\]\[\033[38;5;208m\]}\[$(tput sgr0)\]\[\033[38;5;15m\] \[$(tput sgr0)\]\[\033[38;5;1m\][\[$(tput sgr0)\]\[\033[38;5;15m\] \[$(tput bold)\]\[$(tput sgr0)\]\[\033[38;5;240m\]\u\[$(tput sgr0)\]\[$(tput sgr0)\]\[\033[38;5;15m\] \[$(tput sgr0)\]\[\033[38;5;1m\]]\[$(tput sgr0)\]\[\033[38;5;15m\] - \[$(tput sgr0)\]\[\033[38;5;160m\][\[$(tput sgr0)\]\[\033[38;5;15m\] \[$(tput sgr0)\]\[\033[38;5;214m\]\w\[$(tput sgr0)\]\[\033[38;5;15m\] \[$(tput sgr0)\]\[\033[38;5;160m\]]\[$(tput sgr0)\]\[\033[38;5;15m\]\n\[$(tput sgr0)\]\[\033[38;5;238m\]\\$\[$(tput sgr0)\]\[\033[38;5;15m\] \[$(tput sgr0)\]"
export LD_PRELOAD=""
export EDITOR="vim"
export HISTSIZE=10000
export HISTFILESIZE=900000
alias ls="ls --color"
alias vi="vim"
alias shred="shred -zf"
alias curl="curl --user-agent 'noleak'"
if [ -f ~/.bash_aliases ]; then
. ~/.bash_aliases
fi
[ -r /usr/share/bash-completion/completions ] &&
  . /usr/share/bash-completion/completions/*
tmux new -s awcator 2>/dev/null
if [ $?!=0 ]
then
	tmux new-window
	tmux a -t awcator
	echo "SAD"
fi
export HISTCONTROL=ignoredups:erasedups  
shopt -s histappend
#export PROMPT_COMMAND="${PROMPT_COMMAND:+$PROMPT_COMMAND$'\n'}history -a; history -c; history -r"
#powerline-daemon -q
#$POWERLINE_BASH_CONTINUATION=1
#POWERLINE_BASH_SELECT=1
#. /usr/share/powerline/bindings/bash/powerline.sh
reset-cursor() {
  printf '\033]50;CursorShape=1\x7'
}
export PS1="$(reset-cursor)$PS1"
export DRI_PRIME=1 # load up nvidia driver
export __NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia __VK_LAYER_NV_optimus=NVIDIA_only
