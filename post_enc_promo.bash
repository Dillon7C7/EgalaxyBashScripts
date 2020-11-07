#!/bin/bash

today_date="$(date +%F)"                # yyyy-mm-dd
sun_date="$(date -d "2 day" +%F)"       # yyyy-mm-dd
day_of_week="$(date +%A)"

################## TERMINAL COLOR VARIABLE ASSIGNMENT BEGINS ###############################
color_red=$(tput setaf 1)
color_green=$(tput setaf 2)
color_yellow=$(tput setaf 3)
color_magenta=$(tput setaf 5)
color_cyan=$(tput setaf 6)
color_oj=$(tput setaf 9)
color_reset=$(tput sgr0)
################## TERMINAL COLOR VARIABLE ASSIGNMENT ENDS #################################

################## EXIT CODE VARIABLE ASSIGNMENT BEGINS ####################################
ecode_success=0           # exit without error
ecode_error=1             # exit with error
ecode_lockfail=2          # problem with locking
ecode_recvsig=3           # a signal (INT, QUIT, or TERM), was received
ecode_remote_dp_fail=4    # the remote promo was not found
ecode_remote_dp_names=5   # the Friday and Sunday promos have non-consecutive numbers
################## EXIT CODE VARIABLE ASSIGNMENT ENDS ######################################

################## FLAGS FOR ARGUMENTS BEGINS ##############################################
flag_help=               # flag for -h|--help argument
flag_default=            # flag for -d|--default argument
flag_social=             # flag for -s|--social argument
flag_both_social=        # flag for -t|--both-social argument
flag_both=               # flag for -b|--both argument
flag_alt=                # flag for -a|--alt argument
################## FLAGS FOR ARGUMENTS ENDS ################################################

################## FLAGS FOR FUNCTION COMPLETION BEGINS ####################################
flag_parse_args=         # flag for parse_args() successful completion
flag_start_ssh_master=   # flag for start_ssh_master() successful completion
flag_send_email=         # flag for send_email() successful completion
################## FLAGS FOR FUNCTION COMPLETION ENDS ######################################

################## ACTUAL WORK VARIABLE ASSIGNMENT BEGINS ##################################
promo="${today_date}_DP_1080.mp4"                   # yyyy-mm-dd_DP_1080.mp4
promo_sun="${sun_date}_DP_1080.mp4"                 # yyyy-mm-dd_DP_1080.mp4
social_promo="${today_date}_DP_720.mp4"             # yyyy-mm-dd_DP_720.mp4
social_sun_promo="${sun_date}_DP_720.mp4"           # yyyy-mm-dd_DP_720.mp4
alt_default_dp='1080_1.mp4'                         # default name for alt promo after download

remote_host='REMOTE_HOST'                               # 'remote' (work station) hostname
remote_dp_dir='NEW_REMOTE_DP_DIR'                          # remote path to promo
remote_dp="${remote_dp_dir}${promo}"                # absolute path to default remote dp
remote_sun_dp="${remote_dp_dir}${promo_sun}"        # absolute path to Sunday remote dp
remote_alt_dp="${remote_dp_dir}${alt_default_dp}"   # absolute path to alt remote dp

default_regex='^\./1080_welcome_[0-9]\{4\}\.mp4$'   # escape { and } because variables in the heredoc are expanded by bash
social_regex='^\./720_welcome_[0-9]\{4\}\.mp4$'     # escape { and } because variables in the heredoc are expanded by bash

local_dir='LOCAL_DIR'                        # destination path for scp promo
local_dp="${local_dir}${promo}"
local_dp_sun="${local_dir}${promo_sun}"
################## ACTUAL WORK VARIABLE ASSIGNMENT ENDS ###################################

lockdir="/tmp/"$(basename "$0")"/"
lockfile="${lockdir}pid"

ssh_control_socket="${lockdir}$$-ssh_socket" # use the lock dir for temp files

