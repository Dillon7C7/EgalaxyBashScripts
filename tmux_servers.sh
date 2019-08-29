#!/bin/bash

session_work="encoder"		# session for workflow
session_ssh="servers"		# session for remote administration
work_existed=				# used to determine if the work session already exists
admin_existed=				# used to determine if the admin session already exists

declare -a success_hosts	# array of pinged hosts that replied
declare -a failure_hosts	# array of pinged hosts that did not reply

# list of LAN hosts from /etc/hosts
host_list=("rawfinbackup" "222backup" "104backup" "miscbackup" "NakedFiles" "manilla")

# temporary log file that will contain echo commands to source
output_file="$(mktemp -p /tmp/ $$-"$(basename "${0%.sh}")".XXXXXXXX)"

#################### START OF FUNCTION DECLARATIONS ##################

# redirect 'echo $1' stdout to $output_file, which will be sourced
print_stdout()
{
	echo 'echo '"$1" >> "$output_file"
}

# redirect 'echo $1' stderr to $output_file, which will be sourced
print_stderr()
{
	echo 'echo '"ERROR $(basename $0): $1"' 1>&2' >> "$output_file"
}

# create a work session
create_work_session() 
{
	# make sure the session doesn't already exist
	grep -Eq "^${session_work}: .+" <<< "$(tmux list-sessions)"
	
	# sucessfully grepped text, meaning the session already exists
	if [ $? -eq 0 ]; then
		print_stderr "Session ${session_work} init failed!"
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
	tmux send-keys -t "${session_work}:0.0" 'cd /home/encoder/w/today' ENTER

	print_stdout "Successfully created session ${session_work}"
	work_existed="n"

	return 0
}

# create an admin. session
create_admin_session()
{
	# make sure the session doesn't already exist
	grep -Eq "^${session_ssh}: .+" <<< "$(tmux list-sessions)"
	
	# sucessfully grepped text, meaning the session already exists
	if [ $? -eq 0 ]; then
		print_stderr "Session ${session_ssh} init failed!"
		admin_existed="y"
		return 1
	fi

	# start a new detached session
	tmux new-session -d -s "$session_ssh"

	# attempt to ssh into every local server
	for window in "${!host_list[@]}"; do
	
		# make sure host is up by sending an ICMP packet, ttl 2 seconds
		ping -c1 -t2 "${host_list[${window}]}" 2>&1 >/dev/null
	
		# if the host is pingable, add hostname to a 'success' array
		if [ $? -eq 0 ]; then
			success_hosts+=("${host_list[${window}]}")
		# otherwise, add hostname to a 'failure' array and continue with next host
		else
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
	
		# send the ssh command to the tmux window
		tmux send-keys -t "${session_ssh}:${window}" "ssh '${host_list[${window}]}'" ENTER
	done

	print_stdout "Successfully created session ${session_ssh}"

	# if the admin session didn't already exist, generate output for results of ssh attempts

	# handle output for successful connections
	if [[ $((${#success_hosts[@]})) -gt 0 ]]; then
		print_stdout "Successfully connected to the following hosts: ${success_hosts[*]} on session ${session_ssh}"
	
	# if all hosts are down (i.e. success array is empty), there likely is a LAN connection problem
	else 
		print_stderr "All hosts are down! Perhaps check your LAN connection."
	fi

	# handle output for failed connections, if any
	if [[ $((${#failure_hosts[@]})) -gt 0 ]]; then
		print_stderr "Could not connect to the following hosts: ${failure_hosts[*]}"
	
	# no failed ping attempts
	else
		print_stdout "Completed without error!"
	fi

	admin_existed="n"

	return 0
}

# source $output_file and rm it
source_and_rm()
{
	# for visibility
	echo 'echo -e "\n######################################################\n" 2>&1' >> "$output_file"
	source "$output_file" && rm -f "$output_file"
}

#################### END OF FUNCTION DECLARATIONS ####################

#################### Start of "main()" ###############################

# for visibility
echo 'echo -e "\n######################################################\n" 2>&1' >> "$output_file"

create_work_session
create_admin_session

if [[ "$work_existed" == "y" ]]; then

	# if both sessions already exist, source output on current tty, then exit script abruptly
	if [[ "$admin_existed" == "y" ]]; then
		print_stderr "Both sessions already exist!!"
		source_and_rm
		exit 1

	# source output on current tty
	else # [[ "$admin_existed" != "y" ]]
		source_and_rm
	fi

#  send output_msg to bottom-left pane of window 0 of session "encoder"
#+ if this script created it
else # [[ "$work_existed" != "y" ]]

	# for visibility
	echo 'echo -e "\n######################################################\n" 2>&1' >> "$output_file"

	# source_and_rm() manually by sending keys to tmux pane
	tmux send-keys -t "${session_work}:0.1" "source '${output_file}'" ENTER
	tmux wait-for -S output_channel
	tmux send-keys -t "${session_work}:0.1" "rm -f '${output_file}'" ENTER
	tmux wait-for output_channel
fi

#  if not connected to a tmux server ($TMUX is unset or not null), attach to session
#+ otherwise, switch to session
if [[ -z "${TMUX:+x}" ]]; then
	tmux attach -t "${session_work}"
else
	tmux switch-client -t "${session_work}"
fi
