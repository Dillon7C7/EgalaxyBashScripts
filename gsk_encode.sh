#!/bin/bash


FFMPEG=/usr/bin/ffmpeg
HB=/usr/local/bin/HandBrakeCLI
WM_DIR=./watermarks

 
 
#if [ "$1" -eq "" ]; then
#  echo "Usage: $0 [inputfile]"
#  exit 1
#fi

if [ "$#" -ne 1 ] || ! [ -f "$1" ]; then
  echo "Usage: $0 file" >&2
  exit 1
fi

INPUT="$1"
 
$HB 	-i   ${INPUT} -e x264 -q 13 -E faac --ab 320 --decomb  --x264-preset faster --x264-tune film  --x264-profile high -x level=4.1 --crop 0:0:0:0 -o ${INPUT/.mov/}.mp4  --strict-anamorphic
#scp  ${INPUT/.mov/}.mp4     USER@REMOTE_HOST:REMOTE_DIRECTORY
#mv ${INPUT/.mov/}.mp4 REMOTE_DIRECTORY
 
