#!/bin/bash

# script used to back up select directories on select servers

# prior to use, make sure to:
#  add server and ssh port to $server_list
#  on remote server(s):
#    install rsync if not already installed
#    useradd rsyncbackup
#    add /root/.ssh/bkup_rsa.pub ssh key to /home/rsyncbackup/.ssh/authorized_keys
#    edit /etc/sudoers: allow rsyncbackup to run /usr/bin/rsync as root
#    edit sshd_config and allow rsyncbackup to connect from IP of this server

# hostname:ssh port mapping
declare -A server_list
server_list[encoder]=22222
server_list[NakedBackup]=22222
server_list[REDACTED_HOST]=22223

remote_dirs_raw=(/home /etc)

declare -a remote_dirs
# prepend ':' to all dirs, to satisfy rsync syntax
for ele in "${remote_dirs_raw[@]}"; do
	remote_dirs+=(:"$ele")
done

date_string=$(date +'%Y/%B %F') # we make only one call to `date`

# month_day dir for both logs and deleted files
# today for name of log file, and name of dir for deleted files
read -r month_day today <<< "$date_string"

script_name="${0##*/}"
lock_dir="/tmp/${script_name}-$$"
pid_file="${lock_dir}/pid"

e_success=0
#e_error=1
e_recvsig=2
e_lockfail=3

declare -a success_bkups
declare -a failed_bkups

backup_parent=/raid/servers
log_parent=/var/log/rsync_backups
script_log="${log_parent}/script_results/${month_day}/${today}"

# won't preserve extended attributes
rsync_opts=(-vvaixHAS --exclude '*.mov' --exclude '*.mp4' --exclude '*.mpg' --stats --numeric-ids --delete-after --info=progress2 --backup)

check_root()
{
	if [ $(id -u) -eq 0 ]; then

		#  we create script log before locking,
		## in order to log potential lock failure
		## mkdir here, so redirections to file work later
		mkdir -p "${log_parent}/script_results/${month_day}"

		return $e_success
	else
		exit 1
	fi
}

locking()
{
	trap 'ecode=$?; cleanup $ecode;' EXIT

	if mkdir "$lock_dir" &>/dev/null; then

		echo $$ > "$pid_file"
		trap 'exit $e_recvsig;' HUP INT QUIT TERM

		return $e_success
	else
		trap 'exit $e_recvsig' HUP INT QUIT TERM

		otherPID=$(< "$pid_file")
		pid_ecode=$?

		if [ $pid_ecode -ne 0 ]; then
			exit $e_lockfail # other process is probably removing lock

		elif ! kill -0 $otherPID &>/dev/null; then
			rm -rf "$lock_dir" # stale lock
			exec "$0" "$@"    # restart script
		else
			exit $e_lockfail #other process is still running
		fi
	fi
}

backup()
{
	for server in "${!server_list[@]}"; do
	
		# e.g. /raid/servers/encoder/current
		backup_dir="${backup_parent}/${server}/current"
	
		# e.g. /raid/servers/encoder/DELETED/2020/September/2020-09-18
		deleted_dir="${backup_parent}/${server}/DELETED/${month_day}/${today}"
	
		# e.g. /var/log/rsync_backups/servers/encoder/2020/September/2020-09-18
		log_dir="${log_parent}/servers/${server}/${month_day}"
		log_file="${log_dir}/${today}"
	
		mkdir -p "$backup_dir" # needed if a new server is to be backed up
		mkdir -p "$log_dir"    # required so --log-file argument of rsync doesn't fail
	
		rsync_ssh_opt="ssh -o ConnectTimeout=10s -l rsyncbackup -p ${server_list[$server]} -i /root/.ssh/bkup_rsa"
		rsync ${rsync_opts[@]} --rsync-path='sudo rsync' -e "$rsync_ssh_opt" --backup-dir="${deleted_dir}" --log-file="${log_file}" "${server}${remote_dirs[@]}" "$backup_dir" &>/dev/null
	
		rsync_ecode=$?
		if [ $rsync_ecode -eq 0 ]; then
			success_bkups+=("Server '${server}' success")
		else
			failed_bkups+=("Server '${server}' FAILED - Exit Code: $rsync_ecode")
		fi

	done
	_log_results

	#return $e_success
}

# create script log file here
_log_results()
{

	printf '%s\n\n' "Backup finished at $(date +%c)" >> "$script_log"

	if [ ${#success_bkups[@]} -gt 0 ]; then
		printf '%s\n' "The following servers backed up:" "${success_bkups[@]}" >> "$script_log"
		printf '%s\n' "--------------------------------------------------------" >> "$script_log"
	fi


	if [ ${#failed_bkups[@]} -gt 0 ]; then
		printf '%s\n' "The following servers failed to back up:" "${failed_bkups[@]}" >> "$script_log"
		printf '%s\n' "--------------------------------------------------------" >> "$script_log"
	fi

}

# $1 is an exit code passed from EXIT trap
cleanup()
{
	local final_ecode=$1	

	case $final_ecode in
		# just remove lock dir on successful run
		$e_success)
			rm -rf "$lock_dir"
		;;
		# append notification of caught signal and remove lock dir
		$e_recvsig)
			printf '\n%s\n%s\n' "--------------------------------------------------------" "A signal was caught; $script_name exited abruptly!" >> "$script_log"
			rm -rf "$lock_dir"
		;;
		# lock was not obtained, script will just exit
		$e_lockfail) printf '%s\n' "Lock failed. Backup was NOT run." >> "$script_log"
		;;
		# shouldn't ever get here...
		*)
			printf '%s\n' "Unexpected exit code ${final_ecode}." >> "$script_log"
			rm -rf "$lock_dir"
		;;
	esac

	# clean up deleted files older than 30 days
	printf '%s\n\n' "-------Deleting old deleted files (listed below)--------" >> "$script_log"
	while IFS= read -r -d $'\0' delete; do
		rm -rfv "$delete" >> "$script_log"
	done < <(find "${backup_parent}/${server_list[@]}/DELETED" -mindepth 2 -mtime +30 -print0)
	printf '%s\n'   "--------------------------------------------------------" >> "$script_log"

	# clean up logs older than 60 days
	printf '%s\n\n' "------------Deleting old logs (listed below)------------" >> "$script_log"
	while IFS= read -r -d $'\0' old_log; do
		rm -rfv "$old_log" >> "$script_log"
	done < <(find "$log_parent" -mtime +60 -print0)
	printf '%s\n'   "--------------------------------------------------------" >> "$script_log"
}

check_root && locking && backup
