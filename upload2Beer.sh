#!/bin/bash

print_usage_and_quit() {
	echo "Usage: $0 [-h|--help]"
	echo "    or $0 FILE"
	echo "    or $0 [-d|--remote-dir] REMOTE_DIRECTORY FILE"
	exit 1
} >&2

print_help_and_quit() {
	echo "$0 [-h|--help] displays this help message and exits."
	echo "$0 FILE uploads a file to beer."
	echo "$0 [-d|--remote-dir] DIR FILE uploads a file to beer in remote directory DIR."
	exit 0
}

check_remote_dir() {

	# ** we have to store positional paramters in a variable in order for functions to use them
	# if there is a directoy, check to make sure it isn't the help flag, then initialize remote_dir
	if [[ -n "$remote_dir" ]]; then

		# we always want to print the help message when the help flag is given
		if [[ "$remote_dir" == "-h" ]] || [[ "$remote_dir" == "--help" ]]; then
			print_help_and_quit

		# make sure there are no forward slashes in our remote dir
		elif [[ ! "$remote_dir" =~ ^[^/]+$ ]]; then
			# we have slashes in our remote dir!
			remote_regex_fail=1
		fi

		# this function was called and we have a remote dir
		remote_dir_flag=1

	# no remote dir given, exit
	else # [[ -z "$remote_dir" ]]
		echo "ERROR. No REMOTE_DIR given." >&2
		print_usage_and_quit
	fi
}

file_arg=()
remote_dir_flag=0
remote_regex_fail=0

# parse arguments
while :; do

	# shift until we are out of arguments, then break
	[[ "$#" -eq 0 ]] && break

	case "$1" in
		-h|--help) print_help_and_quit ;;
		-d|--remote-dir) remote_dir="$2"; check_remote_dir; shift ;; # addl. shift for remote_dir positional param
		*) file_arg+=("$1") ;; # store file argment in an array
	esac
	shift
done

# reason for doing this after the while loop is to allow any usage of the help flag to trigger print_help_and_quit()
if [[ "$remote_regex_fail" -eq 1 ]]; then
	echo "ERROR. Do not include forward slashes / in REMOTE_DIR" >&2
	print_usage_and_quit
fi

# ${file_arg[]} should only contain 1 element, which is a regular file that exists
if [[ "${#file_arg[@]}" -ne 1 ]]; then 
	echo "ERROR. Provide one file only!" >&2
	print_usage_and_quit

elif [[ ! -f "${file_arg[0]}" ]]; then
	echo "ERROR. ${file_arg[0]} is not a file!" >&2
	print_usage_and_quit
fi

file="${file_arg[0]}"
remote_user="USER"

# didn't have -d flag
if [[ "$remote_dir_flag" -eq 0 ]]; then
	remote_url="REMOTE_HOST:REMOTE_DIRECTORY"
else # did have -d flag
	remote_url="REMOTE_HOST:REMOTE_DIRECTORY"/"${remote_dir}"
fi

# the actual uploading
scp "$file" "${remote_user}"@"${remote_url}"/"'${file}'"

if [[ "$?" -eq 0 ]]; then
	echo "File uploaded successfully."
	exit 0
else
	echo "File upload failed with scp exit code $?" >&2
	[[ "$remote_dir_flag" -eq 1 ]] && echo "Make sure destination dir exists" >&2
	exit 1
fi
