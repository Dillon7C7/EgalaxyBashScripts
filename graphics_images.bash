#!/bin/bash

# 1) Place screenshots in the 'Pictures/VLC Snapshots' folder
#    Name them N.png if Monday - Thursday, fN.png if Friday, sN.png if Sunday
#    N is the number of the segment

# 2) Fill in the Segment ID abbreviations in the Segment_IDs file
# The renaming will use the segment number instead if this is not done correctly

#  declare doesn't work as expect inside function
#+ this array will hold the segment IDs from the segment file
declare -a segment_ids

declare -A valid_segment_ids
valid_segment_ids[AUD]="REDACTED"
valid_segment_ids[BTL]="REDACTED"
valid_segment_ids[BTS]="REDACTED"
valid_segment_ids[BUT]="REDACTED"
valid_segment_ids[CLS]="REDACTED"
valid_segment_ids[COO]="REDACTED"
valid_segment_ids[DUN]="REDACTED"
valid_segment_ids[ENT]="REDACTED"
valid_segment_ids[FLX]="REDACTED"
valid_segment_ids[FOL]="REDACTED"
valid_segment_ids[GAS]="REDACTED"
valid_segment_ids[XPO]="REDACTED"
valid_segment_ids[BOX]="REDACTED"
valid_segment_ids[MOV]="REDACTED"
valid_segment_ids[FOO]="REDACTED"
valid_segment_ids[NGP]="REDACTED"
valid_segment_ids[POT]="REDACTED"
valid_segment_ids[NIT]="REDACTED"
valid_segment_ids[NNM]="REDACTED"
valid_segment_ids[YOG]="REDACTED"
valid_segment_ids[BUA]="REDACTED"
valid_segment_ids[BUB]="REDACTED"
valid_segment_ids[NUI]="REDACTED"
valid_segment_ids[ODD]="REDACTED"
valid_segment_ids[NED]="REDACTED"
valid_segment_ids[WEB]="REDACTED"
valid_segment_ids[OOO]="REDACTED"
valid_segment_ids[VAU]="REDACTED"
valid_segment_ids[PTA]="REDACTED"
valid_segment_ids[PMC]="REDACTED"
valid_segment_ids[POV]="REDACTED"
valid_segment_ids[DIC]="REDACTED"
valid_segment_ids[SPO]="REDACTED"
valid_segment_ids[TIC]="REDACTED"
valid_segment_ids[SCH]="REDACTED"
valid_segment_ids[TRA]="REDACTED"
valid_segment_ids[TRN]="REDACTED"
valid_segment_ids[TIU]="REDACTED"
valid_segment_ids[VRS]="REDACTED"
valid_segment_ids[VBL]="REDACTED"
valid_segment_ids[VMA]="REDACTED"
valid_segment_ids[WLS]="REDACTED"

# clear ssh ControlMaster, and clear segment_file
cleanup()
{
	ssh -q -S "$ssh_socket" -O 'exit' "$remote_host"
	rm -f "${ssh_socket}"
	clear_seg_file
}

# set up ssh control master
init_ssh_master()
{
	remote_host=NakedFiles
	ssh_socket="/tmp/"ssh_socket-$$-$(basename "$0")""

	# make sure ssh server is up on remote_host
	ssh -T -f -M -N -o ConnectTimeout=8 -o ControlMaster=yes -S "$ssh_socket" "$remote_host" /bin/true &>/dev/null
	[ $? -eq 0 ] && return 0 || { printf '%s\n' "ssh connection failed"; return 1; }
}

#  get segment IDs from file, and store it in an array
#+ will be used to rename screencaps
read_segment_file()
{
	segment_file="/home/REDACTED/scripts/mv_graphics/Segment_IDs"

	# if file is not readable, return from function
	[ -r "$segment_file" ] || { printf '%s\n' "${segment_file-Segment File} does not exist, or is not readable!"; exit 1; }

	# match records in segment file, ex: CLS, bUa
	local seg_regex='^[a-zA-Z]{3}$'

	# read through records in segment file
	while IFS=$'\n' read -r line; do

		#  make sure segment abbreviation is of length 3 and
		#+ and that it is actually valid (element is in array of all possible segment IDs)
		#+ skip otherwise
		if [[ "$line" =~ $seg_regex ]] && [ -n "${valid_segment_ids[${line^^}]+x}" ]; then
			segment_ids+=("${line^^}")

		# indicates that Friday segments end, and Sunday segments begin
		elif [[ "$line" == "-" ]]; then
			segment_ids+=("-")

		# invalid entry, insert a null string which indicates that an abbrev wasn't found
		else
			segment_ids+=("")
		fi

	done < "$segment_file"

	return 0
}

