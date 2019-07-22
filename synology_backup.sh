#!/bin/bash

# absolute paths for binaries
syno_bash="/bin/bash"
syno_find="/bin/find"
syno_xargs="/bin/xargs"
syno_basename="/bin/basename"
syno_rsync="/bin/rsync"
syno_mkdir="/bin/mkdir"

today_date="$(date +%F)"

# array of shares to be backed up
shares=("104" "222" "graphics" "scripts" "social_media" "104_Finished_Shows" "104_RawFtg" "104_RawFtg_DaysDick" "southafrica")

# common rsync arguments
rsync_args=(-vva --chmod=a+rwx --stats --exclude="#recycle" --exclude=".DS_Store" --exclude="@eaDir" --exclude="@tmp" --delete-after --backup --backup-dir="../../DELETED" --password-file="/var/services/homes/dillon/backup/.RsyncPassword")

for share in "${shares[@]}"
do
	# Example: /var/services/homes/dillon/backup/logs/graphics/2019/March
	log_dir="/var/services/homes/dillon/backup/logs/${share}/$(date +%Y)/$(date +%B)"

	# create the log directory structure tree
	"$syno_mkdir" -p "${log_dir}"

	# dynamically created log file variables for rsync calls. TODO: move rsync transfers into for loop, using associative arrays
	declare -r "logfile_${share}"="${log_dir}/${today_date}_${share}.log"
done
        
# 222
"$syno_rsync" "${rsync_args[@]}" --log-file="${logfile_222}" "/volume1/222/" "rsync://rsyncer@192.168.77.106/222Backup/"

# Scripts
"$syno_rsync" "${rsync_args[@]}" --log-file="${logfile_scripts}" "/volume1/Scripts/" "rsync://rsyncer@192.168.77.108/scriptsBackup/current/"

# Graphics
"$syno_rsync" "${rsync_args[@]}" --log-file="${logfile_graphics}" "/volume1/Graphics/" "rsync://rsyncer@192.168.77.108/graphicsBackup/current/"
 
# Social_Media
"$syno_rsync" "${rsync_args[@]}" --log-file="${logfile_social_media}" "/volume1/Social_Media/" "rsync://rsyncer@192.168.77.108/social_mediaBackup/current/"

# South Africa
"$syno_rsync" "${rsync_args[@]}" --log-file="${logfile_southafrica}" "/volume1/SOUTHAFRICA/" "rsync://rsyncer@192.168.77.108/southafrica/current/"

# 104 RawFtg_X/The Day's Dick
"$syno_rsync" "${rsync_args[@]}" --log-file="${logfile_104_RawFtg_DaysDick}" --filter="merge daysdick_filter" "/volume1/104/" "rsync://rsyncer@192.168.77.108/daysdickBackup/current/"

# 104 excluding Finished_Shows_X/FINSHOWS, RawFtg_X/RAWSHOWS,The Day's Dick
"$syno_rsync" "${rsync_args[@]}" --log-file="${logfile_104}" --filter="merge 104_filter" "/volume1/104/" "rsync://rsyncer@192.168.77.107/104Backup/104/"

# 104 Finished_Shows_X/FINSHOWS
"$syno_rsync" "${rsync_args[@]}" --log-file="${logfile_104_Finished_Shows}" --filter="merge finish_filter" "/volume1/104/Finished_Shows_X/" "rsync://rsyncer@192.168.77.105/RawFinBkup/finish/current/"

# 104 RawFtg_X/RAWSHOWS

# directory containing rawftg temp files
"$syno_mkdir" -p "/var/services/homes/dillon/backup/RawFtg_tempfiles"

# Example 1: /volume1/104/RawFtg_X/Mar23_2019
# Example 2: /volume1/104/RawFtg_X/Jan02_2018
regecks='^/volume1/104/RawFtg_X/([[:alpha:]]{3})[[:digit:]]{2}_([[:digit:]]{4})$'

# associative array used to store remote directories that we will create later
# key is remote_dir. value is temp file containing null-terminated files to transfer
declare -A "remote_dir_list"

# Loop through each line returned by find command
# IFS= ensures leading and trailing whitespace is included
while IFS= read -rd $'\0' dirr
do
	# use regex pattern to dynamically create a list of remote directories to create
	# the key of our associatiive array is the remote dir to create, the value is the temp. file containing null-terminated
	#+ files to transfer
	if [[ "$dirr" =~ $regecks ]]
	then
		month_match="${BASH_REMATCH[1]}"
		year_match="${BASH_REMATCH[2]}"
		remote_dir_list["${month_match}_${year_match}"]="/var/services/homes/dillon/backup/RawFtg_tempfiles/${month_match}_${year_match}.filelist"
		
		# populate list of files to transfer, null-terminated
		printf "%s"'\0' "$($syno_basename "$dirr")" 2>&1 >/dev/null >> "/var/services/homes/dillon/backup/RawFtg_tempfiles/${month_match}_${year_match}.filelist"
	fi
done < <("$syno_find" "/volume1/104/RawFtg_X/" -maxdepth 1 -type d -regextype 'posix-extended' -regex $regecks -print0)

# Example: 
# key:   May_2019 (remote dir)
# value: "/var/services/homes/dillon/backup/RawFtg_tempfiles/May_2019.filelist" (null-terminated list of files to transfer to remote directory [key]

# iterate over directories that we need to rsync
for remote_dir in "${!remote_dir_list[@]}"
do
	# rsync's --files-from option requires an explicit -r flag for recursive directory traversal
	"$syno_rsync" "${rsync_args[@]}" --log-file="${logfile_104_RawFtg}" -r --from0 --files-from="${remote_dir_list[$remote_dir]}" "/volume1/104/RawFtg_X/" "rsync://rsyncer@192.168.77.105/RawFinBkup/raw/current/${remote_dir}/"

	# check transfer status
	if [[ $? -eq 0 ]]
	then
		echo "== DELETING ${remote_dir_list[$remote_dir]} ==" >> "${logfile_104_RawFtg}"
		rm "${remote_dir_list[$remote_dir]}"

		# check rm file list status
		if [[ $? -eq 0 ]]
		then
			echo "== rm of ${remote_dir_list[$remote_dir]} COMPLETE ==" >> "${logfile_104_RawFtg}"
		else
			echo "== ERROR! SOMETHING WENT WRONG WITH DELETIION OF ${remote_dir_list[$remote_dir]} ==" >> "${logfile_104_RawFtg}"
		fi
	else
		echo "== ERROR! SOMETHING WENT WRONG WITH RSYNC TRANSFER OF $remote_dir ==" >> "${logfile_104_RawFtg}"
	fi

done