################## EMAIL VARIABLE ASSIGNMENT BEGINS ########################################
mime_boundary="---------324LKHG9TH3SG"
unset date_header                                  # will get a slightly more accurate time when assigning this when creating the mail message
today_date_msg="$(date +'%B %d, %Y')"              # Mon, dd, yyyy
sunday_date_msg="$(date -d "2 day" +'%B %d, %Y')"  # Mon, dd, yyyy

dirURL='DIRURL'
link="${dirURL}${promo}"
link_sun="${dirURL}${promo_sun}"

to="TO_ADDRESS"
from="FROM_ADDRESS"
cc="CC_ADDRESS"
subject="New Files From NN (${today_date_msg})"
################## EMAIL VARIABLE ASSIGNMENT ENDS ##########################################

# take care of script locking
locking()
{
	# if lock is successful...
	if mkdir "${lockdir}" &>/dev/null; then

		# set up an exit trap (cleanup function) for the rest of the script
		trap 'ecode=$?; cleanup $ecode; echo "Exit: $ecode."' EXIT

		# echo PID into the lock file
		echo $$ > "${lockfile}"

		#+ exit with a non-zero exit code if a signal was received
		#  the trap on EXIT will do the cleanup, and the signal trap exit code will be passed to it
		trap 'echo "Killed by a signal"; exit ${ecode_recvsig}' SIGHUP SIGINT SIGQUIT SIGTERM
		print_success "Got a lock!"

		return 0
	else

		# lock failed, check to see if the lock file's PID's process is still alive
		otherPID="$(cat "${lockfile}")"

		#+ if cat isn't able to read the file, another instance is probably
		#  about to remove the lock; exit: we are still locked
		if [ $? -ne 0 ]; then
			print_error_and_exit "lock failed, PID ${otherPID} is active" -e $ecode_lockfail
		fi

		#+ if we are unable to kill this PID's process, assume that it is stale;
		#  remove the lock dir and restart the script
		if ! kill -0 ${otherPID} &>/dev/null; then
			echo "Removing stale lock of non-existent ${otherPID}" >&2
			cleanup $ecode_success
			echo "Restarting..."
			exec "$0" "$@"
		else
			echo "Lock is valid; PID ${otherPID} is active"
			exit $ecode_lockfail
		fi
	fi
}

# parse arguments given to script. make sure that the script argument list $@ is passed when calling this function
parse_args()
{
	# loop through user-provided arguments
	while [ $# -gt 0 ]; do
		case "$1" in
			-s|--social) flag_social=y ;;
			-t|--both-social) flag_both_social=y ;;
			-a|--alt) flag_alt=y ;;
			-b|--both) flag_both=y ;;
			-d|--default) flag_default=y ;;
			-h|--help) flag_help=y ;;
			*) print_error_and_exit "An invalid option was given!" '-h' ;;
		esac
		shift 1
	done

	## handle these arguments before locking later in the script

	# if the '--help' option was given, print the help msg and exit
	if [ -n "${flag_help:+x}" ]; then
		print_usage_and_exit
	fi

	[ $? -eq 0 ] && flag_parse_args=y || print_error_and_exit "parse_args() failed!"
}

