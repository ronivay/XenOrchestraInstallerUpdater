#!/bin/bash

function RunTestsSingle {

	export VAGRANT_CWD="$(dirname $0)/$1"
	local LOGFILE="$(dirname $0)/$1/installation-test.log"
	vagrant up --no-provision &> $LOGFILE

	if [[ $? == "1" ]]; then
		echo "Vagrant box failed to start, exiting"
		exit 1;
	fi

	vagrant provision --provision-with install >> $LOGFILE 2>&1
	sleep 5
	echo "" >> $LOGFILE
	echo "Curl output after install:" >> $LOGFILE
	curl -s -L 192.168.33.101 >> $LOGFILE 2>&1 || false

	if [[ $? == "1" ]]; then
		echo "$1 install HTTP Check: failed"
	else
		echo "$1 install HTTP Check: success"
	fi
	sleep 5

	vagrant provision --provision-with update >> $LOGFILE 2>&1
	sleep 5
	echo "" >> $LOGFILE
	echo "Curl output after update:" >> $LOGFILE
	curl -s -L 192.168.33.101 >> $LOGFILE 2>&1 || false

	if [[ $? == "1" ]]; then
		echo "$1 update HTTP Check: failed"
	else
		echo "$1 update HTTP Check: success"
	fi
	sleep 5

	vagrant destroy -f >> $LOGFILE 2>&1
	unset VAGRANT_CWD

}

function RunTestsAll {

for x in CentOS Debian Ubuntu; do

	export VAGRANT_CWD="$(dirname $0)/$x"
	local LOGFILE="$(dirname $0)/$x/installation-test.log"
	vagrant up --no-provision &> $LOGFILE

	if [[ $? == "1" ]]; then
		echo "Vagrant box failed to start, exiting"
		exit 1;
	fi

	vagrant provision --provision-with install >> $LOGFILE 2>&1
	sleep 5
	echo "" >> $LOGFILE
	echo "Curl output after install:" >> $LOGFILE
	curl -s -L -m 5 192.168.33.101 >> $LOGFILE 2>&1 || false

	if [[ $? == "1" ]]; then
		echo "$x install HTTP Check: failed"
	else
		echo "$x install HTTP Check: success"
	fi
	sleep 5

	vagrant provision --provision-with update >> $LOGFILE 2>&1
	sleep 5
	echo "" >> $LOGFILE
	echo "Curl output after update:" >> $LOGFILE
	curl -s -L -m 5 192.168.33.101 >> $LOGFILE 2>&1 || false

	if [[ $? == "1" ]]; then
		echo "$x update HTTP Check: failed"
	else
		echo "$x update HTTP Check: success"
	fi

	vagrant destroy -f >> $LOGFILE 2>&1
	unset VAGRANT_CWD
done

}

if [[ $# == "1" ]]; then
	RunTestsSingle "$1"
	exit 0
else
	RunTestsAll
	exit 0
fi
