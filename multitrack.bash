#!/bin/bash

[[ -f "$1" ]] || exit 1
[[ -r "$1" ]] || exit 1

input="$1"
output="${input/%.mov/amix.mov}"


# the follow command is an example of how to extract audio streams (4 in this case)
# -----------------------------------
#ffmpeg -i "$input" \
#-map 0:a:0 -c:a pcm_s24be audio0.aiff \
#-map 0:a:1 -c:a pcm_s24be audio1.aiff \
#-map 0:a:2 -c:a pcm_s24be audio2.aiff \
#-map 0:a:3 -c:a pcm_s24be audio3.aiff
# -----------------------------------

# guess_layout_max 0: don't try to guess input channel layout
ffmpeg -guess_layout_max 0 \
	-i "$input" -filter_complex "[0:a:0][0:a:1][0:a:2] amix=inputs=3[low];[low]volume=3[norm]" -map "[norm]" -c:a pcm_s24be -ac 2 -b:a 2304k -map 0:v -c:v copy "$output"
