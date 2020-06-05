#!/bin/sh

# POSIX

# color escape sequences for current terminal
red="$(tput setaf 1)"
green="$(tput setaf 2)"
yellow="$(tput setaf 3)"
magenta="$(tput setaf 5)"
cyan="$(tput setaf 6)"
reset_term="$(tput sgr0)"

# basename of script
script_name="${0##*/}"

# work dir
work_dir="/home/encoder/w"

# flags for options
unset flag_daily
unset flag_sunday

__print_usage()
{
	printf '%b%s%b%s\n\n' "${magenta}" "${script_name}: " "${reset_term}" "Deinterlaces the daily promo, renames it, and uploads it to beer."
	printf '%b%s%b\n' "${cyan}" "Allowed options:" "${reset_term}"
	printf '%b  %s%b%s\n' "${yellow}" "-h|--help      " "${reset_term}" "Prints this message and exits."
	printf '%b  %s%b%s\n' "${yellow}" "-d|--daily     " "${reset_term}" "Works on the daily promo only. This is the default behaviour if no opt is given."
	printf '%b  %s%b%s\n' "${yellow}" "-S|--sunday    " "${reset_term}" "Works on the Sunday promo only. Only works on Friday."
	printf '%b  %s%b%s\n' "${yellow}" "-b|--both      " "${reset_term}" "Works on both the daily (Friday) promo and the Sunday Promo. Alias for '--daily --sunday'. Only works on Friday."
} >&2


# print error message $1 and exit
__print_err_and_exit()
{
	err_msg="$1"

	printf '%b%s%b%s%b\n' "${red}" "ERROR ${script_name}: " "${yellow}" "${err_msg}" "${reset_term}" >&2
	__print_usage
	exit 1
}

# parse arguments
parse_args()
{
	while [ $# -gt 0 ]; do
		case "$1" in
			-h|--help) __print_usage; exit 1 ;;
			-d|--daily) flag_daily=1 ;;
			-S|--sunday) flag_sunday=1 ;;
			-b|--both) flag_daily=1; flag_sunday=1 ;;
			-dSb|-dbS|-bSd|-bdS|-Sdb|-Sbd) flag_daily=1; flag_sunday=1 ;;
			*) __print_err_and_exit "Invalid option '$1' given!" ;;
		esac
		shift
	done

	# if '--sunday' wasn't given, then we use the default option, '--daily'
	[ -z "${flag_sunday+x}" ] && flag_daily=1

	return 0
}

# make sure we are in the work dir
check_cur_dir()
{
	# must be in the working directory
	if [ "$(pwd -P)" != "$work_dir" ]; then
		__print_err_and_exit "MUST BE IN DIRECTORY: $work_dir"
	fi

	return 0
}

# make sure script is called on a weekday
check_weekday()
{
	weekday_name=$(date +%A)

	# Day of the week can only be a weekday.
	if [ "$weekday_name" = Saturday ] || [ "$weekday_name" = Sunday ]; then
		print_err_and_exit "There is no daily promo on Saturday or Sunday!! \
		Run this script from Monday to Friday only."

	# friday
	elif [ "$weekday_name" = Friday ]; then
		source_dir=friday

		# do Sunday stuff
		if [ -n "${flag_sunday+x}" ]; then
			source_dir_sun=weekend
			[ -d "$source_dir_sun" ] || __print_err_and_exit "${source_dir_sun:-SOURCE_DIR_WKD} doesn't exist!"
		fi

	# mon - thurs
	else
		# make sure '--sunday' or '--both' weren't given
		if [ -n "${flag_sunday+x}" ]; then
			__print_err_and_exit "Do not provide '--sunday' or '--both' options on any day except Friday!"
		else
			source_dir=today
		fi
	fi

	[ -d "$source_dir" ] || __print_err_and_exit "${source_dir:-SOURCE_DIR} doesn't exist!"

	return 0
}

