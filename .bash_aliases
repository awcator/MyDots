alias feh="feh --recursive --auto-zoom --scale-down"
alias sandbox="firejail --noprofile --whitelist=/home/awcator/Downloads --whitelist=/home/awcator/.renpy  --whitelist=~/.config/unity3d/ --seccomp --caps.drop=all --net=none"
alias htop="htop -s PERCENT_CPU -t"
alias la="ls -a"
alias diff="diff --color -u"
alias cluster_name="kubectl config view --minify -o jsonpath='{.clusters[].name}'"
alias k="kubectl"
alias gedit="gedit 2>/dev/null "
alias jshell='/usr/lib/jvm/java-12-openjdk/bin/jshell'
alias e="echo"
alias refresh=" sudo sh -c 'echo 3 >/proc/sys/vm/drop_caches'"
alias cd3="cd ../../../"
alias hex2asci="xxd -r -p"
alias httpserver="python -m http.server"
alias gdb="gdb -q"
alias range="seq"
alias time="date  +'%I:%M %p'"
alias c="clear && tmux clear-history"
alias bri2="sudo nvim /sys/devices/pci0000:00/0000:00:02.0/drm/card0/card0-eDP-1/intel_backlight/brightness"
alias lol="ls -loh"
alias bri="sudo nvim /sys/devices/pci0000:00/0000:00:02.0/drm/card1/card1-eDP-1/intel_backlight/brightness"
alias wifi="nmcli d wifi list --rescan yes"
alias dc="steghide extract -sf"
alias hakai="shred -n 5 -u -v -z -f "
alias clr=" clear && tmux clear-history"
alias cler="clear && tmux clear-history"
alias clear="clear && tmux clear-history"
alias xcp="xclip -selection c -o"
alias servers="systemctl status httpd mariadb;nmap -sT localhost"
alias s="sudo"
alias hiddenfiles="ls -d .!(|.)"
alias usbwrite="sudo dd bs=512M if=file.iso of=/dev/sdX"
alias o.="xdg-open . "
alias ungz="gunzip -k "
alias unbz="bzip2 -dk "
alias r="cd ~/.recycle"
alias ports='netstat -tulanp'
alias grep="grep -ian --color=auto"
alias maek='make'
alias du='du -ch'
alias df='df -h'
alias onn='sudo -su awcator reboot'
alias off="poweroff"
alias incognito='export HISTFILE=/dev/null'
alias ..="cd .."
alias h="history"
alias untar='tar -xvf'
alias o="xdg-open $1"
alias xc='xclip -selection clipboard -i ' 
alias ok="ping google.com"
alias cls="clear"
alias pacman="sudo pacman"
alias cd..="cd .."
alias l="ls"
alias ll="ls -lh"
alias lla="ls -lha"
alias rm="mv -t ~/.recycle -f "
alias vi="nvim -O"
alias cd2="cd ../../"
alias su="sudo su"
alias x="exit"
alias mysql='mycli -u root -p dev' 
alias sql='mycli -u root -p dev -D rhythm' 
alias sudo='sudo '
alias whomai='whoami'
#alias mybox='ssh -Y -i ~/.ssh/ams-hsop-keypair.pem -o ServerAliveInterval=60  ubuntu@3.68.159.129'
alias mybox='ssh -Y -o ServerAliveInterval=60 -i /home/awcator/.ssh/awcator_aws.keypair.pem ubuntu@35.173.231.110'
alias ???='gh copilot suggest'
alias ??='function _aianswer(){ echo -e "\e[31mduckduckgo: \e[0m"; tgpt --provider duckduckgo "$1"; echo -e "\e[31mphind: \e[0m"; tgpt --provider phind "$1"; }; _aianswer'
alias shitgitundoncommits="git reset --hard HEAD~2"
alias shitgitsqushcommits="git reset --soft HEAD~5"
alias shitgiterasefilehistory="git filter-branch --force --index-filter 'git rm --cached --ignore-unmatch my_sensitiveFile' --prune-empty --tag-name-filter cat 01c859dd7d34017efe4a722734b2eee80ed10c64..HEAD"
alias clamdscan="clamdscan -m -i --move=/home/awcator/Documents/infected "
alias quickreboot="sudo kexec -l /boot/vmlinuz-linux --initrd=/boot/initramfs-linux.img --reuse-cmdline && sudo kexec -e"
alias wtf='sudo !!'
