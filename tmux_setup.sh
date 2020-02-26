#!/bin/bash

basescript="${0##*/}"           # basename without calling basename

color_yell="$(tput setaf 3)"    # set terminal fg to yellow
term_reset="$(tput sgr0)"       # reset terminal attributes

session_work="encoder"          # session for workflow
session_ssh="servers"           # session for remote administration
work_existed=                   # used to determine if the work session already exists
admin_existed=                  # used to determine if the admin session already exists

declare -a success_hosts        # array of pinged hosts that replied
declare -a failure_hosts        # array of pinged hosts that did not reply

declare -a stdout_msg           # array of successful messages
declare -a stderr_msg           # array of error or failed messages

# list of LAN hosts from /etc/hosts
host_list=("NakedBackup" "NakedExtra" "NakedFiles" "ITAdmin" "manila")

#################### START OF FUNCTION DECLARATIONS ##################

# print arrays of successful messages and error messages
print_output()
{
	printf "%b\n" "${color_yell}######################################################${term_reset}"

	# set terminal fg to green
	tput setaf 2

	[[ ${#stdout_msg[@]} -ne 0 ]] && printf "%s\\n" "${stdout_msg[@]}" 2>&1

	# set terminal fg to red
	tput setaf 1

	[[ ${#stderr_msg[@]} -ne 0 ]] && printf "%s\\n" "${stderr_msg[@]}" >&2

	# reset terminal attributes
	tput sgr0

	printf "%b\n" "${color_yell}######################################################${term_reset}"
}

# create a work session
create_work_session() 
{
	# make sure the session doesn't already exist
	grep -Eq "^${session_work}: .+" <<< "$(tmux list-sessions &>/dev/null)"
	
	# sucessfully grepped text, meaning the session already exists
	if [ $? -eq 0 ]; then
		stderr_msg+=("Session ${session_work} init failed!")
		work_existed="y"
		return 1
	fi
	
	# start a new detached session
	tmux new-session -d -s "$session_work"

	# create a window with 4 evenly-distributed panes
	tmux rename-window -t "${session_work}:0.0" "daily"		# top-left	0.0
	tmux split-window -d -h -t "${session_work}:0.0"		# top-right	0.1
	tmux split-window -d -v -t "${session_work}:0.0"		# bot-left	0.2
	tmux split-window -d -v -t "${session_work}:0.2"		# bot-right	0.3

	# cd into today directory
	tmux send-keys -t "${session_work}:0.0" "cd '/home/encoder/w/today'" 'ENTER'

	stdout_msg+=("Successfully created session ${session_work}")
	work_existed="n"

	return 0
}

# create an admin session
create_admin_session()
{
	# make sure the session doesn't already exist
	grep -Eq "^${session_ssh}: .+" <<< "$(tmux list-sessions &>/dev/null)"
	
	# sucessfully grepped text, meaning the session already exists
	if [ $? -eq 0 ]; then
		stderr_msg+=("Session ${session_ssh} init failed!")
		admin_existed="y"
		return 1
	fi

	# start a new detached session
	tmux new-session -d -s "$session_ssh"

	# attempt to ssh into every local server
	for window in "${!host_list[@]}"; do
	
		# make sure host's ssh server is up by running the 'true' command remotely
		tput setaf 3
		printf "%s\\n" "Checking if ssh server is running on host ${host_list[${window}]}..."
		tput sgr0

		ssh -o 'ConnectTimeout=5' "${host_list[${window}]}" true &>/dev/null </dev/null
	
		# if the host is pingable, add hostname to a 'success' array
		if [ $? -eq 0 ]; then
			tput setaf 2
			printf "%s\\n" "ssh server is running on host ${host_list[${window}]}!"
			tput sgr0
			success_hosts+=("${host_list[${window}]}")
		# otherwise, add hostname to a 'failure' array and continue with next host
		else
			tput setaf 1
			printf "%s\\n" "ssh server is NOT running on host ${host_list[${window}]}!"
			tput sgr0
			failure_hosts+=("${host_list[${window}]}")
			continue
		fi
	
		# rename the first window; create all other windows
		if [ $window -eq 0 ]; then
			# rename automatically created window 0
			tmux rename-window -t "${session_ssh}:${window}" "${host_list[${window}]}"
		else
			# create window with the name of the host to be connected to
			tmux new-window -t "${session_ssh}:${window}" -n "${host_list[${window}]}"
		fi
	
		# connect to old manila with a compatible TERM value
		if [[ "${host_list[${window}]}" == "manila" ]]; then
			tmux send-keys -t "${session_ssh}:${window}" "TERM=screen ssh '${host_list[${window}]}'" 'ENTER'
		# enable X11 forwarding for this server
		elif [[ "${host_list[${window}]}" == "NakedBackup" ]]; then
			tmux send-keys -t "${session_ssh}:${window}" "ssh -X '${host_list[${window}]}'" 'ENTER'
		# send the ssh command to the tmux window
		else
			tmux send-keys -t "${session_ssh}:${window}" "ssh '${host_list[${window}]}'" 'ENTER'
		fi
	done

	# select the first window of the admin session
	tmux select-window -t "${session_ssh}:0"
	stdout_msg+=("Successfully created session ${session_ssh}")

	# if the admin session didn't already exist, generate output for results of ssh attempts

	# handle output for successful connections
	if [[ ${#success_hosts[@]} -gt 0 ]]; then
		stdout_msg+=("Successfully connected to the following hosts: ${success_hosts[*]} on session ${session_ssh}")
	
	# if all hosts are down (i.e. success array is empty), there likely is a LAN connection problem
	else 
		stderr_msg+=("All hosts are down! Perhaps check your LAN connection.")
	fi

	# handle output for failed connections, if any
	if [[ ${#failure_hosts[@]} -gt 0 ]]; then
		stderr_msg+=("Could not connect to the following hosts: ${failure_hosts[*]}")
	
	# no failed ping attempts
	else
		stdout_msg+=("Completed without error!")
	fi

	admin_existed="n"

	return 0
}

#################### END OF FUNCTION DECLARATIONS ####################

#################### Start of "main()" ###############################

create_work_session
create_admin_session

if [[ "$work_existed" == "y" ]]; then

	# if both sessions already exist, source output on current tty, then exit script abruptly
	if [[ "$admin_existed" == "y" ]]; then
		stderr_msg+=("Both tmux sessions already exist!!!!")
		print_output
		exit 1

	# source output on current tty
	else # [[ "$admin_existed" != "y" ]]
		print_output
	fi

#  send output msg to bottom-left pane of window 0 of session "encoder"
#+ if this script created it
#+ passing characters directly via tmux send-keys is tricky, so a temp file is created,
#+ print_output() is redirected into this file, and the cat output is sent to terminal
else # [[ "$work_existed" != "y" ]]

	output_file="$(mktemp "/tmp/${basescript%.*}-$$.XXXXXXXX")"
	trap 'rm -f "$output_file"' EXIT
	print_output &> "${output_file}"

	# print_output() manually by sending keys to tmux pane
	tmux send-keys -t "${session_work}:0.1" "cat '"${output_file}"'" 'ENTER'
	tmux wait-for -S output_channel
	tmux send-keys -t "${session_work}:0.1" "rm -f '"${output_file}"'" 'ENTER'
	tmux wait-for output_channel
fi

#  if not connected to a tmux server ($TMUX is unset or not null), attach to session
#+ otherwise, switch to session
if [[ -z "${TMUX:+x}" ]]; then
	tmux attach -t "${session_work}"
else
	tmux switch-client -t "${session_work}"
fi
