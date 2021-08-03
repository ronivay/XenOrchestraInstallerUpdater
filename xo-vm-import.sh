#!/bin/bash

#########################################################################
# Title: XenOrchestraInstallerUpdater                                   #
# Author: Roni Väyrynen                                                 #
# Repository: https://github.com/ronivay/XenOrchestraInstallerUpdater   #
#########################################################################

# image url is static and not configurable by user
IMAGE_URL="https://xo-image.yawn.fi/downloads/image.xva.gz"

function OSCheck {
	set -e

	if [[ -z $(command -v xe 2>/dev/null) ]]; then
                echo "this scripts needs xe command. make sure you're on xenserver/xcp-ng host"
                exit 1
        fi

	echo
	echo "Welcome. This script will import a preinstalled Debian 10 VM image which has Xen Orchestra installed using https://github.com/ronivay/XenOrchestraInstallerUpdater"
	echo "You need at least 2vCPU/4GB/10GB disk free resources to import VM"
	echo
	echo "Please report any issues to this github project"
	echo


}

function NetworkChoose {

	set +e

	# get network name/uuid of all available networks configured in the pool
	# shellcheck disable=SC1117
	IFS=$'\n' read -r -d '' -a networks <<< "$(xe network-list | grep "uuid\|name-label" | cut -d':' -f2 | sed 's/^ //' | paste - -)"

	echo
	echo "Which network should the VM use?"
	echo
	local PS3="Pick a number. CTRL+C to exit: "
	select network in "${networks[@]}"
	do
		# get only the network uuid from array which we need later on when adding vif
		read -r -a network_split <<< "$network"
		networkuuid=${network_split[0]}

		# print a menu where to choose network from
		case $network in
			*)
			# save network uuid for later
			vifuuid="$networkuuid"
			break
			;;
		esac
	done

}

