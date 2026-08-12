# ~/.bash_profile — login shell only (tmux, tty, SSH)
# Just source .bashrc for all interactive config
if [ -f ~/.bashrc ]; then
    . ~/.bashrc
fi


# Added by Antigravity CLI installer
export PATH="/home/awcator/.local/bin:$PATH"
