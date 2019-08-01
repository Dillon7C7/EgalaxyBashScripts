#!/bin/bash


FFMPEG=/usr/bin/ffmpeg
HB=/usr/local/bin/HandBrakeCLI
WM_DIR=./watermarks

ffprobe=/usr/bin/ffprobe
opts=( -v error -select_streams v -show_entries stream=r_frame_rate -of csv=p=0 )
 

if [ "$#" -ne 1 ] || ! [ -f "$1" ]; then
  echo "Usage: $0 file" >&2
  exit 1
fi

INPUT="$1"
 
# ${ffprobe_frame_rate} should be of the form num/num.
# Ex. 30000/1001 or 2997/100
ffprobe_frame_rate="$(${ffprobe} "${opts[@]}" "${INPUT}")"

# Divide the numbers in ${ffprobe_frame_rate}
real_frame_rate=$((ffprobe_frame_rate))

# make sure the frame rate (rounded down) is 29
if [ "${real_frame_rate}" -ne 29 ]; then
	echo "ERROR!!!! Segment does not have a floor frame rate of 29 !!" >&2
	echo "Frame rate is ${real_frame_rate}" >&2
	exit 1
fi

$HB 	-i   ${INPUT} -e x264 -q 13 -E faac --ab 320 --decomb  --x264-preset faster --x264-tune film  --x264-profile high -x level=4.1 --crop 0:0:0:0 -o ${INPUT/.mov/}.mp4  --strict-anamorphic

chmod 777  ${INPUT/.mov/}.mp4
echo "PRE ENCODING DONE !!!!!!"
echo "---------------------------------------"
echo "Copying to local"

mv ${INPUT/.mov/}.mp4  /home/encoder/w/done_archive/sk/out/
echo "---------------------------------------"
echo "Copying to REMOTE_HOST!"

#scp  /home/encoder/w/done_archive/sk/${INPUT/.mov/}.mp4     USER@REMOTE_HOST:REMOTE_DIRECTORY
#scp  /home/encoder/w/done_archive/sk/${INPUT/.mov/}.mp4     USER@REMOTE_HOST:/REMOTE_DIRECTORY
scp  /home/encoder/w/done_archive/sk/out/${INPUT/.mov/}.mp4     USER@REMOTE_HOST.com:/REMOTE_DIRECTORY
#scp -P PORT /home/encoder/w/done_archive/sk/out/${INPUT/.mov/}.mp4     nnencoder@192.168.7.106:/var/www/html/shows/
echo "---------------------------------------"

if [ "$?" -eq "0" ]; then
	echo "${INPUT/.mov/}.mp4 done 100%"
else
	echo "$0 ERROR: scp of ${INPUT/.mov/}.mp4 failed." >&2
	exit 1
fi
