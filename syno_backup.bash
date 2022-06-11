#!/bin/bash

#  absolute paths for binaries; cron jobs seem to not work
#+ unless absolute paths for scripts and binaries are given
syno_bash="/bin/bash"
syno_find="/bin/find"
syno_xargs="/bin/xargs"
syno_mkdir="/bin/mkdir"
syno_rsync="/bin/rsync"

# script name
script_name="${0##*/}"

# lock directory and pid file
lock_dir="/tmp/${script_name}-lock"
pid_file="${lock_dir}/pid"

# date of day the script was run; also the name of the log file
today_date=$(date +%F)

# exit codes
ecode_success=0
ecode_fail=1
ecode_lockfail=2
ecode_recvsig=3

# array of shares to be backed up
unset -v shares

# successful and failed transfers are added to these arrays, respectively
unset -v rsync_success
unset -v rsync_fail

#  get length of array of args $@; no sanity checking!
#+ the exit code is the array length
len()
{
	local arr=("$@")	
	return "${#arr[@]}"
}

#  "return" left-justified text with length equal to hard-coded value
#+ $1 is the text; no check is made to see if length is > hard-coded value
ljustify()
{
	#  number of columns to ljustify text for logging;
	#+ hard-coded to be the length of the longest share name +1
	local ljust_spaces=13

	local ljust_text="$1"
	local ljust_text_len="${#ljust_text}"

	local added_spaces="$((ljust_spaces-ljust_text_len))"

	local count=0

	until [ $count -eq $added_spaces ]; do
		ljust_text+=" "
		count=$((count+1))
	done
	printf "${ljust_text}"
}

# removes all excluded file lines from log file $1
clean_log_files()
{
	sed -i '/.\+because of pattern .\+$/d' "$1"	2>/dev/null
}

# setup traps and locking for the script
locking()
{
	# lock successful
	if "$syno_mkdir" "${lock_dir}" &>/dev/null; then

		# setup EXIT trap before creating pid file, in case it fails
		trap 'ecode=$?; cleanup "got_lock" ${ecode}; echo "Exit code: ${ecode}"' EXIT

		echo $$ > "${pid_file}"
		trap 'echo "Signal triggered exit!" >&2; exit $ecode_recvsig' HUP INT QUIT TERM

		echo "Lock successful! PID: $$"
		return $ecode_success
	else

		trap 'ecode=$?; cleanup "not_lock" ${ecode}; echo "Exit code: ${ecode}"' EXIT
		trap 'echo "Signal triggered exit!" >&2; exit $ecode_recvsig' HUP INT QUIT TERM

		local otherPID=$(< "${pid_file}")
		local pid_ecode=$?

		#  if the PID in the pid_file was unable to be read,
		#+ then the other process is likely in the process of removing the lock,
		#+ and thus is still running
		if [ $pid_ecode -ne $ecode_success ]; then
			echo "Process ${otherPID} is still running! (Likely in the process of cleaning up)" >&2
			exit $ecode_lockfail
		else
			#  if the process with PID read from pid_file is unkillable,
			#+ then assume the lock is stale; restart the script
			if ! kill -0 ${otherPID} &>/dev/null; then

				echo "Stale lock! PID ${otherPID}!" >&2
				rm -rf "${lock_dir}"

				echo "[${script_name}] Restarting..." >&2
				exec "$0" "$@"
				
			#  if the process with PID read from pid_file is killable,
			#+ then that process is running. Lock failed.
			else
				echo "Process ${otherPID} is still running!" >&2
				exit $ecode_lockfail
			fi
		fi
	fi
}

