# Lines configured by zsh-newuser-install
HISTFILE=~/.histfile
HISTSIZE=100000
SAVEHIST=10000000
setopt autocd beep extendedglob notify
bindkey -e
# End of lines configured by zsh-newuser-install
# The following lines were added by compinstall
zstyle :compinstall filename '/home/restricteduser/.zshrc'

autoload -Uz compinit
compinit
# End of lines added by compinstall
#awcator adds
bindkey "^[[1;5C" forward-word
bindkey "^[[1;5D" backward-word
export PS1="%m%# "
if [ -f ~/.bash_aliases ]; then
. ~/.bash_aliases
fi

alias ls="ls --color"
alias vi="vim"
alias shred="shred -zf"
alias curl="curl --user-agent 'noleak'"
export PATH="$HOME/.npm-global/bin:$PATH"
