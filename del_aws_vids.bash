#!/bin/bash

red="$(tput setaf 1)"
green="$(tput setaf 2)"
yellow="$(tput setaf 3)"
orange="$(tput setaf 9)"
reset="$(tput sgr0)"

script="${0##*/}"

unset flag_dry


_print_usage()
{
	printf '%b\n' "${yellow}usage: ${script} [-h] [-d|--dryrun] SHOW_NUM$(tput sgr0)"
	printf '\n'
	printf '%s\n' "Delete .mov, .scc, and .mpg files from AWS S3 bucket"
	printf '\n'
	printf '%s\n' "positional arguments:"
	printf '%s\n' " SHOW_NUM        the show number of the files to delete"
	printf '\n'
	printf '%s\n' "optional arguments:"
	printf '%s\n' " -h, --help      show this help message and exit"
	printf '%s\n' " -d, --dryrun    perform a trial run with no changes made"
	exit 1
} >&2

_print_error()
{
	error_msg="$1"
	printf '%b\n' "${red}ERROR ${script}: ${yellow}${error_msg}${reset}"
	_print_usage
} >&2

_print_warn()
{
	warn_msg="$1"
	printf '%b\n' "${red}WARNING ${script}: ${yellow}${warn_msg}${reset}"
} >&2

_print_success()
{
	good_msg="$1"
	printf '%b\n' "${green}SUCCESS ${script}: ${orange}${good_msg}${reset}"
}

# pass in "$@"
parse_args()
{
	declare -a params

	while [[ $# -gt 0 ]]
	do
		[[ $1 == --*=* ]] && set -- "${1%%=*}" "${1#*=}" "${@:2}"
		case "$1" in
			-h|--help)
				_print_usage
				;;
			-d|--dryrun)
				flag_dry="y"
				;;
			--)
				params+=("${@:2}")
				break
				;;
			-*)
				_print_error "Unknown argument '$1' given"
				;;
			*)
				params+=("$1")
				;;
		esac
		shift 1
	done
	set -- "${params[@]}"

	if [[ $# -ne 1 ]]; then
		_print_error "Please provide positional argument: SHOW_NUM"
	elif [[ ! $1 =~ ^[0-9]{4}$ ]]; then
		_print_error "SHOW_NUM must be an integer > 1000"
	else 
		show_num=$1
	fi
}

aws_del()
{
	aws_bucket="nnencode"
	aws_input_dir="${aws_bucket}/input"
	aws_output_dir="${aws_bucket}/output"
	aws_common_args=(--recursive "--exclude="'*')
	aws_input_args=("--include=""NN_${show_num}.mov" "--include=""NN_${show_num}.scc" "s3://${aws_input_dir}/")
	aws_output_args=("--include=""*REDACTED*${show_num}*mpg" "--include=""NN_${show_num}h264.mov" "s3://${aws_output_dir}/")

	if [[ -n "${flag_dry+x}" ]]; then
		aws_common_args+=(--dryrun)
	fi

	if aws s3 rm "${aws_common_args[@]}" "${aws_input_args[@]}"; then
		_print_success "input files deleted"
	else
		_print_warn "input files not deleted"
	fi

	if aws s3 rm "${aws_common_args[@]}" "${aws_output_args[@]}"; then
		_print_success "output files deleted"
	else
		_print_warn "output files not deleted"
	fi
}


parse_args "$@" && aws_del