# rename images
rename()
{
	weekday=$(date +%A)
	pic_dir="/home/REDACTED/Pictures/VLC Snapshots"

	# exit if script is ran on the weekend
	if [[ "$weekday" == "Saturday" ]] || [[ "$weekday" == "Sunday" ]]; then
		printf '%s\n' "This script should not be run on a Saturday or Sunday!" >&2
		exit 1

	# account for Friday and Sunday show thumbnails on Friday
	elif [[ "$weekday" == "Friday" ]]; then
		find_args=("${pic_dir}" ! -path "${pic_dir}" -prune -type f \( -name "f[1-9].png" -o -name "s[1-9].png" \) -print0)

	# Monday - Thursday
	else
		find_args=("${pic_dir}" ! -path "${pic_dir}" -prune -type f -name "[1-9].png" -print0)
	fi

	if init_ssh_master; then
		ssh_flag=0
	else
		ssh_flag=1
	fi

	while IFS= read -r -d '' pic
	do
		pic_base="${pic##*/}"             # basename
		pic_dir="${pic%/*}"               # dirname
		pic_ext="${pic_base##*.}"         # file extension
		pic_num="${pic:(-5):1}"           # file number (name excluding file extension)
		pic_base_prefix="${pic_base:0:1}" # f or s, for Friday or Sunday
		array_num=$((pic_num-1))          # arrays start at 0
		sun_array_num=$((pic_num+6))      # number for Sunday

		#  Save basename without ext (ex. 2020-05-16_VMA), so the variable in question
		#+ can be used to easily append a number to when checking for duplicates.
		#+ Otherwise, we would have to run the following if statement once again to find
		#+ the basename, or use string manipulation once again.

		# Friday
		if [[ "${pic_base_prefix}" == "f" ]]; then
			# new file basename, provided segment ID is valid, no extension (.png)
			pic_name_ID_no_ext="$(date +%F)_${segment_ids[$array_num]}"
			
			# new filename, provided segment ID is not valid
			pic_name_NUM="$(date +%F)_${pic_base:1}"

			# for remote dir
			remote_date_dir="$(date +%Y/%B/%F)"

		# Sunday
		elif [[ "${pic_base_prefix}" == "s" ]]; then
			pic_name_ID_no_ext="$(date -d "2 day" +%F)_${segment_ids[$sun_array_num]}"
			pic_name_NUM="$(date -d "2 day" +%F)_${pic_base:1}"
			remote_date_dir="$(date -d "2 day" +%Y/%B/%F)"

			# 7 segments/lines in $segment_file for Friday, Sunday is a special case
			#???
			##array_num=$sun_array_num

		# Monday - Thursday
		else
			pic_name_ID_no_ext="$(date +%F)_${segment_ids[$array_num]}"
			pic_name_NUM="$(date +%F)_${pic_base}"
			remote_date_dir="$(date +%Y/%B/%F)"
		fi

		## **CHANGE cp TO mv LATER
			
		#  if a valid entry in the segment ID file was found for this image,
		#+ rename it as YYYY-MM-DD_SEG.png, otherwise
		#+ rename it as YYYY-MM-DD_N.png, where N is the number/name of the image
		if [[ -n "${segment_ids[$array_num]:+x}" ]]; then

			# used to rename files that would otherwise have been overwritten
			pic_ver_num=2

			# file basename with extension
			pic_name_ID_ext="${pic_name_ID_no_ext}.${pic_ext}"

			# file absolute path
			new_pic_name_final="${pic_dir}/${pic_name_ID_ext}"

			# make sure the file doesn't exist already (this will happen if the same segment appears twice in the show, for example)
			until [ ! -e "$new_pic_name_final" ]; do
				pic_name_ID_no_ext="${pic_name_ID_no_ext}${pic_ver_num}"
				pic_name_ID_ext="${pic_name_ID_no_ext}.${pic_ext}"
				new_pic_name_final="${pic_dir}/${pic_name_ID_ext}"
				pic_ver_num=$((pic_ver_num+1))
			done

		# if the segment ID read from input file is invalid, just prepend date to filename
		else
			new_pic_name_final="${pic_dir}/${pic_name_NUM}"
			pic_ver_num=-1
		fi

		cp -v "$pic" "$new_pic_name_final"

		#+ pass basename of file to be copied, if ssh server is up
		#  don't copy file if ID was invalid (check with $pic_ver_num as flag)
		if [ $ssh_flag -eq 0 ] && [ $pic_ver_num -ne -1 ]; then
			__cp_to_graphics "$new_pic_name_final" "$pic_name_ID_ext" "$remote_date_dir"
		fi

	done < <(find "${find_args[@]}" | sort -nz)
}

# $1 is the file to scp
# $2 is the basename
# $3 is the date_dir
__cp_to_graphics()
{
	local img="$1"
	local base_img="$2"
	local remote_date_dir="$3"
	remote_dir="/volume1/Graphics/  SOUTH AFRICA TEMPLATES/REDACTED_SCREENGRABS/${remote_date_dir}"

	ssh -T -o ControlPath="$ssh_socket" "$remote_host" mkdir -p "'${remote_dir}'"
	scp -o ControlPath="$ssh_socket" "$img" "${remote_host}:'${remote_dir}/${base_img}'"
} </dev/null

# move old $segment_file contents into a backup, if file is already empty
clear_seg_file()
{
	[ -s "${segment_file}.old" ] || cp "$segment_file" "${segment_file}.old"
	: > "$segment_file"
}

trap 'cleanup' EXIT

read_segment_file && \
rename
