#!/bin/bash

today_date="$(date +%F)"                # yyyy-mm-dd

################## TERMINAL COLOR VARIABLE ASSIGNMENT BEGINS ###############################
color_red=$(tput setaf 1)
color_green=$(tput setaf 2)
color_yellow=$(tput setaf 3)
color_magenta=$(tput setaf 4)
color_reset=$(tput sgr0)
################## TERMINAL COLOR VARIABLE ASSIGNMENT ENDS #################################

################## EXIT CODE VARIABLE ASSIGNMENT BEGINS ####################################
ecode_success=0          # exit without error
ecode_error=1            # exit with error
ecode_lockfail=2         # problem with locking
ecode_recvsig=3          # a signal (INT, QUIT, or TERM), was received
ecode_remote_dp_fail=4   # the remote promo was not found
################## EXIT CODE VARIABLE ASSIGNMENT ENDS ######################################

################## FLAGS FOR ARGUMENTS BEGINS ##############################################
flag_help=               # flag for -h|--help argument
flag_default=            # flag for -d|--default argument
flag_social=             # flag for -s|--social argument
flag_one=                # flag for -1|--one argument
flag_misc=               # flag for unsupported arguments
################## FLAGS FOR ARGUMENTS ENDS ################################################

################## FLAGS FOR FUNCTION COMPLETION BEGINS ####################################
flag_parse_args=         # flag for parse_args() successful completion
flag_start_ssh_master=   # flag for start_ssh_master() successful completion
flag_send_email=         # flag for send_email() successful completion
################## FLAGS FOR FUNCTION COMPLETION ENDS ######################################

################## ACTUAL WORK VARIABLE ASSIGNMENT BEGINS ##################################
remote_host='REMOTE_HOST'                               # 'remote' (work station) hostname
remote_dp_dir='REMOTE_DP_DIR'             # remote path to promo
remote_default_dp='1080_1.mp4'                      # default name for promo after download
remote_dp="${remote_dp_dir}${remote_default_dp}"    # absolute path to default remote dp

social_regex='^\./720_welcome_[0-9]\{4\}\.mp4$'     # escape { and } because variables in the heredoc are expanded by bash
one_regex='^\./1080_welcome_[0-9]\{4\}\.mp4$'       # escape { and } because variables in the heredoc are expanded by bash

local_dir='LOCAL_DIR'                        # destination path for scp promo
promo="${today_date}_DP_1080.mp4"                   # yyyy-mm-dd_DP_1080.mp4
social_promo="${today_date}_DP_720.mp4"             # yyyy-mm-dd_DP_720.mp4

local_dp="${local_dir}${promo}"
################## ACTUAL WORK VARIABLE ASSIGNMENT ENDNS ###################################

lockdir="/tmp/"$(basename "$0")"/"
lockfile="${lockdir}pid"

ssh_control_socket="${lockdir}$$-ssh_socket" # use the lock dir for temp files

################## EMAIL VARIABLE ASSIGNMENT BEGINS ########################################
mime_boundary="---------324LKHG9TH3SG"
unset date_header                       # will get a slightly more accurate time when assigning this when creating the mail message
today_date_msg="$(date +'%B %d, %Y')"   # Mon, dd, yyyy

dirURL='DIRURL'
link="${dirURL}${promo}"

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
		#  the trap on EXIT will do the cleanup, and the signal tra[ exit code will be passed to it
		trap 'echo "Killed by a signal"; exit ${ecode_recvsig}' SIGHUP SIGINT SIGQUIT SIGTERM
		echo "Got a lock!"

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
			-s|--social) flag_social="y" ;;
			-1|--one) flag_one="y" ;;
			-d|--default) flag_default="y" ;;
			-h|--help) flag_help="y" ;;
			*) flag_misc="y" ;;
		esac
		shift 1
	done

	[ $? -eq 0 ] && flag_parse_args="y" || print_error_and_exit "parse_args() failed!"
}

