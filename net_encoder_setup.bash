#!/bin/bash

# used to recreate networking settings on fresh "DB10" install. Check MAC addresses before using

error()
{
	local msg="$1"
	printf '%b\n' "$(tput setaf 1)ERROR ${0##*/}:$(tput setaf 3) ${msg}$(tput sgr0)"
	exit 1
} >&2

success()
{
	local msg="$1"
	printf '%b\n' "$(tput setaf 2)SUCCESS ${0##*/}:$(tput setaf 3) ${msg}$(tput sgr0)"
}

check_root()
{
	[ $(id -u) -eq 0 ] || error "Must run as root!"
	return 0
}

check_device()
{
	local int="$1"
	declare dev typ state conn

	read -r dev typ state conn <<< $(nmcli device status | grep "$int")
	
	if [ "$state" != connected ]; then
		if ! nmcli device connect "$int"; then
			error "Failed to connect device $int"
		fi
	fi
	return 0
}

check_rt_num()
{
	local num=$1
	local rt_name=$2

	# sanity check
	if [ -z "${num:+x}" ] ||  [ -z "${rt_name:+x}" ]; then
		error "Function check_rt_num() requires 2 arguments!"
	fi

	if ! grep -qs ^"$num" /etc/iproute2/rt_tables; then
		if ! printf '%d\t%s\n' $num "$rt_name" >> /etc/iproute2/rt_tables; then
			error "Couldn't add $num to list of route tables!"
		fi
	fi
	return 0
}

# currently unused
check_ip_rule_num()
{
	local num=$1
	until ! grep -qs ^"${num}": <<< "$(ip rule show)"; do
		num=$((num+1))
	done
	return 0
}

# settings common to all interfaces
# takes array of network info as arg
config_general()
{
	data=("$@")

	int="${data[0]}"
	ip="${data[1]}"
	gw="${data[2]}"
	net="${data[3]}"

	rtable="${data[4]}"
	rt_name="${data[5]}"

	check_device "$int"
	return 0
}

config_lan()
{
	config_general "${lan[@]}"

	if nmcli connection mod "$int" \
	ipv4.method manual \
	ipv4.addresses "$ip" \
	ipv4.gateway "$gw" \
	ipv4.dns "$dns" \
	ipv4.never-default false \
	ipv4.may-fail false; then
		if ! nmcli device reapply "$int" &>/dev/null; then
			error "Problem with applying $int settings"
		fi
	else
		error "Unable to modify $int connection"
	fi

	success "Configured $int"
	return 0
}

config_dmz()
{
	config_general "${dmz[@]}"

	if nmcli connection mod "$int" \
	ipv4.method manual \
	ipv4.addresses "$ip" \
	ipv4.dns "$dns" \
	ipv4.never-default true \
	ipv4.route-table $rtable \
	ipv4.routes "0.0.0.0/1 $gw, 128.0.0.0/1 $gw" \
	ipv4.routing-rules \
	"priority $rtable from $ip lookup $rtable, \
	priority $((rtable+1)) to $net lookup $rtable" \
	ipv4.may-fail true; then
		if ! nmcli device reapply "$int" &>/dev/null; then
			error "Problem with applying $int settings"
		fi
	else
		error "Unable to modify $int connection"
	fi

	success "Configured $int"
	return 0
}

config_admin()
{
	config_general "${admin[@]}"

	if nmcli connection mod "$int" \
	ipv4.method manual \
	ipv4.addresses "$ip" \
	ipv4.dns "$dns" \
	ipv4.never-default true \
	ipv4.route-table $rtable \
	ipv4.routes "0.0.0.0/1 $gw, 128.0.0.0/1 $gw" \
	ipv4.routing-rules \
	"priority $rtable from $ip lookup $rtable, \
	priority $((rtable+1)) to $net lookup $rtable, \
	priority $((rtable+2)) to $vlan_idrac lookup $rtable, \
	priority $((rtable+3)) to $vlan_wifi lookup $rtable, \
	priority $((rtable+4)) to $vlan_gw lookup $rtable" \
	ipv4.may-fail true; then
		if ! nmcli device reapply "$int" &>/dev/null; then
			error "Problem with applying $int settings"
		fi
	else
		error "Unable to modify $int connection"
	fi

	success "Configured $int"
	return 0
}

# === interfaces ===
# interface static_ip gateway subnet (route_table_num route_table_name)?
lan=(enp2s0 SENSITIVE_IP SENSITIVE_IP SENSITIVE_IP)
dmz=(enp3s0 SENSITIVE_IP SENSITIVE_IP SENSITIVE_IP 200 dmz)
admin=(enp4s0 SENSITIVE_IP SENSITIVE_IP SENSITIVE_IP 69 admin)

# === destination vlan subnets ===
# connections to these will use admin interface's route table
vlan_idrac="SENSITIVE_IP"
vlan_wifi="SENSITIVE_IP"
vlan_gw="SENSITIVE_IP"

dns="8.8.8.8,8.8.4.4"

check_root && config_lan && config_dmz && config_admin && success "Network configured"