# the actual backup
backup()
{
	# trap for backup()
	trap 'ecode=$?; cleanup "backup" ${ecode};' EXIT
	
	# backup directory on NAS containing rsync filter files, logs, and scripts
	backup_dir="PRIV_BACKUP_DIR/logs"

	# array of shares to be backed up
	shares=("104" "222" "Graphics" "Scripts" "Social_Media" "SOUTHAFRICA")
	
	# common rsync arguments
	rsync_args=(-vvai --stats --exclude="#recycle" --exclude=".DS_Store" --exclude="@eaDir" --exclude="@tmp" --delete-after --backup --backup-dir="../../DELETED" --password-file="PRIV_BACKUP_DIR/.RsyncPassword")
	
	# successful and failed transfers are added to these arrays, respectively
	rsync_success=()
	rsync_fail=()
	
	# used to get the exit code of the rsync transfers
	unset -v rsync_ecode

	# backup start time, before rsync transfers
	backup_start_time="$(date +'%F, %R')"
	
	for share in "${shares[@]}"
	do
		# example (with log file): /home/rsyncer/backup/logs/Graphics/2019/March/2019-03-25
		log_dir="${backup_dir}/${share}/$(date +'%Y/%B')"
		log_file="${log_dir}/${today_date}"
	
		# create the log directory tree
		"$syno_mkdir" -p "${log_dir}"

		# the actual backup
		"${syno_rsync}" "${rsync_args[@]}" --log-file="${log_file}" "/volume1/${share}/" "rsync://rsyncer@THIS_HOST/${share}/current/"
		local rsync_ecode=$?
		
		# log results for post-backup email
		if [ $rsync_ecode -eq $ecode_success ]; then
			rsync_success+=("${share}")
			clean_log_files "${log_file}"
		else
			ljust_share="$(ljustify "${share}")"
			rsync_fail+=("${ljust_share}: RSYNC EXIT CODE: $rsync_ecode")
		fi
	done

	exit $ecode_success
}

#  generate a backup email
#+ $1 is an exit code to be included in body
generate_rsync_email()
{
	ecode="$1"

	len "${shares[@]}"
	len_shares=$?

	len "${rsync_success[@]}"
	len_success=$?

	len "${rsync_fail[@]}"
	len_fail=$?

	#  make sure that every share was accounted for, and added to an array
	#+ we can check this by making sure the lengths of arrays containing
	#+ both successful and failed transfers is equal to the number of shares
	if [[ $((len_success+len_fail)) -eq $len_shares ]]; then

		# all transfers completed successfully
		if [[ $len_success -eq $len_shares ]]; then

			#  change subject depending on exit code only if all transfers completed successfully
			#+ otherwise, just include exit code in email subject
			case "$ecode" in
				$ecode_success) subject="${subject_prefix} SUCCESS[${ecode}]: All share backups completed." ;;
				$ecode_recvsig) subject="${subject_prefix} WARN[${ecode}]: All share backups completed, but a signal was caught." ;;
				*) subject="${subject_prefix} WARN[${ecode}]: All share backups completed, but got an unexpected exit code." ;;
			esac
				
			IFS= read -r -d $'\0' body <<- EMAIL_BODY_EOF || true
				Backup start time: ${backup_start_time}

				All transfers completed successfully. List below:

				$(printf "%s\\n" "${rsync_success[@]}")
			EMAIL_BODY_EOF

		# no transfers completed! check network/services!
		elif [[ $len_success -eq $ecode_success ]]; then

			subject="${subject_prefix} FAILURE[${ecode}]: All share backups failed!"

			IFS= read -r -d $'\0' body <<- EMAIL_BODY_EOF || true
				Backup start time: ${backup_start_time}

				All transfers FAILED! Here is list of them, with rsync exit codes:

				$(printf "%s\\n" "${rsync_fail[@]}")
			EMAIL_BODY_EOF

		# only some transfers completed successfully
		else # if [[ $len_success -ne $len_shares ]]; then

			subject="${subject_prefix} FAILURE[${ecode}]: Only some backups completed successfully!"

			IFS= read -r -d $'\0' body <<- EMAIL_BODY_EOF || true
				Backup start time: ${backup_start_time}

				Some transfers completed. Here is a list of successful transfers:

				$(printf "%s\\n" "${rsync_success[@]}")

				Here is a list of failed transfers with rsync exit codes:

				$(printf "%s\\n" "${rsync_fail[@]}")
			EMAIL_BODY_EOF
		fi

	# not all shares were accounted for
	else
		subject="${subject_prefix} CAUTION[${ecode}]: Not all share transfers were accounted for!"

		# change the email body based on if success/fail arrays are empty
		if [ $len_success -eq 0 ]; then

			IFS= read -r -d $'\0' body <<- EMAIL_BODY_EOF || true
				Backup start time: ${backup_start_time}

				It appears that not all shares were accounted for.

				No transfers completed successfully.

				Here is a list of failed transfers with rsync exit codes:

				$(printf "%s\\n" "${rsync_fail[@]}")
			EMAIL_BODY_EOF

		elif [ $len_fail -eq 0 ]; then

			IFS= read -r -d $'\0' body <<- EMAIL_BODY_EOF || true
				Backup start time: ${backup_start_time}

				It appears that not all shares were accounted for.

				Here is a list of successful transfers:

				$(printf "%s\\n" "${rsync_success[@]}")

				Surprisinly, no transfers failed.
			EMAIL_BODY_EOF

		else
			IFS= read -r -d $'\0' body <<- EMAIL_BODY_EOF || true
				Backup start time: ${backup_start_time}

				It appears that not all shares were accounted for.

				List of successful transfers:

				$(printf "%s\\n" "${rsync_success[@]}")

				List of failed transfers with rsync exit codes:

				$(printf "%s\\n" "${rsync_fail[@]}")
			EMAIL_BODY_EOF
		fi
	fi
}