# Print script options and exit
print_usage_and_exit()
{
	printf '%b%s%b%s\n' "${color_magenta}" "$(basename $0): " "${color_reset}" "Downloads the daily promo from desktop, renames it, uploads it to beer,"
	printf '%s\n\n' "                     and sends a completion email. Without any arguments given, the '--default' flag is assumed."

	printf '%b%s%b\n' "${color_cyan}" "Allowed options:" "${color_reset}"
	printf '%b  %s%b%s\n\n' "${color_yellow}" "-h|--help          " "${color_reset}" "Prints this message and exits."
	printf '%b  %s%b%s\n' "${color_yellow}" "-d|--default       " "${color_reset}" "Uploads and renames the regular DP. This is the default behaviour Mon-Thurs."
	printf '%b  %s%b  \n' "${color_green}" "                   Can only be used by itself, or with the '-s|--social' option." "${color_reset}"
	printf '%b  %s%b  \n\n' "${color_oj}" "                   Cannot be used with the '-a|--alt' '-b|--both' or '-t|--both-social' options." "${color_reset}"

	printf '%b  %s%b%s\n' "${color_yellow}" "-b|--both          " "${color_reset}" "Uploads and renames the Friday and Sunday DPs. Only works on Friday. This is the default behaviour on Friday."
	printf '%b  %s%b  \n' "${color_green}" "                   Can only be used by itself, or with the 't|--both-social' option." "${color_reset}"
	printf '%b  %s%b  \n\n' "${color_oj}" "                   Cannot be used with the '-d|--default' '-a|--alt' or 's|--social' options." "${color_reset}"
	printf '%b  %s%b%s\n' "${color_yellow}" "-s|--social        " "${color_reset}" "Renames the social DP on ${remote_host}, if it exists. Quit if it is not found."
	printf '%b  %s%b  \n' "${color_green}" "                   Can only be used by itself, or with the '-d|--default' or '-a|--alt' options." "${color_reset}"
	printf '%b  %s%b  \n\n' "${color_oj}" "                   Cannot be used with the '-b|--both' or '-t|--both-social' options." "${color_reset}"
	printf '%b  %s%b%s\n' "${color_yellow}" "-t|--both-social   " "${color_reset}" "Renames the social Friday and Sunday DPs on ${remote_host}, if they exist. Quit if they are not found."
	printf '%b  %s%b  \n' "${color_green}" "                   Can only be used by itself, or with the '-b|--both' option." "${color_reset}"
	printf '%b  %s%b  \n\n' "${color_oj}" "                   Cannot be used with the '-d|--default' '-a|--alt' or '-s|--social' options." "${color_reset}"
	printf '%b  %s%b%s\n' "${color_yellow}" "-a|--alt           " "${color_reset}" "There is only one DP (with the default name 1080_1.mp4)."
	printf '%b  %s%b  \n' "${color_green}" "                   Can only be used by itself, or with the '-s|--social' option." "${color_reset}"
	printf '%b  %s%b  \n\n' "${color_oj}" "                   Cannot be used with the '-d|--default' '-b|--both' or '-t|--both-social' options." "${color_reset}"
	exit $ecode_error
} >&2

# Command was successful
print_success()
{
	printf '%b%s%b%s%b\n' "$color_green" "SUCCESS "$(basename "$0")": " "$color_yellow" "$1" "$color_reset"
}

# Print a warning message (but don't exit)
print_warn()
{
	printf '%b%s%b%s%b\n' "$color_magenta" "WARNING "$(basename "$0")": " "$color_yellow" "$1" "$color_reset" >&2
}

#+ Print an error message and exit,
#  optional '-h' to print help before exiting
#  optional '-e' followed by a number ($3) to specify exit code 
print_error_and_exit()
{
	printf "%b%s%b%s%b%s%b\\n" "$color_red" "ERROR "$(basename "$0")": " "$color_yellow" "$1 " "$color_red" "Exiting..." "$color_reset" >&2
	case "$2" in
		-h) { echo ""; print_usage_and_exit; } ;;
		-e) case "$3" in # check to see if "$3" is a number. If it's not, exit with 1
				''|*[!0-9]*) exit $ecode_error ;;
				*) exit $3;;
			esac ;;
		*) exit $ecode_error ;;
	esac
}

# Set up ssh connection sharing
start_ssh_master()
{
	# make sure that parse_args() is ran before this function
	[ -z "${flag_parse_args:+x}" ] && print_error_and_exit "arse_args() must be run before start_ssh_master()!"

	# test host for ssh connectivity
	ssh -o 'ConnectTimeout=10' -S "$ssh_control_socket" "${remote_host}" /bin/true &>/dev/null
	[ $? -eq 0 ] || print_error_and_exit "ssh server doesn't appear to be running on ${remote_host}!"

	# -f: background. -M: "master" mode for connection sharing. -N: Do no execute remote command.
	ssh -f -M -N -o 'ControlMaster=yes' -S "$ssh_control_socket" "${remote_host}"
	[ $? -eq 0 ] && flag_start_ssh_master="y" || print_error_and_exit "Failed to start a master ssh connection!"
}