# Print script options and exit
print_usage_and_exit()
{
	IFS= read -r -d '\0' help_msg <<- USAGE_HEREDOC
		$(printf ${color_yellow})$(basename $0): $(printf ${color_reset})Downloads the daily promo from desktop, \
renames it, uploads it to beer,
		and sends a completion email. Without any arguments given, the '--default' flag is assumed.
		
		Allowed options:
		  -d|--default       Uploads and renames the regular DP (1080_1.mp4). This is the default behaviour.
		                     Cannot be used with the '-1|--one' option
		  -s|--social	     Renames the social DP on ${remote_host}, if it exists. Quit if it is not found.
		  -1|--one           There is only one DP (with a different default name). Cannot be used with '-d|--default'
		  -h|--help          Prints this message and exits
		\0
	USAGE_HEREDOC

	printf "%s\\n" "$help_msg" >&2 
	exit $ecode_error
}

# Print a warning message (but don't exit)
print_warn()
{
	printf "%b%s%b%s%b\\n" "$color_magenta" "WARNING "$(basename "$0")": " "$color_yellow" "$1" "$color_reset" >&2
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

	# -f: background. -M: "master" mode for connection sharing. -N: Do no execute remote command.
	ssh -f -M -N -o 'ControlMaster=yes' -S "$ssh_control_socket" "${remote_host}"
	[ $? -eq 0 ] && flag_start_ssh_master="y" || print_error_and_exit "Failed to start a master ssh connection!"
}

# Function that does the actual work
copy_and_upload_dp()
{
	# if the '--help' option was given, print the help msg and exit
	if [ -n "${flag_help:+x}" ]; then
		print_usage_and_exit

	# if an invalid option was given, print the error, print the help msg, and exit
	elif [ -n "${flag_misc:+x}" ]; then
		print_error_and_exit "An invalid option was given!" '-h'
	
	# make sure that start_ssh_master() is ran before this function
	elif [ -z "${flag_start_ssh_master:+x}" ]; then
		print_error_and_exit "Run start_ssh_master() first!"

	# if the '--default' option is given...
	elif [ -n "${flag_default:+x}" ]; then

		# and the '--one' option was given, print the error, help msg, and exit
		if [ -n "${flag_one:+x}" ]; then
			print_error_and_exit "The '--default' option must not be provided with the --one option!"

		# if the social flag is set, 
		elif [ -n "${flag_social:+x}" ]; then
			social
			default

		# no '--one' or '--social' flags, just call the default function
		else
			default
		fi

	# if the '--social' option was given
	elif [ -n "${flag_social:+x}" ]; then

		# always call social()
		social

		if [ -n "${flag_default:+x}" ]; then
			default
		elif [ -n "${flag_one:+}" ]; then
			one
		fi

	# if the '--one' option was given
	elif [ -n "${flag_one:+x}" ]; then

		if [ -n "${flag_default:+x}" ]; then
			print_error_and_exit "The '--one' option must not be provided with the --default option!"
		elif [ -n "${flag_social:+}" ]; then
			social
			one
		else
			one
		fi

	# if no arguments are provided, do the default action
	else
		default
	fi
}

# default function; copy the DP from remote, rename, and upload to beer
default()
{
	# idempotently make sure file doesn't exist on local first, to prevent a second run from transferring again
	if [ -f "${local_dp}" ]; then
		print_error_and_exit "${local_dp} already exists; script was already ran today!"
	fi

	# copy file from work station
	scp -o ControlPath=${ssh_control_socket} "${remote_host}:${remote_dp}" "${local_dp}" &>/dev/null
	[ $? -eq 0 ] || print_error_and_exit "scp of promo failed!"

	# upload file to beer
	bash -c "${local_dir}upload2Beer.sh -d promo ${local_dp}"
	[ $? -eq 0 ] || print_error_and_exit "upload of promo to beer failed!"

	send_email || print_error_and_exit "sending of email failed!"
}

