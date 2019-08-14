#!/bin/bash

# Dynamic DNS /etc/hosts.allow IP updater. To be run as a cron job, as root.

#  $1: error message to output
#+ $2: optional non-zero exit code. default 1
print_error_and_exit()
{
	echo "ERROR $(basename $0): $1" >&2

	# use exit code of 1, otherwise use supplied exit code
	[ $# -eq 1 ] && exit 1 || exit $2
}

# tcp wrapper file to update
hosts_file='/etc/hosts.allow'

# /etc/hosts.allow is not writable except as root
[ -w "${hosts_file}" ] || print_error_and_exit "Must be run as root!"

# regex pattern for an IP address: aaa.bbb.ccc.ddd
ipaddr_regex='([0-9]{1,3}\.){3}[0-9]{1,3}'

# the ddns host to query
ddns_host='MY_HOSTNAME'

# attempt to resolve IP address from ${ddns_host}, and grep the IP address from answer
ddns_ip="$(grep -oE $ipaddr_regex$ < <(dig +noall +answer "${ddns_host}"))" || print_error_and_exit "DNS lookup failed"

current_ip="$(grep -oP "(?<=^sshd: )"$ipaddr_regex"(?= # ${ddns_host}$)" "${hosts_file}")" \
|| print_error_and_exit "IP not found in /etc/hosts.allow"

if [[ "${ddns_ip}" != "${current_ip}" ]]; then
	echo "IP has been changed! Updating /etc/hosts.allow..."
	sed -i -re "s/(^sshd: )${current_ip//./\\.}( # ${ddns_host//.\\.}$)/\1${ddns_ip//./\\.}\2/" "${hosts_file}"
	echo "Update of /etc/hosts.allow complete"
	echo "Old IP was: ${current_ip}; New IP is: ${ddns_ip}"
else
	echo "IP has not changed."
fi
