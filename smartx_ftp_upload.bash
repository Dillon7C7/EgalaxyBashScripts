#!/bin/bash

red="$(tput setaf 1)"
green="$(tput setaf 2)"
yellow="$(tput setaf 3)"
res_term="$(tput sgr0)"


# print program usage
print_usage()
{
	printf '%s\n' "usage: ${script} [-h] JPEG [JPEG ...]"
} >&2

# print help and exit
print_help_and_exit()
{
	print_usage

	read -r -d $'\0' help_msg <<- EOF_HELP || true
	Upload JPEG image(s) to Smart-X's FTP server.

	positional arguments:
	  JPEG                   the image(s) to upload

	optional arguments:
	  -h, --help             show this message and exit
	EOF_HELP

	printf '\n%s\n' "$help_msg"
	exit 1
} >&2

# print errors and exit with a positive exit code
die()
{
	print_usage
	err_msg="$1"
	printf '%s\n' "${script}: error: ${err_msg}"
	exit 1
} >&2

# print a warning
warn()
{
	warn_msg="$1"
	printf '%b\n' "${script}: ${yellow}WARNING:${res_term} ${warn_msg}"
} >&2

# assume this script is called via 'sudo' as the 'encoder' user
# we need root privileges in order to start/stop OpenVPN (to create TUN devices)
check_user()
{
	[[ $(id -nu) == encoder ]] || die "Must be run as encoder !"

	return 0
}

# quick check for external binary dependencies
check_deps()
{
	command -v pass     &>/dev/null || die "pass (password manager) must be installed!"
	command -v identify &>/dev/null || die "imagemagick ('identify' binary) must be installed!"
	command -v lftp     &>/dev/null || die "lftp must be installed!"
	command -v openvpn  &>/dev/null || die "OpenVPN must be installed!"

	return 0
}

# get credentials from password manager
get_creds()
{
	# retrieving sensitive data from pass makes this script safe for sharing
	ftp_credentials="$(pass show ftp/smartx | head -n3)"
	
	password="$(sed -n '1p' <<< "$ftp_credentials" | cut -d' ' -f2)"
	username="$(sed -n '2p' <<< "$ftp_credentials" | cut -d' ' -f2)"
	host="$(sed -n '3p' <<< "$ftp_credentials" | cut -d' ' -f2)"

	return 0
}

# pass in an image
# this makes sure it exists, and is a JPEG
_check_img()
{
	local img="$1"
	[[ -f "$img" ]] || die "Given argument '${img:-NULL}' is not a file"

	file_format="$(identify -format '%m\n' "$img" 2>/dev/null)"
	[[ "$file_format" == "JPEG" ]] || die "Given file '$img' is not a JPEG"

	return 0
}

# pass in "$@"
parse_args()
{
	while [[ $# -gt 0 ]]; do
		case "$1" in
			-h|--help) print_help_and_exit ;;
			-*) die "unrecognized argument: '$1'" ;;
			*) _check_img "$1"; images+=("$1") ;;
		esac
		shift 1
	done

	((${#images[@]})) || die "at least one image is required"

	return 0
}

# first argument: start or stop
ovpn()
{
	if [[ "$1" != "start" ]] && [[ "$1" != "stop" ]]; then
		die "Neither 'start' nor 'stop' was provided to ovpn()"
	elif [[ "$1" == "start" ]]; then
		trap 'ovpn stop; rm -rf "$img_check_dir"' EXIT
	fi

	action="$1"

	if sudo systemctl "$action" openvpn-client@smartx.service; then
		printf '%s\n' "OpenVPN $action connection successful"
		# give some time for the routes to be pushed before attempting to upload to the FTP server
		sleep 5
	else
		die "Failed to $action Smart-X OpenVPN service"
	fi

	return 0
}

# test FTP connection
test_ftp()
{
	lftp -u "${username},${password}" "$host" <<- FTP_EOF
		set ssl:verify-certificate no
		set ftp:ssl-protect-data true
		bye
	FTP_EOF
	[[ $? -eq 0 ]] || die "the connection to the FTP server failed"

	return 0
}

# make sure image doesn't already exist on remote FTP
# we check by trying to download the image
# pass in the image
_check_remote_img()
{
	local img="$1"

	pushd "$img_check_dir" &>/dev/null

	# make sure image doesn't already exist on the FTP server
	lftp -u "${username},${password}" "$host" 2>/dev/null <<- CHECK_EOF
		set ssl:verify-certificate no
		set ftp:ssl-protect-data true
		cd nakednews/email/images/fan-zones-emails/
		get "${img##*/}"
	CHECK_EOF

	ecode=$?

	popd &>/dev/null

	if [[ $ecode -eq 0 ]]; then
		warn "'$img' already exists on the FTP server"
		return 1
	fi

	return 0
}

# pass in an image to upload
_upload_file()
{
	# 'ftp:ssl-protect-data' enables data channel encryption, which is required before executing any commands that will transfer data

	local img="$1"

	# if the image already exists on the remote FTP site, immediately return
	if ! _check_remote_img "$img"; then
		return 1
	fi

	# upload the image to the server
	lftp -u "${username},${password}" "$host" <<- UPLOAD_EOF
		set ssl:verify-certificate no
		set ftp:ssl-protect-data true
		cd nakednews/email/images/fan-zones-emails/
		put "$img"
	UPLOAD_EOF

	if [[ $? -ne 0 ]]; then
		warn "Upload of '$img' failed"
		return 1
	fi

	return 0
}

# batch upload
upload_files()
{
	mkdir "$img_check_dir"

	for img in "${images[@]}"; do
		if _upload_file "$img"; then
			win+=("$img")
		else
			fail+=("$img")
		fi
	done

	printf '\n%b\n' "${yellow}The following images were provided:${res_term}"
	printf '%s\n' "${images[@]}"
	printf '\n'

	if ((${#win[@]})); then
		printf '%b\n' "${green}The following images were successfully uploaded:${res_term}"
		printf '%s\n' "${win[@]}"
		printf '\n'
	fi

	if ((${#fail[@]})); then
		printf '%b\n' "${red}The following images were not uploaded:${res_term}"
		printf '%s\n' "${fail[@]}"
		printf '\n'
	fi

	return 0
}


# script basename
script="${0##*/}"

declare -a images

# 'win' is for successfully uploaded images, 'fail' is for failed uploads
declare -a win fail

# cd into this directory before attempting to get the remote image
img_check_dir="/tmp/${script}-img_check"


parse_args "$@" && \
check_user && \
check_deps && \
get_creds && \
ovpn 'start' && \
test_ftp && \
upload_files
