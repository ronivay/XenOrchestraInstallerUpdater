#!/bin/bash

function RunTestsSingle {

	export VAGRANT_CWD="$(dirname $0)/$1"
	local LOGFILE="$(dirname $0)/$1/installation-test.log"
	vagrant up &> $LOGFILE
	sleep 5
	echo "" >> $LOGFILE
	curl -s -L 192.168.33.101 >> $LOGFILE 2>&1 || false

	if [[ $? == "1" ]]; then
	echo "$1 HTTP Check: failed"
	else
		echo "$1 HTTP Check: success"
	fi
	sleep 5
	vagrant destroy -f &> $LOGFILE
	unset VAGRANT_CWD

echo $1

}

function RunTestsAll {

for x in CentOS Debian Ubuntu; do

	export VAGRANT_CWD="$(dirname $0)/$x"
	local LOGFILE="$(dirname $0)/$x/installation-test.log"
	vagrant up &> $LOGFILE
	sleep 5
	echo "" >> $LOGFILE
	echo "Curl output:" >> $LOGFILE
	curl -s -L -m 5 192.168.33.101 >> $LOGFILE 2>&1 || false
	
	if [[ $? == "1" ]]; then
		echo "$x HTTP Check: failed"
	else
		echo "$x HTTP Check: success"
	fi
	sleep 5
	vagrant destroy -f &> $LOGFILE
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