# set the variables we need, using the `date` command
set_date_variables()
{
	# Mon - Fri
	if [ -n "${flag_daily+x}" ]; then
		read -r month_and_day full_date <<- EOF_DATE
			$(date +'%b%d %F')
		EOF_DATE
	fi

	# Sun
	if [ -n "${flag_sunday+x}" ]; then
		read -r month_and_day_sun full_date_sun <<- EOF_DATE_SUN
			$(date -d "2 day" +'%b%d %F')
		EOF_DATE_SUN
	fi

	return 0
}

# make sure promo exists
check_promo()
{
	# Mon - Fri
	if [ -n "${flag_daily+x}" ]; then
		# example: today/DP_Feb12.mov
		promo_regex="^${source_dir}/DP_${month_and_day}\.mov$"

		# store the output of find into a variable, so we don't have to run it twice
		find_output="$(find "${source_dir}/" ! -path "${source_dir}/" -prune -type f -name "*mov")"

		# make sure we only have 1 regex match (one file). otherwise, exit
		if [ $(printf '%s\n' "${find_output}" | grep -ciE ${promo_regex}) -eq 1 ]; then
			file_path_social="$(printf '%s\n' "${find_output}" | grep -iE $promo_regex)"

		elif [ $(printf '%s\n' "${find_output}" | grep -ciE ${promo_regex}) -eq 0 ]; then
			__print_err_and_exit "No promo found!"

		else
			__print_err_and_exit "Too many promos found! Make sure source dir has 1 only."
		fi
	fi

	# Sun
	if [ -n "${flag_sunday+x}" ]; then
		promo_regex_sun="^${source_dir_sun}/DP_${month_and_day_sun}\.mov$"

		find_output_sun="$(find "${source_dir_sun}/" ! -path "${source_dir_sun}/" -prune -type f -name "*mov")"

		if [ $(printf '%s\n' "${find_output_sun}" | grep -ciE ${promo_regex_sun}) -eq 1 ]; then
			file_path_social_sun="$(printf '%s\n' "${find_output_sun}" | grep -iE $promo_regex_sun)"

		elif [ $(printf '%s\n' "${find_output_sun}" | grep -ciE ${promo_regex_sun}) -eq 0 ]; then
			__print_err_and_exit "No Sunday promo found!"

		else
			__print_err_and_exit "Too many promos found! Make sure Sunday source dir has 1 only."
		fi
	fi

	return 0
}

# copy and encode the promo
promo_encode()
{
	# Mon - Fri
	if [ -n "${flag_daily+x}" ]; then
		new_name_social="program_promo_social_${full_date}.mov"
		printf '%s\n' "Filename is: ${new_name_social} !!!!!!"

		cp "${file_path_social}" "${work_dir}/${new_name_social}" && \
		./sk_encode.sh "${new_name_social}"
		[ $? -eq 0 ] || __print_err_and_exit "Encoding of $new_name_social failed"
	fi

	# Sun
	if [ -n "${flag_sunday+x}" ]; then
		new_name_social_sun="program_promo_social_${full_date_sun}.mov"
		printf '%s\n' "Filename is: ${new_name_social_sun} !!!!!!"

		cp "${file_path_social_sun}" "${work_dir}/${new_name_social_sun}" && \
		./sk_encode.sh "${new_name_social_sun}"
		[ $? -eq 0 ] || __print_err_and_exit "Encoding of $new_name_social_sun failed"
	fi

	return 0
}

# print (assumed successful) result of script
print_result()
{
	# Mon - Fri
	if [ -n "${flag_daily+x}" ]; then
		printf '%b%s%b%s%b\n' "$green" "Finished encoding and uploading: " "$yellow" "$new_name_social" "$reset_term"
	fi

	# Sun
	if [ -n "${flag_sunday+x}" ]; then
		printf '%b%s%b%s%b\n' "$green" "Finished encoding and uploading: " "$yellow" "$new_name_social_sun" "$reset_term"
	fi

	return 0
}

parse_args "$@" && \
check_cur_dir && \
check_weekday && \
set_date_variables && \
check_promo && \
promo_encode &&
print_result
