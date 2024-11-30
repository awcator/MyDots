#!/bin/bash
xhost +local:*
docker run --device /dev/dri/ -it   \
	-v /run/user/$(id -u)/pulse:/run/user/1000/pulse:ro \
	-e PULSE_SERVER=unix:/run/user/1000/pulse/native \
	--device /dev/snd \
	-v ~/.renpy:/home/renpy/.renpy:rw \
	-v ~/.config/unity3d:/home/renpy/.config/unity3d:rw \
	--net=none \
	--cap-drop=ALL \
	-e  DISPLAY=$DISPLAY  -v `pwd`:"/game/":rw -v /tmp/:/tmp/ -w /game awcator/renpygamelauncher bash -c "pulseaudio -D;$1"
	#SDL_AUDIODRIVER
	#PULSE_SERVER=unix:/run/user/0/pulse/native
