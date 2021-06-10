#!/bin/bash

red="$(tput setaf 1)"
green="$(tput setaf 2)"
yellow="$(tput setaf 3)"
res_term="$(tput sgr0)"


print_usage()
{
	printf '%s\n' "usage: ${script} [-h] [-d DIR] FILE [FILE ...]"
} >&2

print_help_and_exit()
{
	print_usage

	read -r -d '\0' help_msg <<- EOF_HELP
	Upload files to t.nakednews.com

	positional arguments:
	  FILE                        the file(s) to upload

	optional arguments:
	  -h, --help                  show this message and exit
	  -d DIR, --remote-dir DIR    append DIR to the base sk-encoder directory
	\0
	EOF_HELP

	printf '\n%s\n' "$help_msg"
	exit 1
} >&2

die()
{
	print_usage
	err_msg="$1"
	printf '%s\n' "${script}: error: ${err_msg}"
	exit 1
} >&2

warn()
{
	warn_msg="$1"
	printf '%b\n' "${script}: ${yellow}WARNING:${res_term} ${warn_msg}"
} >&2

# pass in "$@"
parse_args()
{
	while [[ $# -gt 0 ]]; do
		[[ "$1" == --*=* ]] && set -- "${1%%=*}" "${1#*=}" "${@:2}"
		case "$1" in
			-h|--help) print_help_and_quit ;;
			-d|--remote-dir)
				if [[ -z "$2" ]]; then
					die "'-d|--remote-dir' requires an argument"
				else
					remote_dir="$2"
					shift
				fi ;;
			-*) die "unrecognized argument: '$1'" ;;
			*)
				if [[ ! -f "$1" ]]; then
					die "'$1' does not exist on local system, and/or is not a file"
				else
					files+=("$1")
				fi ;;
		esac
		shift
	done

	((${#files[@]})) || die "at least one file is required"

	return 0
}

# set up ssh connection sharing
setup_ssh()
{
	remote="REMOTE_USER@REMOTE_HOST"
	remote_uri="REMOTE_URI"

	# socket for ControlMaster
	ssh_ctl="/tmp/${script}-$$-ssh.socket"

	# create initial TCP connection
	if ! ssh -fN -o 'ControlMaster=yes' -o 'ControlPersist=yes' -o 'ConnectTimeout=20' -S "$ssh_ctl" "$remote"; then
		die "initial ssh connection failed"
	else
		# close ssh connection on script exit
		trap 'ssh -O exit -S "$ssh_ctl" "$remote" &>/dev/null' EXIT
	fi

	return 0
}

# make sure remote_dir exists on the remote host
check_remote_dir()
{
	# if --remote-dir was given, create the dir on remote host if it doesn't already exist
	if [[ -n "${remote_dir:+x}" ]]; then
		if ! ssh -T -S "$ssh_ctl" "$remote" "cd -P "$remote_uri"; [ -d "$remote_dir" ] || mkdir -p "$remote_dir""; then
			die "ssh failed when trying to check remote dir $remote_dir"
		# ssh succeeded
		else
			# append remote dir to remote URI
			remote_uri="${remote_uri}/${remote_dir}"
		fi
	fi

	return 0
}

# pass in a file, should only be called from upload_files()
_upload_file()
{
	local file="$1"

	if ! scp -o ControlPath="$ssh_ctl" "$file" "${remote}:${remote_uri}/" 2>/dev/null; then
		warn "upload of '$file' failed"
		return 1
	else
		return 0
	fi
}

# batch upload
upload_files()
{

	for file in "${files[@]}"; do
		if _upload_file "$file"; then
			success+=("$file")
		else
			fail+=("$file")
		fi
	done

	printf '\n%b\n' "${yellow}The following files were provided:${res_term}"
	printf '%s\n' "${files[@]}"
	printf '\n'

	if ((${#success[@]})); then
		printf '%b\n' "${green}The following files were successfully uploaded:${res_term}"
		printf '%s\n' "${success[@]}"
		printf '\n'
	fi

	if ((${#fail[@]})); then
		printf '%b\n' "${red}The following files were not uploaded successfully:${res_term}"
		printf '%s\n' "${fail[@]}"
		printf '\n'
	fi

	return 0
}

# script basename
script="${0##*/}"

declare -a files

# 'success' is for successfully uploaded files, 'fail' is for failed uploads
declare -a success fail

parse_args "$@" && \
setup_ssh && \
check_remote_dir && \
upload_files
