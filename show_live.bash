#!/bin/bash

color_red=$(tput setaf 1)
color_green=$(tput setaf 2)
color_yellow=$(tput setaf 3)
color_reset=$(tput sgr0)

flag_help=       # set if -h||--help was given as an argument
flag_time=       # set if -t||--time was given as an argument
flag_default=    # set if -d||--default was given as an argument
flag_misc=       # set if an invalid argument was given

unset email_date # date for email in RFC 5322 format. Set when creating email

time_regex='((0?[1-9]|1[0-2]):[0-5][0-9]) ([AP]M)' # e.g. 0?1-12:00-59 AM/PM
time_regex_no_ampm='((0?[1-9]|1[0-2]):[0-5][0-9])' # e.g. 0?1-12:00-59
ampm_regex='[AP]M'
unset the_time

yes_sent="/home/encoder/w/show_live_done" # if this file exists, then the email was already sent; exit instead

# print script usage and exit
print_usage_and_exit()
{
	IFS= read -r -d $'\0' help_msg <<- USAGE_HEREDOC || true
	$(printf ${color_yellow})$(basename $0): $(printf ${color_reset})Sends the "Show live" email with a the subject containing the time (of one minute ago by default).
	
		Allowed options:
		  -d|--default       Sends the email with the time of one minute ago.
		                     This is also the default behaviour if no arguments are given.
		                     Cannot be used with the '-t|--time' option.
		  -t|--time          Specify a time (HH:MM AM/PM). Cannot be used with the '-d|--default' option.
		  -h|--help          Prints this message and exists.
	USAGE_HEREDOC

	printf "%s\\n" "$help_msg" >&2
	exit 1
}

# print a given error and exit
print_error_and_exit()
{
	# call the help function if '--help' was given
	if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
		error_msg="$2"
		printf "%b%s%b%s%b%s%b\\n" "${color_red}" "ERROR "$(basename $0)": " "${color_yellow}" "${error_msg}"\
		"${color_red}" " Exiting..." "${color_reset}" >&2
		print_usage_and_exit
	else
		error_msg="$1"
		printf "%b%s%b%s%b%s%b\\n" "${color_red}" "ERROR "$(basename $0)": " "${color_yellow}" "${error_msg}"\
		"${color_red}" " Exiting..." "${color_reset}" >&2
		exit 1
	fi

}

# parse the given arguments
parse_args()
{
	until [ $# -le 0 ]; do
		case "$1" in
			-h|--help) flag_help="y" ;;
			-t|--time) if [ -z "${flag_time:+x}" ]; then

							flag_time="y"
							time_check "$2" "$3" 
							time_check_ecode=$?
							case ${time_check_ecode} in
								$shift_one) shift 1 ;;
								$shift_two) shift 2 ;;
								*)         shift 1 ;;
							esac

							# set ignore case for regex matching
							shopt -u nocasematch
						fi ;;
			-d|--default) flag_default="y" ;;
			*) flag_misc="y" ;;
		esac
		shift 1
	done

	[ -n "${flag_help:+x}" ] && print_usage_and_exit
	[ -n "${flag_misc:+x}" ] && print_error_and_exit '-h' "Invalid argument given!"

	# if both the --default and --time arguments were given, exit
	if [ -n "${flag_default:+x}" ] && [ -n "${flag_time:+x}" ]; then
		print_error_and_exit "Both '--default' and '--time' arguments were given!"

	# '--time' argument was given
	elif [ -n "${flag_time:+x}" ]; then
		custom_time
	
	# '--default' argument was given
	#elif [ -n "${flag_default:+}" ]; then
		#default_time

	# no args; default time
	else
		default_time
	fi
}

# make sure an appropriate time was given
time_check()
{
	the_time="$1"
	am_or_pm="$2"

	shift_one=1
	shift_two=2

	# set ignore case for regex matching
	shopt -s nocasematch

	#  if the time regex matches, we don't check the second argument,
	#+ and shift 1 in parse_args()
	if [[ "${the_time}" =~ $time_regex ]]; then
		return $shift_one

	# if no AM/PM was given in the first argument, 
	#+ check to make sure that the second argument is AM or PM,
	#+ and shift 2 in parse_args() if it is
	elif [[ "${the_time}" =~ $time_regex_no_ampm ]]; then

		if [[ "${am_or_pm}" =~ $ampm_regex ]]; then
			the_time="${the_time} ${am_or_pm}"
			return $shift_two

		#  if the second argument is not AM or PM, just shift one;
		#+ assume that the user didn't give a second argument to '--time'
		else
			unset the_time
			return $shift_one
		fi

	# garbage argument given that doesn't match either time regexes
	else
		unset the_time
		return $shift_one
	fi
}

# if '--default' or no args were given
default_time()
{
	# get the date from 1 minute ago
	the_time="$(date --date="1 minute ago" '+%I:%M %p')"

	# if the hour is between 1 and 9 inclusive, remove the leading 0
	if [ "${the_time:0:1}" == "0" ]; then
		the_time="${the_time:1}"
	fi
}

# if '--time' was given
custom_time()
{
	#  an invalid time in time_check() should result in $the_time being explicitly unset;
	#+ that check is made here
	[ -z "${the_time+x}" ] && print_error_and_exit "Invalid time was given!"

	# capitalize am/pm if they were given in lowercase
	the_time="${the_time^^}"

	# if the hour is between 1 and 9 inclusive, remove the leading 0
	if [ "${the_time:0:1}" == "0" ]; then
		the_time="${the_time:1}"
	fi
}

gen_and_print_email()
{
	from="FROM_ADDRESS"
	to="TO_ADDRESS"
	subject="Show live ${the_time}"
	email_date="$(date --rfc-email)"

	IFS= read -r -d $'\0' message <<- MAIL_HEREDOC || true
		From: ${from}
		To: ${to}
		BCC: ${from}
		Subject: ${subject}
		Date: ${email_date}
		MIME-Version: 1.0
		Content-Type: text/plain; charset=utf-8; format=flowed
		Content-Transfer-Encoding: 7bit
		Content-Language: en-US
	
		MAIL_HEREDOC

	printf "%s\\n" "$message"
}
send_email()
{
	gen_and_print_email | msmtp --account=ACCOUNT --read-recipients
}

[ -f "${yes_sent}" ] && print_error_and_exit "Email already sent today! Exiting..."
parse_args "$@" && send_email
touch "${yes_sent}"