# rename social DP; all remote /bin/sh commands are POSIX-compliant
social()
{
	ssh -T -o ControlPath=${ssh_control_socket} "${remote_host}" /bin/sh <<- SOCIAL_HEREDOC

		cd -P ${remote_dp_dir}
		find_output="\$(find . ! -name . -prune)"
		if [ \$(echo "\$find_output" | grep -cE $social_regex) -eq 1 ]; then
			mv "\$(echo "\$find_output" | grep -E $social_regex)" "$social_promo"
		else	
			exit $ecode_remote_dp_fail
		fi

	SOCIAL_HEREDOC

	ssh_ecode=$?

	# the heredoc returns this particular exit code if the number of regex matches is not 1
	[ $ssh_ecode -eq $ecode_remote_dp_fail ] && print_error_and_exit "Either the 'social' promo wasn't found, or there are too many files that match the social regex on ${remote_host}!"
	[ $ssh_ecode -ne 0 ] && print_error_and_exit "ssh in social() failed!"
}

# copy the "one" DP from remote, rename, upload to beer
one()
{
	# idempotently make sure file doesn't exist on local first, to prevent a second run from transferring again
	if [ -f "${local_dp}" ]; then
		print_error_and_exit "${local_dp} already exists; script was already ran today!"
	fi

	ssh -T -o ControlPath=${ssh_control_socket} "${remote_host}" /bin/sh <<- ONE_HEREDOC

		cd -P ${remote_dp_dir}
		find_output="\$(find . ! -name . -prune)"
		if [ \$(echo "\$find_output" | grep -cE $one_regex) -eq 1 ]; then
			mv "\$(echo "\$find_output" | grep -E $one_regex)" "$remote_default_dp"
		else	
			exit $ecode_remote_dp_fail
		fi

	ONE_HEREDOC

	ssh_ecode=$?

	# the heredoc returns this particular exit code if the number of regex matches is not 1
	[ $ssh_ecode -eq $ecode_remote_dp_fail ] && print_error_and_exit "Either the 'one' promo wasn't found, or there are too many files that match the regex on ${remote_host}!"
	[ $ssh_ecode -ne 0 ] && print_error_and_exit "ssh in one() failed!"

	# copy file from work station
	scp -o ControlPath=${ssh_control_socket} "${remote_host}:${remote_dp}" "${local_dp}" &>/dev/null
	[ $? -eq 0 ] || print_error_and_exit "scp of promo failed!"

	# upload file to beer
	bash -c "${local_dir}upload2Beer.sh -d promo ${local_dp}"
	[ $? -eq 0 ] || print_error_and_exit "upload of promo to beer failed!"

	send_email || print_error_and_exit "sending of email failed!"
}

#  Craft a MIME-formatted email (html or plaintext)
#+ The \0 at the end is an explicit end marker that gives a 0 return code
create_email()
{
	date_header="$(date --rfc-email)"

IFS= read -r -d '\0' message << MAIL_HEREDOC
From: ${from}
To: ${to}
Subject: ${subject}
Cc: ${cc}
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

	printf "%s\\n" "$message"
}

# use msmtp to send mail
send_email()
{
	create_email | msmtp --account=egalaxy --read-recipients

	if [ $? -eq 0 ]; then
		flag_send_email="y"
		printf "%s\\n" "Email sent!"
	fi
}

# cleanup function; "$1" is a passed in exit code
cleanup()
{
	#+ if the exit code passed is 0 (or no exit code was passed at all),
	#  try to remove the remote DP
	if [ $1 -eq $ecode_success ] || [ -z "$1" ]; then

		#+ check to see if a previous ssh master connection was established,
		#  and that the socket file still exists
		if [ -n "${flag_start_ssh_master:+x}" ] && [ -S "${ssh_control_socket}" ]; then
			ssh -T -o ControlPath=${ssh_control_socket} "${remote_host}" /bin/sh <<- CLEANUP_HEREDOC
				rm -f ${remote_dp} || exit 1
			CLEANUP_HEREDOC

			# print a warning if deleting the remote promo failed
			[ $? -ne 0 ] && print_warn "Failed to delete the remote promo ${remote_dp} on ${remote_host}!"
		fi
	
	#+ if the exit code passed was set by the signal trap,
	#  remove the local promo file, and remove the beer DP if the email has not been sent
	elif [ $1 -eq $ecode_recvsig ]; then
		rm -f "${local_dp}"

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

# set up traps and locking
trap 'ecode=$?; printf "%s\\n" "Exit code: ${ecode}."' EXIT
locking

parse_args "$@" && start_ssh_master && copy_and_upload_dp
