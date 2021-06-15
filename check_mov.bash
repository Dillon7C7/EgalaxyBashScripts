#!/bin/bash

script="${0##*/}"

ffprobe_v_opts=( -v error -select_streams v -show_entries "stream=codec_name,width,height,r_frame_rate" -of "csv=p=0" )
ffprobe_a_opts=( -v error -select_streams a -show_entries "stream=index" -of "csv=p=0" )


print_usage()
{
	printf '%s\n' "usage: ${script} [-h] FILE"
} >&2

print_help_and_exit()
{
	print_usage

	read -r -d '\0' help_msg <<- EOF_HELP
	Check a given video file for the following:

	  Video stream:
	    codec               (should be Apple ProRes)
	    resolution          (should be 1920x1080)
	    real frame rate     (should be 30000/1000)

	  Audio stream:
	    # of streams        (should be 1)

	positional arguments:
	  FILE                  the file to check

	optional arguments:
	  -h, --help            show this message and exit
	\0
	EOF_HELP

	printf '\n%s\n' "$help_msg"
	exit 1
} >&2

die()
{
	print_usage
	err_msg="$1"
	printf '%s\n' "${script}: ERROR: ${err_msg}"

	exit 1
} >&2

# pass in "$@"
parse_args()
{
	while [[ $# -gt 0 ]]; do
		[[ "$1" == --*=* ]] && set -- "${1%%=*}" "${1#*=}" "${@:2}"
		case "$1" in
			-h|--help) print_help_and_exit ;;
			-*) die "unrecognized argument: '$1'" ;;
			*) input="$1"
				break ;;
		esac
		shift
	done

	if [[ ! -f "$input" ]]; then
		die "'$input' does not exist on local system, and/or is not a file"
	fi

	return 0
}

# check video stream entries
check_v_stream()
{
	if ! vid_info="$(ffprobe -i "$input" "${ffprobe_v_opts[@]}" 2>/dev/null)"; then
		die "failed to probe '$input' for video info, make sure it is a video file"
	fi
	
	# we must get codec, resolution, frame rate
	IFS=, read -r codec width height r_frame_rate <<< "$vid_info"

	#  if we need to divide in the future for other numer/denom pairs...
	#~ real_frame_rate=$(echo "scale=2; ${r_frame_rate}" | bc)

	if [[ "$codec" != "prores" ]]; then
		die "$input: video stream codec must be Apple ProRes. Given: $codec"
	elif [[ $width -ne 1920 ]] && [[ $height -ne 1080 ]]; then
		die "$input: video resolution must be 1920x1080. Given: ${width}x${height}"
	elif [[ "$r_frame_rate" != "30000/1001" ]]; then
		die "$input: real frame rate must be 30000/1001. Given: $r_frame_rate"
	fi

	return 0
}

# check audio stream entries
check_a_stream()
{
	set -o pipefail

	if ! num_a_streams=$(ffprobe -i "$input" "${ffprobe_a_opts[@]}" 2>/dev/null | wc -w); then
		die "failed to probe '$input' for audio info"
	fi

	# make sure we only have 1 audio stream. will allow for a variable number in the future
	if [[ $num_a_streams -ne 1 ]]; then
		die "$input: must only have 1 audio stream. Given: $num_a_streams"
	fi

	return 0
}

parse_args "$@" && \
check_v_stream  && \
check_a_stream && \
exit 0
