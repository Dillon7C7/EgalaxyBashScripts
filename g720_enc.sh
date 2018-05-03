#!/bin/bash
#
# Dependencies: ffmpeg, ffprobe, imagemagick (convert)
#
# Name the file the same as if you were uploading to lyrical, also add it to the admin as if you were uploading to lyrical
#
# Take all of the output files (after the script finishes) and upload them to the "lyrical-nakednews" S3 bucket.
# You can use something like http://www.3hubapp.com/ to upload with a drag and drop interface, or by going 
# to: https://console.aws.amazon.com/s3/home?region=us-east-1
 
# Change to match paths on your system, but these should be correct if you installed from packages
FFMPEG=/usr/bin/ffmpeg
FFPROBE=/usr/bin/ffprobe
CONVERT=/usr/bin/convert
 
# Destination dir
#OUTDIR=/home/gabriel/output
OUTDIR="."
 
 
#if [ "$1" -eq "" ]; then
#  echo "Usage: $0 [inputfile]"
#  exit 1
#fi

if [ "$#" -ne 1 ] || ! [ -f "$1" ]; then
  echo "Usage: $0 file" >&2
  exit 1
fi


#exit 2 
MOVINPUT="$1"
INPUT=${MOVINPUT/.mov/}.mp4

 
$FFMPEG -y -i "./$INPUT" -c:v libx264 -b:v 1200k -vf scale=1280:720 -pass 1 -x264opts "keyint=60:ref=5" -preset veryslow -profile:v main -level 3.1 -pix_fmt yuv420p -an -f mp4 /dev/null
$FFMPEG -y -i "./$INPUT" -c:v libx264 -b:v 1200k -vf scale=1280:720 -pass 2 -x264opts "keyint=60:ref=5" -preset veryslow -profile:v main -level 3.1 -pix_fmt yuv420p -c:a libfdk_aac -b:a 96k -movflags faststart "${OUTDIR}/${INPUT}_720.mp4"




