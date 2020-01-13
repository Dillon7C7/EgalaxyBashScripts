#!/bin/bash

# printf "$1"
print_help_and_exit()
{
	msg="$1"
	printf "%s\\n\\n" "$msg" >&2
	printf "%s\\n" "Usage: ${0##*/} Weekly_Directory" >&2
	printf "%s\\n" "Example: "${0##*/}" January/WeekOfJan13" >&2
	exit 1
}

# get duration of video file $1
get_duration()
{
	local video="${1}"
	
	# get time of video in sexgesimal format
	local sexa_time="$(ffprobe -v error -show_entries format=duration \
	-of default=noprint_wrappers=1:nokey=1 -sexagesimal "${video}")"

	# trim the leading hour of sexagesimal time
	local time_trim_hour="${sexa_time#*:}"

	# trim leading 0 if duration < 10 minutes
	if [ "${time_trim_hour:0:1}" = "0" ]; then
		local time_trim_hour="${time_trim_hour:1}"
	fi
	
	# trim microseconds off of time
	local time_trim_ms="${time_trim_hour%.*}"

	printf "%s\\n" "$time_trim_ms"
}

# get segment id of video file $1
get_segment_id()
{
	local video="${1}"
	local seg_id="${video:4:3}"
	: "${SEGMENT_ID[${seg_id}]?"ERROR: SEGMENT ABBREV. NOT FOUND"}"
	printf "%s\\n" "${SEGMENT_ID[${seg_id}]}"
}

# print file names and durations
print_vid_info()
{
	echo ""

	local vid_total=0
	printf "%-3s%-23s%-9s%s\\n" "#" "SEGMENT FILE" "DURATION" "SEGMENT ID"

	while IFS= read -r -d '' vid_file; do
		vid_total=$((vid_total+1))
		vid_time="$(get_duration "${vid_file}")"
		vid_id="$(get_segment_id "${vid_file##*/}")"
			
		printf "%-3s%-23s%-9s%s\\n" "$vid_total" "${vid_file##*/}" "${vid_time}" "${vid_id}"
	
	done < <(find "${dir_segments}" -mindepth 1 -maxdepth 1 -type f -name "*mov" -print0 | sort -zrn -t_ -k3)
	echo ""

	local vid_total=0
	printf "%-3s%-23s%-9s\\n" "#" "TV SHOW FILE" "DURATION"

	while IFS= read -r -d '' vid_file; do
		vid_total=$((vid_total+1))
		vid_time="$(get_duration "${vid_file}")"
			
		printf "%-3s%-23s%-9s\\n" "$vid_total" "${vid_file##*/}" "${vid_time}"
	
	done < <(find "${dir_tvshows}" -mindepth 1 -maxdepth 1 -type f -name "*mpg" -print0 | sort -zrn -t_ -k3)
	echo ""
}

sa_dir="${1}"
dir_segments="${sa_dir}/SEGMENTS/VIDEOS/"
dir_tvshows="${sa_dir}/TV_SHOWS/VIDEOS/"

# mapping of segment abbreviations to segment IDs
declare -A SEGMENT_ID
SEGMENT_ID[AUD]="Auditions"
SEGMENT_ID[BTL]="Behind The Lens"
SEGMENT_ID[BTS]="Behind the Scenes"
SEGMENT_ID[BUT]="Busts For Laughs"
SEGMENT_ID[CLS]="Closing Remarks"
SEGMENT_ID[COO]="Cooking in the Raw"
SEGMENT_ID[DUN]="Dating Uncovered"
SEGMENT_ID[ENT]="Entertainment"
SEGMENT_ID[FLX]="Flex Appeal"
SEGMENT_ID[GAS]="Game Spot"
SEGMENT_ID[XPO]="HollywoodXposed"
SEGMENT_ID[BOX]="Inside The Box"
SEGMENT_ID[MOV]="Naked At The Movies"
SEGMENT_ID[FOO]="Naked Foodie"
SEGMENT_ID[NGP]="Naked Goes Pop"
SEGMENT_ID[POT]="Naked Goes Pot"
SEGMENT_ID[NIT]="Naked In The Streets"
SEGMENT_ID[NNM]="Naked News Moves"
SEGMENT_ID[YOG]="Naked Yogi"
SEGMENT_ID[BUA]="News off the Top"
SEGMENT_ID[BUB]="News off the Top Part 2"
SEGMENT_ID[NUI]="Nude and Improved"
SEGMENT_ID[ODD]="Odds N Ends"
SEGMENT_ID[NED]="Odds N Ends Part 2"
SEGMENT_ID[OOO]="One on One"
SEGMENT_ID[PTA]="Pillow Talk"
SEGMENT_ID[PMC]="Pop My Cherry"
SEGMENT_ID[DIC]="Riding In A Car Naked"
SEGMENT_ID[SPO]="Sports"
SEGMENT_ID[TIC]="Talk Is Cheap"
SEGMENT_ID[SCH]="The Schmooze"
SEGMENT_ID[TRA]="Travels"
SEGMENT_ID[TRN]="Trending Now"
SEGMENT_ID[TIU]="Turn it Up"
SEGMENT_ID[VRS]="Versus"
SEGMENT_ID[VBL]="Video Blog"
SEGMENT_ID[VMA]="Viewer's Mail"
SEGMENT_ID[WLS]="Wheels"

if ! command -v ffprobe 2>/dev/null; then
	printf "%s\\n" "Please install ffprobe and make sure it is in your \$PATH!"
	exit 1

elif [ $# -ne 1 ]; then
	print_help_and_exit "Too many arguments given!" 

elif [ ! -d "${dir_segments}" ]; then
	print_help_and_exit "${dir_segments} is not a valid directory!"

elif [ ! -d "${dir_tvshows}" ]; then
	print_help_and_exit "${dir_tvshows} is not a valid directory!"

fi

print_vid_info
