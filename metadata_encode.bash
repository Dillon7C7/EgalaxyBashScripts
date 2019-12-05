#!/usr/bin/env bash

# print the argument usage of this script
print_usage()
{
	echo "ERROR "$(basename "$0")": [-i,--input] FILE (ARTIST TITLE || [-g,--grab]) ALBUM [-h,--help]" >&2

	# if an additional message is given, print it and exit
	if [ -n "$1" ]; then
		echo -e "\n${1}\n" >&2
		exit 1
	fi
}

# print detailed information on the availabile options, and exit
print_help_and_exit()
{
	print_usage
	echo ""
	echo "-h|--help           Prints this message and exits." >&2
	echo "-g|--grab           Gets the ARTIST and TITLE from FILE. Last string provided is the ALBUM when this flag is set." >&2
	echo "-i|--input FILE     Explicitly specifies the FILE." >&2     
	exit 1
}

#  function to handle -i flag
#+ requires one argument (a file)
inputter()
{
	# make sure this function is only called once
	[[ -z "${i_given:+x}" ]] && i_given="y" || print_usage "[-i,--input] was provided more than once, and/or a file was already given."

	# if function argument is a file...
	if [[ -f "$1" ]]; then

		file="$1"

		# file name must end in .mp4
		if [[ "${file:(-4):4}" != "$file_suffix" ]]; then
			print_usage "${file} does not end in ${file_suffix}!"
		fi

		# else file is good
	
	# function argument is not a file
	else
		print_usage "${1:-FILE} does not exist!"
	fi

	return 0
}

#  function to check the first argument special case
#+ it can be a FILE, or -i|--input
check_first_arg()
{
	#  if $first_arg is not assigned here upon initial call, 
	#+ do so after parsing first argument
	[[ -z "${first_arg:+x}" ]] && first_arg="y"

	inputter "$1"
	return 0
}

# function to handle the -g flag
grabber()
{
	# make sure this function is only called once
	[[ -z "${g_given:+x}" ]] && g_given="y" || print_usage "[-g,--grab] was provided more than once."
}

# function to handle the string arguments
init_tags()
{
	if [ $string_count -ge $string_limit ]; then
		print_usage "Too many metadta tags provided. Maximum 3: ARTIST TITLE ALBUM"
	fi

	# increase the number of strings given
	string_count=$((string_count+1))

	case $string_count in
		1)
			artist="$1"
			;;
		2)
			title="$1"
			;;
		3)
			album="$1"
			;;
	esac
}

#  function to do post parameter checks
post_loop_check()
{
	# make sure that a file was provided
	[[ -z "${i_given:+x}" ]] && print_usage "No file was given!"

	# if the -g flag was given, 
	if [[ -n "$g_given" ]]; then

		# if we are grabbing the artist and title from the file, make sure it is named correctly
		if [[ "$file" =~ $file_regex ]]; then

			# make sure that at least 1 string was provided 
			[ $string_count -eq 0 ] && print_usage "No metadata was given!"

			# use the last string provided; loop in reverse
			for string in "$album" "$title" "$artist"; do
				if [[ -n "${string:+x}" ]]; then
					album="$string"
					break
				fi
			done

			artist="${BASH_REMATCH[1]}"
			title="${BASH_REMATCH[2]}"
		
		# file name does not match regex
		else
			print_usage "When using [-g,--grab], FILE must exist and be of the form 'ARTIST - TITLE.mp4'."
		fi

	# -g flag was not given
	else
		[ $string_count -ne 3 ] && print_usage "Not enough metadata tags were given!"
	fi
}

string_count=0                 # used to keep track of the number of strings provided
string_limit=3                 # maximum number of strings allowed
i_given=                       # assign this to something to cause a second -i to break the script
g_given=                       # assign this to something to cause a second -g to break the script
first_arg=                     # assign this to something to ignore special case first arg function

file_regex='^(.+) - (.+).mp4'  # E.g. 'BAND NAME - SONG NAME.mp4'
file_suffix='.mp4'             # suffix of permitted file name
file=                          # assign this to something to indicate that a file has been found
artist=                        # assign this to something to indicate that an artist has been found
title=                         # assign this to something to indicate that a title has been found
album=                         # assign this to something to indicate that an album has been found

while [ $# -gt 0 ]; do
	case "$1" in
		-h|--help)
			print_help_and_exit
			;;
		-g|--grab)
			grabber
			;;
		-i|--input)
			# shift, because inputter() will parse $2
			inputter "$2" && shift 1
			;;
		*)
			#  if the first arg is a string, it can be a file name
			#+ we do not to shift because that will occur at the end of the loop
			if [[ -z "${first_arg:+x}" ]]; then
				check_first_arg "$1"
			else
				init_tags "$1"
			fi
			;;
	esac
	shift 1

	# if the first arg was not a string, disable that check for following options
	first_arg="y"
done

# make sure we have all the data we need
post_loop_check

ffmpeg -i "$file" -metadata artist="${artist}" -metadata title="${title}" -metadata album="${album}" \
	-vn -acodec copy -f mp4 "${file/%mp4/m4a}"

IFS= read -r -d '' awkVariable << "AWK_EOF"
BEGIN { print ""; }
!found && /Metadata:/ {
	found = 1;
	num_lines_to_print=8+1;
}

# next line...
{
	if (num_lines_to_print) {
		print;
		num_lines_to_print--;
	}
}
END { print ""; }
AWK_EOF

/usr/bin/ffprobe "$file" 2> >(awk "$awkVariable")
