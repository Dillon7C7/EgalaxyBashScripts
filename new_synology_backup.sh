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

# rsync arguments for raw footage and finished shows. we don't want --delete-after, --backup, or --backup-dir
rawfin_rsync_args=(-vva --chmod=a+rwx --stats --exclude="#recycle" --exclude=".DS_Store" --exclude="@eaDir" --exclude="@tmp" --password-file="/var/services/homes/dillon/backup/.RsyncPassword")

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
"$syno_rsync" "${rawfin_rsync_args[@]}" --log-file="${logfile_104_Finished_Shows}" --filter="merge finish_filter" "/volume1/104/Finished_Shows_X/" "rsync://rsyncer@192.168.77.105/RawFinBkup/finish/current/"

# 104 RawFtg_X/RAWSHOWS
"$syno_rsync" "${rawfin_rsync_args[@]}" --log-file="${logfile_104_RawFtg}" --filter="merge raw_filter" "/volume1/104/RawFtg_X/" "rsync://rsyncer@192.168.77.105/RawFinBkup/raw/current/"
