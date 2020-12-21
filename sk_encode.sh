#!/bin/bash

FFMPEG=/usr/bin/ffmpeg
HB=/usr/local/bin/HandBrakeCLI
WM_DIR=./watermarks

ffprobe=/usr/bin/ffprobe
frame_opts=( -v error -select_streams v -show_entries stream=r_frame_rate -of csv=p=0 )
codec_opts=( -v error -select_streams v -show_entries stream=codec_name \
	-of default=noprint_wrappers=1:nokey=1 )

if [ $# -ne 1 ] || ! [ -f "$1" ]; then
	echo "Usage: $0 file" >&2
	exit 1
fi

INPUT="$1"
 
# ${ffprobe_frame_rate} should be of the form num/num.
# Ex. 30000/1001 or 2997/100
ffprobe_frame_rate="$(${ffprobe} "${frame_opts[@]}" "${INPUT}")"

# Get the frame rate to 2 decimal places
real_frame_rate=$(echo "scale=2; ${ffprobe_frame_rate}" | bc)

# make sure the frame rate is 29.97
if [[ "${real_frame_rate}" != "29.97" ]]; then
	echo "ERROR!!!! Segment does not have a floor frame rate of 29 !!" >&2
	echo "Frame rate is ${real_frame_rate}" >&2
	exit 1
fi

# Check video codec of segment; should be Apple ProRes 422 ("prores")
video_codec="$(${ffprobe} "${codec_opts[@]}" "${INPUT}")"

if [[ "$video_codec" != "prores" ]]; then
	echo "ERROR!!!! Segment was not encoded with Apple ProRes 422 !!" >&2
	echo "Video codec is ${video_codec}" >&2
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
#scp  /home/encoder/w/done_archive/sk/${INPUT/.mov/}.mp4     USER@REMOTE_HOST:REMOTE_DIRECTORY
scp  /home/encoder/w/done_archive/sk/out/${INPUT/.mov/}.mp4     USER@REMOTE_HOST:REMOTE_DIRECTORY
#scp -P 2222 /home/encoder/w/done_archive/sk/out/${INPUT/.mov/}.mp4     nnencoder@192.168.7.106:/var/www/html/shows/
echo "---------------------------------------"

if [ "$?" -eq "0" ]; then
	echo "${INPUT/.mov/}.mp4 done 100%"
else
	echo "$0 ERROR: scp of ${INPUT/.mov/}.mp4 failed." >&2
	exit 1
fi