# Function that does the actual work
copy_and_upload_dp()
{
	# make sure that start_ssh_master() is ran before this function
	if [ -z "${flag_start_ssh_master:+x}" ]; then
		print_error_and_exit "Run start_ssh_master() first!"

	# if the '--default' option is given...
	elif [ -n "${flag_default:+x}" ]; then

		# and the '--alt' option was given, print the error, help msg, and exit
		if [ -n "${flag_alt:+x}" ]; then
			print_error_and_exit "The '--default' option must not be provided with the '--alt' option!" -h

		# and the '--both' option was given, print the error, help msg, and exit
		elif [ -n "${flag_both:+x}" ]; then
			print_error_and_exit "The '--default' option must not be provided with the '--both' option!" -h

		# and the '--both-social' option was given, print the error, help msg, and exit
		elif [ -n "${flag_both_social:+x}" ]; then
			print_error_and_exit "The '--default' option must not be provided with the '--both-social' option!" -h

		# if the social flag is set, 
		elif [ -n "${flag_social:+x}" ]; then
			social
			default

		# no '--alt', '--both', 'both-social', or '--social' flags, just call the default function
		else
			default
		fi

	# if the '--alt' option was given
	elif [ -n "${flag_alt:+x}" ]; then

		if [ -n "${flag_both:+x}" ]; then
			print_error_and_exit "The '--alt' option must not be provided with the '--both' option!" -h

		elif [ -n "${flag_both_social:+x}" ]; then
			print_error_and_exit "The '--alt' option must not be provided with the '--both-social' option!" -h

		elif [ -n "${flag_social:+x}" ]; then
			social
			alt

		else
			alt
		fi

	# if the '--both' option was given
	elif [ -n "${flag_both:+x}" ]; then

		if [ -n "${flag_social:+x}" ]; then
			print_error_and_exit "The '--both' option must not be provided with the '--social' option!" -h

		elif [ -n "${flag_both_social:+x}" ]; then
			both_social
			both

		else
			both
		fi

	# if the '--social' option was given
	elif [ -n "${flag_social:+x}" ]; then

		if [ -n "${flag_both_social:+x}" ]; then
			print_error_and_exit "The '--social' option must not be provided with the '--both-social' option!" -h

		else
			social
		fi

	# if the '--both-social' option was given
	elif [ -n "${flag_both_social:+x}" ]; then
		both_social

	# if no arguments are provided, do the default action
	else
		# '--both' is the default action on Fridays
		if [ $day_of_week = Friday ]; then
			flag_both=y
			both

		# '--default' is the default action on any other day
		else
			flag_default=y
			default
		fi
	fi
}

# default function; copy the DP from remote, rename, and upload to beer
default()
{
	# idempotently make sure file doesn't exist on local first, to prevent a second run from transferring again
	if [ -f "${local_dp}" ]; then
		print_error_and_exit "${local_dp} already exists; script was already ran today!"
	fi

	ssh -T -o ControlPath=${ssh_control_socket} "${remote_host}" /bin/sh <<-DEFAULT_HEREDOC

		cd -P ${remote_dp_dir}
		find_output="\$(find . ! -name . -prune)"
		if [ \$(printf '%s\n' "\$find_output" | grep -cE $default_regex) -eq 1 ]; then
			mv "\$(printf '%s\n' "\$find_output" | grep -E $default_regex)" "$promo"
		else
			exit $ecode_remote_dp_fail
		fi

	DEFAULT_HEREDOC

	ssh_ecode=$?

	# the heredoc returns this particular exit code if the number of regex matches is not 1
	[ $ssh_ecode -eq $ecode_remote_dp_fail ] && print_error_and_exit "Either the default promo wasn't found, or there are too many files that match the regex on ${remote_host}!"
	[ $ssh_ecode -ne 0 ] && print_error_and_exit "ssh in default() failed!"

	# copy file from workstation
	scp -o ControlPath=${ssh_control_socket} "${remote_host}:${remote_dp}" "${local_dp}" &>/dev/null
	[ $? -eq 0 ] || print_error_and_exit "scp of promo failed!"

	# upload file to beer
	bash -c "${local_dir}upload2Beer.sh -d promo ${local_dp}"
	[ $? -eq 0 ] || print_error_and_exit "upload of promo to beer failed!"

	send_email || print_error_and_exit "sending of email failed!"
}

