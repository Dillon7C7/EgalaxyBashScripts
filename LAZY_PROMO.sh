#!/bin/sh

# POSIX

# color escape sequences for current terminal
color_red="$(tput setaf 1)"
color_green="$(tput setaf 2)"
color_yellow="$(tput setaf 3)"
color_magenta="$(tput setaf 5)"
color_cyan="$(tput setaf 6)"
reset_term="$(tput sgr0)"

# basename of script
script_name="${0##*/}"

# work dir
work_dir="/home/encoder/w"

# print error message $1 and exit
__print_err_and_exit()
{
	local err_msg="$1"

	printf "%b%s%b%s%b\\n" "${color_red}" "ERROR ${script_name}: " "${color_yellow}" "${err_msg}" "${reset_term}"
	exit 1
}

# make sure script was not provided with any args
check_args_total_zero()
{
	if [ $# -ne 0 ]; then
		__print_err_and_exit "Do not provide any arguments!"
	fi

	return 0
}

# make sure we are in the chosen work dir
check_cur_dir()
{
	# must be in the working directory
	if [ "$(pwd -P)" != "$work_dir" ]; then
		__print_err_and_exit "MUST BE IN DIRECTORY: $work_dir"
	fi

	return 0
}

# set the variables we need, using the `date` command
set_date_variables()
{
	read -r weekday_name month_and_day month_abbrev day_num full_date <<- EOF_DATE
		$(date +'%A %b%d %b %d %F')
	EOF_DATE

	return 0
}

# make sure script is called on a weekday
check_weekday()
{
	# Day of the week can only be a weekday.
	if [ "$weekday_name" = "Saturday" ] || [ "$weekday_name" = "Sunday" ]; then
		print_err_and_exit "There is no daily promo on Saturday or Sunday!! \
		Only run this script from Monday to Friday."

	elif [ "$weekday_name" = "Friday" ]; then
		source_dir="friday"

	# mon - thurs
	else
		source_dir="today"
	fi

	[ -d "$source_dir" ] || __print_err_and_exit "${source_dir:-SOURCE_DIR} doesn't exist!"

	return 0
}

# make sure promo exists
check_promo()
{
	# example: today/DP_Feb12.mov
	local promo_regex="^${source_dir}/DP_${month_and_day}\.mov$"

	# store the output of find into a variable, so we don't have to run it twice
	local find_output="$(find "${source_dir}/" ! -path "${source_dir}/" -prune -type f -name "*mov")"

	# make sure we only have 1 regex match (one file). otherwise, exit
	if [ $(printf "%s\\n" "${find_output}" | grep -ciE ${promo_regex}) -eq 1 ]; then
		file_path_social="$(printf "%s\\n" "${find_output}" | grep -iE $promo_regex)"

	elif [ $(printf "%s\\n" "${find_output}" | grep -ciE ${promo_regex}) -eq 0 ]; then
		__print_err_and_exit "No promo found!"

	else
		__print_err_and_exit "Too many promos found! Make sure work dir has 1 only."
	fi

	return 0
}

# copy and encode the promo
promo_encode()
{
	local new_name_social="program_promo_social_${full_date}.mov"
	printf "%s\\n" "Filename is: ${new_name_social} !!!!!!"

	cp "${file_path_social}" "${work_dir}/${new_name_social}" && \
	./sk_encode.sh "${new_name_social}"

	return 0
}

check_args_total_zero && \
check_cur_dir && \
set_date_variables && \
check_weekday && \
check_promo && \
promo_encode
