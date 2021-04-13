#!/bin/bash

# remove DELETED files older than 20 days

share_list=("104" "222" "Graphics" "Scripts" "Social_Media" "SOUTHAFRICA")
log_dir="/var/log/cron_logs/raid_DELETED/$(date +'%Y/%B/%F')"

for share in "${share_list[@]}"; do
	
	# create log directory
	mkdir -p "${log_dir}"

	find "/raid/${share}/DELETED/" -mindepth 1 -mtime +20 -exec rm -rvf '{}' + 2>&1 > "${log_dir}/${share}"
done
