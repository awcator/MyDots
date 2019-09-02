#!/bin/sh

/usr/bin/i3status -c $HOME/.i3status.conf | while :
do
    read line
   # RAM=`free -kh | grep Mem | awk '{print $3}'`
  #  TOTR=$(cat /proc/meminfo | grep MemT | sed 's/.*\://g' | sed 's/ *//g' | sed 's/kB//g')
 #   TOT=$(octave --eval "$TOTR/1024^2" | sed 's/ans = *//g' | sed 's/$/G/g' )

    # Put uptime
    uptime=`uptime | awk '{print $3 " " $4}' | sed 's/,.*//'`
    hour=$(echo $uptime | sed 's/\:.*//g')
    min=$(echo $uptime | sed 's/.*\://g')
    UP="$hour h $min m"

    # Compile C++ CPU prog and run it
    #g++ -o cpu.o $HOME/.i3/cpu.cpp
    #CPU=$(./cpu.o)
    KEYS=`xset q | grep Caps | tr -s ' ' | cut -d ' ' -f 5,9,13 | sed 's/on/▣/g' | sed 's/off/▢/g'`
    printf "%s\n" "Up: $UP | K: $KEYS% | RAM: $RAM/$TOT | $line"
done