# Like default, but account for Sunday DP as well on Friday
both()
{
	# make sure we are using the '--both' argument on a Friday only!
	[ $day_of_week = Friday ] || print_error_and_exit "'--both' argument is only valid on Fridays!"

	# idempotently make sure files don't exist on local first, to prevent a second run from transferring again
	if [ -f "${local_dp}" ] || [ -f "${local_dp_sun}" ]; then
		if [ -f "${local_dp}" ]; then
			print_error_and_exit "${local_dp} already exists; script was already ran today!"
		else
			print_error_and_exit "${local_dp_sun} already exists; script was already ran today!"
		fi
	fi

	#  $first_iter is used to check if the current iteration of the while loop is the first,
	#+ in which the 4-digit number of the first of the 2 downloaded DPs is initialized.
	#+ This value can then be used to ensure that the following DPs have a consecutive 4-digit number,
	#+ by comparing it to the 4-digit number found in the next iteration.
	ssh -T -o ControlPath=${ssh_control_socket} "${remote_host}" /bin/sh <<-BOTH_HEREDOC

		cd -P ${remote_dp_dir}
		find_output="\$(find . ! -name . -prune)"
		if [ \$(printf '%s\n' "\$find_output" | grep -cE $default_regex) -eq 2 ]; then
			first_iter=n
			while IFS= read -r dp_match; do
				if [ \$first_iter = n ]; then
					first_iter=y
					friday_DP=\$dp_match
					prev_show_num=\$(printf '%s\n' \$dp_match | cut -c16-19)
				else
					next_show_num=\$(printf '%s\n' \$dp_match | cut -c16-19)
					if [ \$next_show_num = \$((prev_show_num+1)) ]; then
						prev_show_num=\$((prev_show_num+1))
						mv "\$friday_DP" "$promo"
						mv "\$dp_match" "$promo_sun"
					else
						exit $ecode_remote_dp_names
					fi
				fi
			done <<-BOTH_INNER_HEREDOC
				\$(printf '%s\n' "\$find_output" | grep -E $default_regex | sort -t '_' -k3n,3)
			BOTH_INNER_HEREDOC
		else
			exit $ecode_remote_dp_fail
		fi

	BOTH_HEREDOC

	ssh_ecode=$?

	# the heredoc returns this particular exit code if the number of regex matches is not 2
	[ $ssh_ecode -eq $ecode_remote_dp_fail ] && print_error_and_exit "Either the Friday and Sunday promos weren't found, or there are too many files that match the regex on ${remote_host}!"

	# the heredoc returns this particular exit code if the downloaded DP numbers are not in consecutive order
	[ $ssh_ecode -eq $ecode_remote_dp_names ] && print_error_and_exit "The Friday and Sunday promo numbers are not in a consecutive order on ${remote_host}!"
	[ $ssh_ecode -ne 0 ] && print_error_and_exit "ssh in both() failed!"

	# copy Friday DP from workstation
	scp -o ControlPath=${ssh_control_socket} "${remote_host}:${remote_dp}" "${local_dp}" &>/dev/null
	[ $? -eq 0 ] || print_error_and_exit "scp of Friday promo failed!"

	# copy Sunday DP from workstation
	scp -o ControlPath=${ssh_control_socket} "${remote_host}:${remote_sun_dp}" "${local_dp_sun}" &>/dev/null
	[ $? -eq 0 ] || print_error_and_exit "scp of Sunday promo failed!"

	# upload files to beer
	bash -c "${local_dir}upload2Beer.sh -d promo ${local_dp}"
	[ $? -eq 0 ] || print_error_and_exit "upload of Friday promo to beer failed!"

	bash -c "${local_dir}upload2Beer.sh -d promo ${local_dp_sun}"
	[ $? -eq 0 ] || print_error_and_exit "upload of Sunday promo to beer failed!"

	send_email || print_error_and_exit "sending of email failed!"
}