#  generate the final email message
generate_final_email()
{
	# RFC 2822/5322 format
	date_header="$(date -R)"	

	# if ${body} is set and not null, include it in final email
	if [[ -n "${body:+x}" ]]; then
		IFS= read -r -d $'\0' message <<- FINAL_MAIL_HEREDOC || true
			From: FROM_EMAIL
			To: TO_EMAIL
			Subject: ${subject}
			Date: ${date_header}
			MIME-Version: 1.0
			Content-Type: text/plain; charset=utf8; format=flowed
			Content-Transfer-Encoding: 7bit
			Content-Language: en-US

			${body}
		FINAL_MAIL_HEREDOC

	# otherwise, no body
	else
		IFS= read -r -d $'\0' message <<- FINAL_MAIL_HEREDOC || true
			From: FROM_EMAIL
			To: TO_EMAIL
			Subject: ${subject}
			Date: ${date_header}
			MIME-Version: 1.0
			Content-Type: text/plain; charset=utf8; format=flowed
			Content-Transfer-Encoding: 7bit
			Content-Language: en-US
		FINAL_MAIL_HEREDOC
	fi
}

# pipe the email message over ssh and to a remote email script, since that machine can send OAUTH2 mail
send_email()
{
	printf "%s\\n" "${message}" | ssh -T -p PORT REMOTE_HOST@REMOTE_IP bash -c 'cat - | w/send_msmtp.bash EMAIL_ACCOUNT'
	ecode=$?

	# if ssh connection, or sending of the email failed, create a file in the backup directory
	if [ $ecode -ne 0 ]; then
		failed_to_notify_dir="${backup_dir}/failed_notifications"
		"$syno_mkdir" -p "${failed_to_notify_dir}"
		printf "%s\\n" "Couldn't send the notification email! Exit code: $ecode" > "${failed_to_notify_dir}/${today_date}"
	fi
}

#  $1 is the function from which cleanup() was called
#+ when func is locking, use got_lock for successful lock,
#+ and not_lock for a failed lock
#+ $2 is an exit code
cleanup()
{
	func="$1"
	ecode="$2"

	# time of backup completion
	backup_end_time=$(date +'%F, %R')

	# subject prefix for email
	subject_prefix="[${script_name}] - (${backup_end_time}) -"

	# set if/when email needs a body (backup())
	unset -v body

	# action based on calling function
	case "${func}" in
	##	main)
		#  script should not exit here
		#+ if it does: send an email with the exit code (point out if a signal was caught), and remove the lock directory
		got_lock)
			case "${ecode}" in
				$ecode_recvsig) subject="${subject_prefix} ERROR[${ecode}]: locking() exited with a signal." ;;
				*) subject="${subject_prefix} FATAL[${ecode}]: locking() exited with an unexpected exit code. Investigate further." ;;
			esac
			generate_final_email
			send_email
			rm -rf "${lock_dir}" ;;

		#  script should only exit here if locking failed
		#+ if lock exists: send an email with the exit code (point out if a signal was caught, or if locking failed)
		not_lock)
			case "${ecode}" in
				$ecode_lockfail) subject="${subject_prefix} WARN[${ecode}]: failed to get a lock; backup won't run tonight." ;;
				$ecode_recvsig) subject="${subject_prefix} ERROR[${ecode}]: locking() exited with a signal." ;;
				*) subject="${subject_prefix} FATAL[${ecode}]: locking() exited with an unexpected exit code. Investigate further." ;;
				esac
				generate_final_email
				send_email ;;

		# include exit code, but handle (email subject) in generate_rsync_email()
		backup)
			# generate email describing backup result
			generate_rsync_email "${ecode}"
			generate_final_email
			send_email
			rm -rf "${lock_dir}"; ;;

		# this condition shouldn't ever execute; included for clarity
		*) 
			subject="${subject_prefix} ERROR[${ecode}]: [BUG]: An invalid function was called."
			generate_final_email
			send_email ;;
	esac
}

locking && backup
