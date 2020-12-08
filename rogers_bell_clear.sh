#!/bin/sh

# removes the file that ensures the Rogers/Bell upload script can't run again

rogers_bell_file="/home/encoder/.cache/ROGERS_BELL.txt"
log_file="/home/encoder/.local/log/rogers_bell.bash.log"

rm_result="$(rm -vf "$rogers_bell_file" 2>&1)"

if [ -z "$rm_result" ]; then
	printf '%s\n' "$(date +%F) - NO FILE FOUND" >> "$log_file"
else
	printf '%s\n' "$(date +%F) - $rm_result" >> "$log_file"
fi

max_lines=2000
total_lines=$(wc -l "$log_file" | cut -d ' ' -f1)

# remove older lines in log file
if [ $total_lines -gt $max_lines ]; then
	lines_to_del=$((total_lines-max_lines))
	sed -i -e "1,${lines_to_del}d" "$log_file"
fi

return 0