# rename social DP; all remote /bin/sh commands are POSIX-compliant
social()
{
	ssh -T -o ControlPath=${ssh_control_socket} "${remote_host}" /bin/sh <<-SOCIAL_HEREDOC

		cd -P ${remote_dp_dir}
		find_output="\$(find . ! -name . -prune)"
		if [ \$(printf '%s\n' "\$find_output" | grep -cE $social_regex) -eq 1 ]; then
			mv "\$(printf '%s\n' "\$find_output" | grep -E $social_regex)" "$social_promo"
		else
			exit $ecode_remote_dp_fail
		fi

	SOCIAL_HEREDOC

	ssh_ecode=$?

	# the heredoc returns this particular exit code if the number of regex matches is not 1
	if [ $ssh_ecode -eq $ecode_remote_dp_fail ]; then
		print_error_and_exit "Either the 'social' promo wasn't found, or there are too many files that match the social regex on ${remote_host}!"
	elif [ $ssh_ecode -ne 0 ]; then
		print_error_and_exit "ssh in social() failed!"
	else
		return $ssh_ecode
	fi
}

# like social, but account for Sunday DP as well on Friday
both_social()
{
	# make sure we are using the '--both' argument on a Friday only!
	[ $day_of_week = Friday ] || print_error_and_exit "'--both' argument is only valid on Fridays!"

	ssh -T -o ControlPath=${ssh_control_socket} "${remote_host}" /bin/sh <<-BOTH_SOCIAL_HEREDOC

		cd -P ${remote_dp_dir}
		find_output="\$(find . ! -name . -prune)"
		if [ \$(printf '%s\n' "\$find_output" | grep -cE $social_regex) -eq 2 ]; then
			first_iter=n
			while IFS= read -r dp_match; do
				if [ \$first_iter = n ]; then
					first_iter=y
					friday_DP=\$dp_match
					prev_show_num=\$(printf '%s\n' \$dp_match | cut -c15-18)
				else
					next_show_num=\$(printf '%s\n' \$dp_match | cut -c15-18)
					if [ \$next_show_num = \$((prev_show_num+1)) ]; then
						prev_show_num=\$((prev_show_num+1))
						mv "\$friday_DP" "$social_promo"
						mv "\$dp_match" "$social_sun_promo"
					else
						exit $ecode_remote_dp_names
					fi
				fi
			done <<-BOTH_INNER_HEREDOC
				\$(printf '%s\n' "\$find_output" | grep -E $social_regex | sort -t '_' -k3n,3)
			BOTH_INNER_HEREDOC
		else
			exit $ecode_remote_dp_fail
		fi

	BOTH_SOCIAL_HEREDOC

	ssh_ecode=$?

	# the heredoc returns this particular exit code if the number of regex matches is not 1
	if [ $ssh_ecode -eq $ecode_remote_dp_fail ]; then
		print_error_and_exit "Either the Friday and Sunday 'social' promos weren't found, or there are too many files that match the social regex on ${remote_host}!"

	# the heredoc returns this particular exit code if the downloaded DP numbers are not in consecutive order
	elif [ $ssh_ecode -eq $ecode_remote_dp_names ]; then
		print_error_and_exit "The Friday and Sunday social promo numbers are not in a consecutive order on ${remote_host}!"
	elif [ $ssh_ecode -ne 0 ]; then
		print_error_and_exit "ssh in both_social() failed!"
	else
		return $ssh_ecode
	fi
}

