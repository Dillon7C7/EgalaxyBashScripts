#!/bin/bash

session_work="work"			# session for workflow
session_ssh="servers"		# session for remote administration
#in_tmux=					# used to determine if we are currently in tmux
work_exists=				# used to determine if the work session already exists
admin_exists=				# used to determine if the admin session already exists

declare -a success_hosts	# array of pinged hosts that replied
declare -a failure_hosts	# array of pinged hosts that did not reply

# list of LAN hosts from /etc/hosts
host_list=("rawfinbackup" "222backup" "104backup" "miscbackup" "NakedFiles" "manilla")

# temporary log file
output_file="$(mktemp -p /tmp/ $$-$(basename "${0}").XXXXXXXX)"

#  print an error;
#+ $1 is the message
#+ $2 is the optional output file
print_error()
{
	# if $2 is a file and writable, append to it
	if [ -w "$2" ]; then
		echo "ERROR $(basename $0): $1" 1>&2 >> "$2"
	else
		echo "ERROR $(basename $0): $1" 1>&2
	fi
}

# create a work session
create_work_session() 
{
	# make sure the session doesn't already exist
	grep -Eq "^${session_work}: .+" <<< "$(tmux list-sessions)"
	
	# sucessfully grepped text, meaning the session already exists
	if [ $? -eq 0 ]; then
		print_error "Session ${session_work} init failed!" "$output_file" 1>&2 #>> "$output_file"
		work_exists="y"
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

	echo "Successfully created session ${session_work}" >> "$output_file"
	work_exists="n"

	return 0
}

# create an admin. session
create_admin_session()
{
	# make sure the session doesn't already exist
	grep -Eq "^${session_ssh}: .+" <<< "$(tmux list-sessions)"
	
	# sucessfully grepped text, meaning the session already exists
	if [ $? -eq 0 ]; then
		print_error "Session ${session_ssh} init failed!" 1>&2 >> "$output_file"
		admin_exists="y"
		return 1
	fi

	# start a new detached session
	tmux new-session -d -s "$session_ssh"

	# attempt to ssh into every local server
	for window in "${!host_list[@]}"; do
	
		# make sure host is up by sending an ICMP packet, ttl 1 second
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

	echo "Successfully created session ${session_ssh}" >> "$output_file"
	admin_exists="n"

	return 0
}

# for visibility
echo -e "\n######################################################\n" >> "$output_file"

create_work_session
create_admin_session

# if both sessions already exist, exit script abruptly
if [ "$work_exists" == "y" ] && [ "$admin_exists" == "y" ]; then
	print_error "Both sessions already exist!!" 1>&2 >> "$output_file"
	cat "$output_file" && rm -f "$output_file"
	exit 1
fi

# if the admin session didn't already exist, create output for result of ssh attempts
if [ "$admin_exists" != "y" ]; then

	# handle output for successful connections
	if [ $((${#success_hosts[@]})) -gt 0 ]; then
		echo "Successfully connected to the following hosts: ${success_hosts[*]} on session ${session_ssh}" >> "$output_file"
	
	# if all hosts are down (i.e. success array is empty), there likely is a LAN connection problem
	else 
		echo "All hosts are down! Perhaps check your LAN connection." >> "$output_file"
	fi

	# handle output for failed connections, if any
	if [ $((${#failure_hosts[@]})) -gt 0 ]; then
		echo "Could not connect to the following hosts: ${failure_hosts[*]}" >> "$output_file"
	
	# no failed ping attempts
	else
		echo "Completed without error!" >> "$output_file"
	fi
fi

# for visibility
echo -e "\n######################################################\n" >> "$output_file"

# send output_msg to bottom-left pane of window 0 of session "work", otherwise current tty
if [ "$work_exists" != "y" ]; then

	tmux send-keys -t "${session_work}:0.1" "cat '${output_file}'" ENTER
	tmux wait-for -S output_channel
	tmux send-keys -t "${session_work}:0.1" "rm -f '${output_file}'" ENTER
	tmux wait-for output_channel
else
	cat "${output_file}" && rm -f "$output_file"
fi

#  if not connected to a tmux server ($TMUX is unset or not null), attach to session
#+ otherwise, switch to session
if [ -z "${TMUX:+x}" ]; then
	tmux attach -t "${session_work}"
else
	tmux switch-client -t "${session_work}"
fi
