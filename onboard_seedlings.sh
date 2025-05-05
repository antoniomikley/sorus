#!/usr/bin/env bash

wg_peers_dir="./wg-peers/"

get_available_ips() {
	local ip_addrs=$(cat $wg_peers_dir* 2>/dev/null | grep 'AllowedIPs' | sed 's/.*"\([^"]*\)".*/\1/' | sort -t . -k 1,1n -k 2,2n -k 3,3n -k 4,4n)

	for ip in 10.0.{0..1}.{0..255}; do
		if [[ $ip == "10.0.0.0" || $ip == "10.0.0.1" || $ip == "10.0.1.255" ]]; then
			continue
		fi
		if [[ ! " $ip_addrs " =~ [[:space:]]$ip[[:space:]] ]]; then
			echo $ip
			break
		fi
	done
}

# Get Wireguard public key
get_wg_pub_key() {
	local wg_pubkey=$(cat /etc/nixos/keys/wg_pubkey)
	echo $wg_pubkey
}

get_iface_info() {
	local extern_domain="nixos.org"		# should be always reachable to be able to update packages
	local extern_ip=$(getent ahosts $extern_domain | head -n 1 | cut -d ' ' -f 1)
	local iface_name=$(ip route get $extern_ip | grep -E -o 'dev [^ ]+' | sed 's/dev //')
	local iface_info=$(ip -json addr show dev $iface_name | jq ".[0]") 
	echo $iface_info
}

get_ipv6_addr() {
	local ip_v6=$(get_iface_info | jq '.addr_info.[] | select(.family=="inet6")' | jq -r .local)
	echo $ip_v6
}

get_ssh_host_keys() {
	local ip_v4_section=$(get_iface_info | jq '.addr_info.[] | select(.family=="inet")')
	local ip_v4_addr=$(echo $ip_v4_section | jq -r .local)
	local cidr=$(echo $ip_v4_section | jq -r .prefixlen)
	local net_addr=$(ipcalc -j "$ip_v4_addr/$cidr" | jq -r .NETWORK)/$cidr
	ssh-keyscan -q -t ed25519 $net_addr 2>/dev/null | grep -v $ip_v4_addr
}

get_ready_for_onboarding() {
	local wg_net=$(ssh-keyscan -q -t ed25519 10.0.0.0/24 2>/dev/null | cut -d ' ' -f 3)
	get_ssh_host_keys > /tmp/temptestfile
	for key in $wg_net; do
		local result=$(cat /tmp/temptestfile | grep -v -F $key)
		printf "$result\n" > /tmp/temptestfile

	done
	cat /tmp/temptestfile
	rm /tmp/temptestfile
}

# call with parameters $1 = ip v4 addr; $2 = ssh ed25519 host key
onboard_seedling() {
	local pw_hash='$y$j9T$8v6gPezp9Sla1WB/JCCYw0$Gk0U92WEg9fo5k5KXNZv.LNLGRhHuGFWeitm9OIWAn5'
	local onboarding_ip_v4=$1
	local wg_client_ip_v4=$(get_available_ips)
	local new_host_name=$(printf seedling-%03d $(echo "$wg_client_ip_v4" | echo "$(($(cut -d '.' -f 4) - 1))"))

	if [[ -z $new_host_name ]]; then
		echo "something went wrong"
		exit 1
	fi

	local wg_client_private_key=$(wg genkey)
	local wg_client_public_key=$(echo $wg_client_private_key | wg pubkey)
	local wg_server_pub_key=$(get_wg_pub_key)
	local wg_server_ip_v6=$(get_ipv6_addr)
	local age_key=$(echo "$1 ssh-ed25519 $2" | ssh-to-age)

	if [[ -z $age_key ]]; then
		echo "something went wrong 2 electric bogaloo"
		exit 1
	fi

	local onboarding_dir="/tmp/onboarding/$new_host_name"
	mkdir -p $onboarding_dir
	echo "tech_user_pw: $pw_hash" > $onboarding_dir/default_sops_unenc.yaml
	echo "wg_private_key: $wg_client_private_key" >> $onboarding_dir/default_sops_unenc.yaml
	sops encrypt --age $age_key $onboarding_dir/default_sops_unenc.yaml > $onboarding_dir/default_sops.yaml
	rm $onboarding_dir/default_sops_unenc.yaml

	cat ./templates/morph_deploy.nix | sed "s/\${onboarding_ip_v4}/$onboarding_ip_v4/" | sed "s/\${new_host_name}/$new_host_name/" | sed "s/\${wg_client_ip_v4}/$wg_client_ip_v4/" | sed "s/\${wg_server_ip_v6}/$wg_server_ip_v6/" | sed "s|\${wg_server_pub_key}|$wg_server_pub_key|" > $onboarding_dir/$new_host_name.nix 

	cat ./templates/wg_peers | sed "s|\${wg_client_public_key}|$wg_client_public_key|" | sed "s/\${wg_client_ip_v4}/$wg_client_ip_v4/" > $wg_peers_dir$new_host_name

	cp ./templates/hardware_config/qemu_kvm.nix $onboarding_dir/hardware-configuration.nix
	cp ./serf-agent-bin.nix $onboarding_dir/serf-agent-bin.nix

	echo "$new_host_name" >> /tmp/onboarding/ready_to_enroll
}

onboard_all() {
	mkdir /tmp/onboarding 2>/dev/null
	get_ready_for_onboarding | cut -d ' ' -f 1,3 > /tmp/onboarding/queue
	while read args; do
		onboard_seedling $args
	done < /tmp/onboarding/queue

	sudo nixos-rebuild -I nixos-config=./configuration.nix switch

	while read host_name; do
		SSH_USER=onboarding SSH_SKIP_HOST_KEY_CHECK=true morph deploy --upload-secrets /tmp/onboarding/$host_name/$host_name.nix switch &> /tmp/onboarding/$host_name/deploy.log
	done < /tmp/onboarding/ready_to_enroll
	rm /tmp/onboarding/ready_to_enroll
}

onboard_all