# copy the "alt" DP from remote, rename, upload to beer
alt()
{
	# idempotently make sure file doesn't exist on local first, to prevent a second run from transferring again
	if [ -f "${local_dp}" ]; then
		print_error_and_exit "${local_dp} already exists; script was already ran today!"
	fi

	# copy file from work station
	scp -o ControlPath=${ssh_control_socket} "${remote_host}:${remote_alt_dp}" "${local_dp}" &>/dev/null
	[ $? -eq 0 ] || print_error_and_exit "scp of alt promo failed; check to make sure it exists, and that the network is up!"

	# upload file to beer
	bash -c "${local_dir}upload2Beer.sh -d promo ${local_dp}"
	[ $? -eq 0 ] || print_error_and_exit "upload of alt promo to beer failed!"

	send_email || print_error_and_exit "sending of email failed!"
}

#  Craft a MIME-formatted email (html or plaintext)
#+ The \0 at the end is an explicit end marker that gives a 0 return code
create_email()
{
	date_header="$(date --rfc-email)"

IFS= read -r -d '\0' message <<MAIL_HEREDOC
From: ${from}
To: ${to}
Subject: ${subject}
Cc: ${cc}
BCC: ${from}
Date: ${date_header}
MIME-Version: 1.0
Content-Type: multipart/alternative; boundary="${mime_boundary}"
Content-Language: en-US

This is a multi-part message in MIME format.
--${mime_boundary}
Content-Type: text/plain; charset=utf-8; format=flowed
Content-Transfer-Encoding: 7bit

Hi Anthony,

There is a new Naked News daily promotion video for *${today_date_msg}* ready for production.
You can find the link below:
${link}

Thank you,

Dillon

--${mime_boundary}
Content-Type: text/html; charset=utf-8
Content-Transfer-Encoding: 7bit

<html>
  <head>
    <meta http-equiv="content-type" content="text/html; charset=UTF-8">
  </head>
  <body text="#000000" bgcolor="#FFFFFF">
    Hi Anthony,<br>
    <br>
    There is a new Naked News daily promotion video for <b>${today_date_msg}</b>
    ready for production.<br>
    You can find the link below:<br>
    <a 
      href="${link}">${link}</a><br>
    <br>
    Thank you,<br>
    <br>
    Dillon<br>
   </body>
</html>

--${mime_boundary}--
\0
MAIL_HEREDOC

	printf '%s\n' "$message"
}

create_both_email()
{
	date_header="$(date --rfc-email)"

IFS= read -r -d '\0' message <<BOTH_MAIL_HEREDOC
From: ${from}
To: ${to}
Subject: ${subject}
Cc: ${cc}
BCC: ${from}
Date: ${date_header}
MIME-Version: 1.0
Content-Type: multipart/alternative; boundary="${mime_boundary}"
Content-Language: en-US

This is a multi-part message in MIME format.
--${mime_boundary}
Content-Type: text/plain; charset=utf-8; format=flowed
Content-Transfer-Encoding: 7bit

Hi Anthony,

There is a new Naked News daily promotion video for *${today_date_msg}* ready for production.
You can find the link below:
${link}

Additionally, there is a new Naked News daily promotion video for *${sunday_date_msg}* ready for production.
You can find the link below:
${link_sun}

Thank you,

Dillon

--${mime_boundary}
Content-Type: text/html; charset=utf-8
Content-Transfer-Encoding: 7bit

<html>
  <head>
    <meta http-equiv="content-type" content="text/html; charset=UTF-8">
  </head>
  <body text="#000000" bgcolor="#FFFFFF">
    Hi Anthony,<br>
    <br>
    There is a new Naked News daily promotion video for <b>${today_date_msg}</b>
    ready for production.<br>
    You can find the link below:<br>
    <a
      href="${link}">${link}</a><br>
    <br>
    Additionally, there is also a new Naked News daily promotion video
    for <b>${sunday_date_msg}</b> ready for production.<br>
    You can find the link below:<br>
    <a
      href="${link_sun}">${link_sun}</a><br>
    <br>
    Thank you,<br>
    <br>
    Dillon<br>
   </body>
</html>

--${mime_boundary}--
\0
BOTH_MAIL_HEREDOC

	printf '%s\n' "$message"
}
# use msmtp to send mail
send_email()
{
	# send a different email depending on which of '--default' or '--both' flag was given
	if [ -n "${flag_both:+x}" ]; then
		create_both_email | msmtp --account=egalaxy --read-recipients
	# default
	else
		create_email | msmtp --account=egalaxy --read-recipients
	fi

	if [ $? -eq 0 ]; then
		flag_send_email=y
		print_success "Email sent!"
	fi
}