function StorageChoose {

	set +e

	# get storage name/uuid of all available storages with content-type=user which should match all usable storage repositories
	# shellcheck disable=SC1117
	IFS=$'\n' read -r -d '' -a storages <<< "$(xe sr-list content-type=user | grep "uuid\|name-description" | cut -d':' -f2 | sed 's/^ //' | paste - -)"

	# bail out if no storage repositories are found
	if [[ ${#storages[@]} -eq 0 ]]; then
		echo "No storage repositories found, can't import VM"
		echo "Create SR and try again. More information: https://xcp-ng.org/docs/storage.html"
		exit 1
	fi

	echo "Which storage repository should the VM use?"
	echo "default will attempt to use pool default SR"
	echo
	local PS3="Pick a number. CTRL+C to exit: "
	select storage in "${storages[@]}" "default"
	do
		# get only the storage repository uuid which we need later on when importing image
		read -r	-a storage_split <<< "$storage"
		storageuuid=${storage_split[0]}

		# print a menu where to choose storage from
		case $storage in
			default)
			# this value is handled during import if set to default
			sruuid=default
			break
			;;
			*)
			# save storage uuid for later
			sruuid=$storageuuid
			break
			;;
		esac
	done

}

function NetworkSettings {

	set -e

	ipregex="^[0-9]{1,3}.[0-9]{1,3}.[0-9]{1,3}.[0-9]{1,3}$"

	echo
	echo "Set network settings for VM. Leave IP-address as blank to use DHCP"
	echo

	# read ip address from user input. dhcp is default if left empty
	read -r -p "IP address: " ipaddress
	ipaddress=${ipaddress:-dhcp}

	# if not using dhcp, we need more information
	if [[ "$ipaddress" != "dhcp" ]]; then
		# get network details from user and prompt again if input doesn't match ip address regex
		while ! [[ $ipaddress =~ $ipregex ]]; do
			echo "Check IP address format"
			read -r -p "IP address: " ipaddress
		done
		read -r -p "Netmask [255.255.255.0]: " netmask
		netmask=${netmask:-255.255.255.0}
		while ! [[ $netmask =~ $ipregex ]]; do
			echo "Check gateway format"
			read -r -p "Netmask [255.255.255.0]: " netmask
			netmask=${netmask:-255.255.255.0}
		done
		read -r -p "Gateway: " gateway
		while ! [[ $gateway =~ $ipregex ]] && [[ $gateway != "" ]]; do
			echo "Check gateway format"
			read -r -p "Gateway: " gateway
		done
		read -r -p "DNS [8.8.8.8]: " dns
		dns=${dns:-8.8.8.8}
		while ! [[ $dns =~ $ipregex ]]; do
			echo "Check dns format"
			read -r -p "DNS [8.8.8.8]: " dns
			dns=${dns:-8.8.8.8}
		done

	fi

}

function VMImport {

	set -e

	echo
	echo "Downloading and importing XVA image..."
	echo

	# Import image. We pipe through zcat because xe vm-import should transparently decompress gzipped image, but doesn't seem to understand when stream ends when piped through curl/wget whatnot.
	# if SR was not defined, we leave that parameter out
	if [[ $sruuid == "default" ]]; then
		uuid=$(curl "$IMAGE_URL" | zcat | xe vm-import filename=/dev/stdin)
	else
		uuid=$(curl "$IMAGE_URL" | zcat | xe vm-import filename=/dev/stdin sr-uuid="$sruuid")
	fi

	# exit if import failed for any reason
	# shellcheck disable=SC2181
	if [[ $? != "0" ]]; then
		echo "Import failed"
		exit 1
	fi
	echo
	echo "Import complete"

	# no network interface included in the image, we need to create one based on network uuid set by user earlier
	xe vif-create network-uuid="$vifuuid" vm-uuid="$uuid" device=0 >/dev/null

	# VM startup script reads network details from xenstore and configures interface based on that so set values based on user input earlier
	if [[ "$ipaddress" != "dhcp" ]]; then
		xe vm-param-set uuid="$uuid" xenstore-data:vm-data/ip="$ipaddress" xenstore-data:vm-data/netmask="$netmask" xenstore-data:vm-data/gateway="$gateway" xenstore-data:vm-data/dns="$dns"
	fi

	# remove all other boot options except disk to speed startup
	xe vm-param-remove uuid="$uuid" param-name=HVM-boot-params param-key=order
	xe vm-param-set uuid="$uuid" HVM-boot-params:"order=c"

	echo
	echo "Starting VM..."
	xe vm-start uuid="$uuid"

	set +e

	# loop max 300 seconds for VM to startup and xen tools to announce ip-address value
	count=0
	limit=10
	ip=$(xe vm-param-get uuid="$uuid" param-name=networks param-key=0/ip 2>/dev/null)
	while [[ -z "$ip" ]] && [[ "$count" -lt "$limit" ]]; do
		echo "Waiting for VM to start and announce it got IP-address"
		sleep 30
		ip=$(xe vm-param-get uuid="$uuid" param-name=networks param-key=0/ip 2>/dev/null)
		(( count++ ))
	done

	# network details are needed in xenstore only during first startup so remove them at this point since VM should be running
	if [[ "$ipaddress" != "dhcp" ]]; then
		xe vm-param-remove param-name=xenstore-data param-key=vm-data/ip uuid="$uuid" 2>/dev/null
		xe vm-param-remove param-name=xenstore-data param-key=vm-data/netmask uuid="$uuid" 2>/dev/null
		xe vm-param-remove param-name=xenstore-data param-key=vm-data/gateway uuid="$uuid" 2>/dev/null
		xe vm-param-remove param-name=xenstore-data param-key=vm-data/dns uuid="$uuid" 2>/dev/null
	fi

	# if we got ip-address value from VM, we print how to access it...
	if [[ "$ip" != "" ]]; then
		echo
		echo "VM Started successfully"
		echo
		echo "You can access Xen Orchestra at https://$ip and via SSH at $ip"
		echo "Default credentials for UI: admin@admin.net/admin"
		echo "Default credentials for SSH: xo/xopass"
		echo
		echo "Remember to change both passwords before putting VM to use!"
	# ... and print the same without ip-address information if ip-address value was missing
	else
		echo
		echo "VM started but we couldn't fetch it's ip-address from xentools"
		echo
		echo "Check VM status/ip-address manually. If VM started correctly, it should have Web UI and SSH accessible at it's ip-address"
		echo "Default credentials for UI: admin@admin.net/admin"
		echo "Default credentials for SSH: xo/xopass"
		echo
		echo "Remember to change both passwords before putting VM to use!"
	fi

}

# run all functions in a specific order
OSCheck
StorageChoose
NetworkChoose
NetworkSettings
VMImport
