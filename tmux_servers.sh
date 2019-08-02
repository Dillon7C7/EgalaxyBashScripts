#!/bin/bash

session_work="work"			# session for workflow
session_ssh="servers"		# session for remote administration
in_tmux=					# used to determine if we are currently in tmux
send_output="current"		# used to determine where to send output, (focused terminal or tmux session)

declare -a success_hosts	# array of pinged hosts that replied
declare -a failure_hosts	# array of pinged hosts that did not reply
declare -a output_msg		# array of strings containing output of ssh attempts

# list of LAN hosts from /etc/hosts
host_list=("rawfinbackup" "222backup" "104backup" "miscbackup" "NakedFiles")

# function used to create a work session
create_work_session() 
{
	# make sure the session doesn't already exist
	grep -Eq "^${session_work}: .+" <<< "$(tmux list-sessions)"
	
	if [ $? -eq 0 ]; then
		#echo "ERROR: session ${session_work} already exists!" >&2
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
	tmux send-keys -t "${session_work}:0.0" 'cd /home/encoder/w/today' C-m

	return 0
}

# function used to create an admin. session
create_admin_session()
{
	# make sure the session doesn't already exist
	grep -Eq "^${session_ssh}: .+" <<< "$(tmux list-sessions)"
	
	if [ $? -eq 0 ]; then
		#echo "ERROR: session ${session_ssh} already exists!" >&2
		return 1
	fi

	# start a new detached session
	tmux new-session -d -s "$session_ssh"

	# attempt to ssh into every local server
	for window in "${!host_list[@]}"; do
	
		# make sure host is up by sending an ICMP packet, ttl 1 second
		ping -c1 -t1 "${host_list[$window]}" 2>&1 >/dev/null
	
		# if the host is pingable, add hostname to a 'success' array
		if [ $? -eq 0 ]; then
			success_hosts+=("${host_list[$window]}")
		# otherwise, add hostname to a 'failure' array and continue with next host
		else
			failure_hosts+=("${host_list[$window]}")
			continue
		fi
	
		# rename the first window; create all other windows
		if [ $window -eq 0 ]; then
			# rename automatically created window 0
			tmux rename-window -t "${session_ssh}:${window}" "${host_list[$window]}"
		else
			# create window with the name of the host to be connected to
			tmux new-window -t "${session_ssh}:${window}" -n "${host_list[$window]}"
		fi
	
		# send the ssh command to the tmux window
		tmux send-keys -t "${session_ssh}:${window}" "ssh '${host_list[$window]}'" ENTER
	done

	return 0
}

create_work_session
if [ $? -ne 0 ]; then
	output_msg+="ERROR: session ${session_work} init failed!\n"
	send_output="${session_work}"
else
	output_msg+="Successfully created session ${session_work}\n"
fi

create_admin_session
if [ $? -ne 0 ]; then
	output_msg+="ERROR: session ${session_ssh} init failed!\n"
#	# if create_work_session() failed, send output to ssh session
#	[ "$send_output" != "work" ] && send_output="${session_ssh}"
else
	output_msg+="Successfully created session ${session_ssh}\n"
fi

# handle output for successful connections
if [ $((${#success_hosts[@]})) -gt 0 ]; then
	output_msg+="Successfully connected to the following hosts: ${success_hosts[*]} on session ${session_work}\n"

# if all hosts are down (i.e. success array is empty), there likely is a LAN connection problem
else 
	output_msg+="All hosts are down! Perhaps check your LAN connection.\n"
fi

# handle output for failed connections
if [ $((${#failure_hosts[@]})) -gt 0 ]; then
	output_msg+="Could not connect to the following hosts: ${failure_hosts[*]}\n"
else
	output_msg+="Completed without error!\n"
fi

# send output_msg to bottom-left pane of window 0 of session "work", otherwise current tty
if [ "$send_output" == "${session_work}" ]; then
	tmux send-keys -t "${session_work}:0.1" "echo -en '${output_msg}'" ENTER
else
	echo -en "${output_msg}"
fi

# if not connected to a tmux server ($TMUX is unset), attach to session
# otherwise, switch to session
if [ -z "${TMUX+x}" ]; then
	tmux attach -t "${session_work}"
else
	tmux switch-client -t "${session_work}"
fi