# cleanup function; "$1" is a passed in exit code
cleanup()
{
	#+ if the exit code passed is 0 (or no exit code was passed at all),
	#  try to remove the remote DP(s)
	if [ $1 -eq $ecode_success ] || [ -z "$1" ]; then

		#+ check to see if a previous ssh master connection was established,
		#  and if its socket file still exists
		if [ -n "${flag_start_ssh_master:+x}" ] && [ -S "${ssh_control_socket}" ]; then

			# delete the remote Friday and Sunday DPs if the '--both' flag was given
			if [ -n "${flag_both:+x}" ]; then

				ssh -T -o ControlPath=${ssh_control_socket} "${remote_host}" /bin/sh <<-BOTH_CLEANUP_HEREDOC
					rm -f ${remote_dp} || exit 2
					rm -f ${remote_sun_dp} || exit 3
				BOTH_CLEANUP_HEREDOC

				both_del_ecode=$?

				# print a warning if deleting either of the remote promos failed
				if [ $both_del_ecode -eq 2 ]; then
					print_warn "Failed to delete the remote Friday promo ${remote_dp} on ${remote_host}!"
				elif [ $both_del_ecode -eq 3 ]; then
					print_warn "Failed to delete the remote Sunday promo ${remote_sun_dp} on ${remote_host}!"
				elif [ $both_del_ecode -ne 0 ]; then
					print_warn "Failed to delete either the remote Friday DP ${remote_dp} or Sunday DP ${remote_sun_dp} on ${remote_host}!"
				fi

			# otherwise, just delete the remote DP
			else
				ssh -T -o ControlPath=${ssh_control_socket} "${remote_host}" /bin/sh <<-CLEANUP_HEREDOC
					rm -f ${remote_dp} || exit 1
				CLEANUP_HEREDOC

				# print a warning if deleting the remote promo failed
				[ $? -ne 0 ] && print_warn "Failed to delete the remote promo ${remote_dp} on ${remote_host}!"

			fi
		fi
	
	#+ if the exit code passed was set by the signal trap,
	#  remove the local promo file, and remove the beer DP if the email has not been sent
	elif [ $1 -eq $ecode_recvsig ]; then
		rm -f "${local_dp}"
		rm -f "${local_dp_sun}"

		if [ -z "${flag_send_email:+x}" ]; then
			ssh BEER_USER@BEER_HOST BEER_COMMAND
			[ $? -ne 0 ] && print_warn "Failed to delete the uploaded promo ${local_dp} on beer!"
		fi
	fi

	# close the ssh master connection
	ssh -q -S "$ssh_control_socket" -O 'exit' "${remote_host}"

	# remove the lock
	rm -rf "${lockdir}"
}

trap 'ecode=$?; printf "%s\\n" "Exit code: ${ecode}."' EXIT

parse_args "$@" && locking && start_ssh_master && copy_and_upload_dp
