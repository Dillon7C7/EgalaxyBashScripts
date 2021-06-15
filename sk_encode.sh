#!/bin/bash

script="${0##*/}"
done_archive="${HOME}/w/done_archive/sk/out"

ffprobe_v_opts=( -v error -select_streams v -show_entries "stream=codec_name,width,height,r_frame_rate" -of "csv=p=0" )
ffprobe_a_opts=( -v error -select_streams a -show_entries "stream=index" -of "csv=p=0" )

hb_opts=( -e x264 -E faac --ab 320 --decomb -q 13 --x264-preset faster
	--x264-tune film --x264-profile high -x "level=4.1"
	--crop 0:0:0:0 --strict-anamorphic -o "$output")

print_e_and_exit()
{
	err_msg="$1"
	printf '%s\n' "${script}: ERROR: ${err_msg}"
	exit 1
} >&2

# check args given to this script
check_args()
{
	if [[ $# -ne 1 ]] || [[ ! -f "$1" ]]; then
		print_e_and_exit "requires one argument: a video file"
	else
		input="$1"
		output="${input/%mov/mp4}"
	fi

	return 0
}

# check video stream entries
check_v_stream()
{
	# we must get codec, resolution, frame rate
	IFS=, read -r codec width height r_frame_rate <<< "$(ffprobe -i "$input" "${ffprobe_v_opts[@]}")"

	#  if we need to divide in the future for other numer/denom pairs...
	#~ real_frame_rate=$(echo "scale=2; ${r_frame_rate}" | bc)

	if [[ "$codec" != "prores" ]]; then
		print_e_and_exit "$input: video stream must be Apple ProRes. Given: $codec"
	elif [[ $width -ne 1920 ]] || [[ $height -ne 1080 ]]; then
		print_e_and_exit "$input: video resolution must be 1920x1080. Given: ${width}x${height}"
	elif [[ "$r_frame_rate" != "30000/1001" ]]; then
		print_e_and_exit "$input: real frame rate must be 30000/1001. Given: $r_frame_rate"
	fi

	return 0
}

# check audio stream entries
check_a_stream()
{
	num_a_streams=$(ffprobe -i "$input" "${ffprobe_a_opts[@]}" | wc -w)

	# make sure we only have 1 audio stream. will allow for a variable number in the future
	if [[ $num_a_streams -ne 1 ]]; then
		print_e_and_exit "$input: must only have 1 audio stream. Given: $num_a_streams"
	fi

	return 0
}

encode_and_upload()
{
	# if there is an abnormal exit during encoding, remove output file
	trap 'rm -fv "$output"' HUP INT QUIT TERM

	if ! /usr/local/bin/HandBrakeCLI -i "$input" "${hb_opts[@]}" -o "$output"; then
		print_e_and_exit "$input: encoding failed"
	fi

	trap - HUP INT QUIT TERM

	chmod 777 "$output"
	printf '%s\n' "Pre-encoding complete !!!!!!"
	printf '%s\n' "---------------------------------------"
	printf '%s\n' "Moving to local archive..."

	# mv will remove the destination in case of error, no need for a trap
	if ! mv "$output" "${done_archive}/"; then
		print_e_and_exit "$output: mv to ${done_archive}/ failed"
	fi

	printf '%s\n' "---------------------------------------"
	printf '%s\n' "Uploading to beer.nakednews..."

	if ! scp "${done_archive}/${output}" REMOTE_USER@REMOTE_HOST:REMOTE_URI; then
		print_e_and_exit "$input: upload failed"
	fi

	printf '%s\n' "---------------------------------------"
	printf '%s\n' "${output} done 100%"

	return 0
}

check_args "$@" && \
check_v_stream  && \
check_a_stream  && \
encode_and_upload
