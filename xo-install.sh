#!/bin/bash

#########################################################################
# Title: XenOrchestraInstallerUpdater                                   #
# Author: Roni Väyrynen                                                 #
# Repository: https://github.com/ronivay/XenOrchestraInstallerUpdater   #
#########################################################################

### Start of editable variables ###

# Optional user that runs the service. root by default
#XOUSER="node"

# Port number where xen-orchestra service is bound
PORT="80"

# Base dir for installation and future updates
INSTALLDIR="/etc/xo"

# Git branch or tag (append tags/ before the tag name) where xen-orchestra sources are fetched
BRANCH="master"

# Log path for possible errors
LOGFILE="$(dirname $0)/xo-install.log"

# comma separated list of plugins to be installed, check README for more information
#PLUGINS="xo-server-transport-email,xo-server-usage-report,xo-server-perf-alert"

# NodeJS and Yarn are automatically updated when running update. Switch this option to false if you want to disable it.
AUTOUPDATE="true"

### End of editable variables ###

function CheckUser {

	# Make sure the script is ran as root

	if [[ ! "$(id -u)" == "0" ]]; then
		echo "This script needs to be ran as root"
		exit 0
	fi

}

function InstallDependenciesCentOS {

	set -e

	# Install necessary dependencies for XO build

	# only run automated node install if package not found
	if [[ -z $(rpm -qa | grep ^node) ]]; then
		echo
		echo -n "Installing node.js..."
		curl -s -L https://rpm.nodesource.com/setup_8.x | bash - >/dev/null
		echo "done"
	fi

	# only install yarn repo and package if not found
	if [[ -z $(rpm -qa | grep yarn) ]]; then
		echo
		echo -n "Installing yarn..."
		curl -s -o /etc/yum.repos.d/yarn.repo https://dl.yarnpkg.com/rpm/yarn.repo >/dev/null && \
		yum -y install yarn >/dev/null
		echo "done"
	fi

	# only install epel-release if doesn't exist
	if [[ -z $(rpm -qa | grep epel-release) ]]; then
		echo
		echo -n "Installing epel-repo..."
		yum -y install epel-release >/dev/null
		echo "done"
	fi

	# install
	echo
	echo -n "Installing build dependencies, redis server, python and git..."
	yum -y install gcc gcc-c++ make openssl-devel redis libpng-devel python git >/dev/null
	echo "done"
	echo

	echo "Enabling and starting redis service"
	/bin/systemctl enable redis >/dev/null && /bin/systemctl start redis >/dev/null

} 2>$LOGFILE

function InstallDependenciesDebian {

	set -e

	# Install necessary dependencies for XO build
        
	echo
	echo -n "Running apt-get update..."
	apt-get update >/dev/null
	echo "done"

	# Install apt-transport-https and ca-certificates because of yarn https repo url
	echo
	echo -n "Installing apt-transport-https and ca-certificates packages to support https repos"
	apt-get install -y apt-transport-https ca-certificates >/dev/null
	echo "done"

	# install curl for later tasks if missing
	if [[ -z $(which curl) ]]; then
		echo
		echo -n "Installing curl..."
		apt-get install -y curl >/dev/null
		echo "done"
	fi

	# only install yarn repo and package if not found
	if [[ -z $(dpkg -l | grep yarn) ]]; then
		echo
		echo -n "Installing yarn..."
		curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | apt-key add - >/dev/null
		echo "deb https://dl.yarnpkg.com/debian/ stable main" | tee /etc/apt/sources.list.d/yarn.list >/dev/null
		apt-get update >/dev/null
		apt-get install -y yarn >/dev/null
		echo "done"
	fi


	# only run automated node install if package not found
	if [[ -z $(dpkg -l | grep node) ]] || [[ -z $(which npm) ]]; then
		echo
		echo -n "Installing node.js..."
		curl -sL https://deb.nodesource.com/setup_8.x | bash - >/dev/null
		apt-get install -y nodejs >/dev/null
		echo "done"
	fi


	# install packages
	echo
	echo -n "Installing build dependencies, redis server, python and git..."
	apt-get install -y build-essential redis-server libpng-dev git python-minimal >/dev/null

	echo "Enabling and starting redis service"
	/bin/systemctl enable redis-server >/dev/null && /bin/systemctl start redis-server >/dev/null


} 2>$LOGFILE

function UpdateNodeYarn {

	if [[ $AUTOUPDATE == "true" ]]; then

		if [ $OSNAME == "CentOS" ]; then
			echo
			echo "Checking updates for nodejs and yarn"
			yum update -y nodejs yarn > /dev/null
		else
			echo
			echo "Checking updates for nodejs and yarn"
			apt-get install -y --only-upgrade nodejs yarn > /dev/null
		fi
	fi

} 2>$LOGFILE

function InstallXOPlugins {

	if [[ "$PLUGINS" ]] && [[ ! -z "$PLUGINS" ]]; then

		echo
		echo "Installing plugins defined in PLUGINS variable"
		echo
		local PLUGINSARRAY=($(echo "$PLUGINS" | tr ',' ' '))
		for x in "${PLUGINSARRAY[@]}"; do
			if [[ $(find $INSTALLDIR/xo-builds/xen-orchestra-$TIME/packages -type d -name "$x") ]]; then
				ln -sn $INSTALLDIR/xo-builds/xen-orchestra-$TIME/packages/$x $INSTALLDIR/xo-builds/xen-orchestra-$TIME/packages/xo-server/node_modules/
			else
				echo "No $x plugin found from xen-orchestra packages, skipping"
				continue
			fi
		done

		cd $INSTALLDIR/xo-builds/xen-orchestra-$TIME && yarn >/dev/null && yarn build >/dev/null
	else
		echo
		echo "No plugins to install"
	fi

}

function InstallXO {

	set -e

	TIME=$(date +%Y%d%m%H%M)

	# Create user if doesn't exist (if defined)

	if [ $XOUSER ]; then
		if [[ -z $(getent passwd $XOUSER) ]]; then
			echo
			echo "Creating missing $XOUSER user"
			useradd -s /sbin/nologin $XOUSER
			echo
			sleep 2
		fi
	fi

	# Create installation directory if doesn't exist already
	if [[ ! -d "$INSTALLDIR" ]] ; then
		echo "Creating missing basedir to $INSTALLDIR"
		mkdir -p "$INSTALLDIR"
	fi

	echo
	echo "Creating install directory: $INSTALLDIR/xo-builds/xen-orchestra-$TIME"
	mkdir -p "$INSTALLDIR/xo-builds/xen-orchestra-$TIME"

	echo
	echo "Fetching source code from branch: $BRANCH ..."
	echo
	git clone https://github.com/vatesfr/xen-orchestra $INSTALLDIR/xo-builds/xen-orchestra-$TIME
	cd $INSTALLDIR/xo-builds/xen-orchestra-$TIME
	git checkout $BRANCH
	cd $(dirname $0)
	echo
	echo "done"

	echo
	echo "xo-server and xo-web build quite a while. Grab a cup of coffee and lay back"
	echo
	echo -n "Running installation..."
	cd $INSTALLDIR/xo-builds/xen-orchestra-$TIME && yarn >/dev/null && yarn build >/dev/null
	echo "done"

	# Install plugins
	InstallXOPlugins

	echo
	echo "Fixing binary path in systemd service configuration and symlinking to /etc/systemd/system/xo-server.service"
	sed -i "s#ExecStart=.*#ExecStart=$INSTALLDIR\/xo-server\/bin\/xo-server#" $INSTALLDIR/xo-builds/xen-orchestra-$TIME/packages/xo-server/xo-server.service
	echo
	echo "Adding WorkingDirectory parameter to systemd service configuration"
	sed -i "/ExecStart=.*/a WorkingDirectory=$INSTALLDIR/xo-server" $INSTALLDIR/xo-builds/xen-orchestra-$TIME/packages/xo-server/xo-server.service

	if [ $XOUSER ]; then
		echo "Adding user to systemd config"
		sed -i "/SyslogIdentifier=.*/a User=$XOUSER" $INSTALLDIR/xo-builds/xen-orchestra-$TIME/packages/xo-server/xo-server.service

		if [ $OSNAME == "CentOS" ]; then
			echo -n "Attempting to set cap_net_bind_service permission for /usr/bin/node..."
			setcap 'cap_net_bind_service=+ep' /usr/bin/node >/dev/null \
			&& echo "Success" || echo "Failed. Non-privileged user might not be able to bind to <1024 port"
		else
			echo -n "Attempting to set cap_net_bind_service permission for /usr/bin/nodejs..."
			setcap 'cap_net_bind_service=+ep' /usr/bin/nodejs >/dev/null \
			&& echo "Success" || echo "Failed. Non-privileged user might not be able to bind to <1024 port"
		fi
	fi

	echo "Fixing relative path to xo-web installation in xo-server configuration file"
	sed -i "s/#'\/': '\/path\/to\/xo-web\/dist\//'\/': '..\/xo-web\/dist\//" $INSTALLDIR/xo-builds/xen-orchestra-$TIME/packages/xo-server/sample.config.yaml
	sleep 2

	if [[ $PORT != "80" ]]; then
		echo "Changing port in xo-server configuration file"
		sed -i "s/port: 80/port: $PORT/" $INSTALLDIR/xo-builds/xen-orchestra-$TIME/packages/xo-server/sample.config.yaml
		sleep 2
	fi

	echo "Activating modified configuration file"
	mv $INSTALLDIR/xo-builds/xen-orchestra-$TIME/packages/xo-server/sample.config.yaml $INSTALLDIR/xo-builds/xen-orchestra-$TIME/packages/xo-server/.xo-server.yaml

	echo
	echo "Symlinking fresh xo-server install/update to $INSTALLDIR/xo-server"
	ln -sfn $INSTALLDIR/xo-builds/xen-orchestra-$TIME/packages/xo-server $INSTALLDIR/xo-server
	sleep 2
	echo "Symlinking fresh xo-web install/update to $INSTALLDIR/xo-web"
	ln -sfn $INSTALLDIR/xo-builds/xen-orchestra-$TIME/packages/xo-web $INSTALLDIR/xo-web

	if [ $XOUSER ]; then
		chown -R $XOUSER:$XOUSER $INSTALLDIR/xo-builds/xen-orchestra-$TIME

		if [ ! -d /var/lib/xo-server ]; then
			mkdir /var/lib/xo-server 2>/dev/null
		fi

		chown $XOUSER:$XOUSER /var/lib/xo-server
	fi

	echo
	echo "Symlinking systemd service configuration"
	ln -sfn $INSTALLDIR/xo-server/xo-server.service /etc/systemd/system/xo-server.service
	sleep 2
	echo "Reloading systemd configuration"
	echo
	/bin/systemctl daemon-reload
	sleep 2

	echo
	echo "Starting xo-server..."
	/bin/systemctl start xo-server >/dev/null

	# no need to exit on errors anymore
	set +x

	timeout 60 bash <<-"EOF"
		while [[ -z $(journalctl -u xo-server | sed -n 'H; /Starting XO Server/h; ${g;p;}' | grep "http:\/\/\[::\]:$PORT") ]]; do
			echo "waiting port to be open"
			sleep 10
		done
	EOF

	if [[ $(journalctl -u xo-server | sed -n 'H; /Starting XO Server/h; ${g;p;}' | grep "http:\/\/\[::\]:$PORT") ]]; then
		echo
		echo "WebUI started in port $PORT"
		echo "Default username: admin@admin.net password: admin"
		echo
		echo "Installation successful. Control xo-server.service with systemctl"
	else
		echo
		echo "Looks like there was a problem when starting xo-server/reading journalctl. Please see logs for more details"
	fi

} 2>$LOGFILE


function UpdateXO {

	if [[ $(ps aux | grep xo-server | grep -v grep) ]]; then
		/bin/systemctl stop xo-server || { echo "failed to stop service, exiting..." ; exit 1; }
	fi

	InstallXO

	# remove old builds. leave 3 latest
	echo
	echo -n "Removing old installations (leaving 3 latest)..."
	find $INSTALLDIR/xo-builds/ -maxdepth 1 -type d -name "xen-orchestra*" -printf "%T@ %p\n" | sort -n | cut -d' ' -f2- | head -n -3 | xargs -r rm -r
	echo "done"

} 2>$LOGFILE

function UpdateXOAutomate {

	case "$1" in
		--update)
			UpdateNodeYarn
			UpdateXO
			;;
		*)
			StartUpScreen
			;;
		esac

}	

function CheckOS {

	if [ -f /etc/centos-release ] ; then
		OSVERSION=$(grep -Eo "[0-9]" /etc/centos-release | head -1)
		OSNAME="CentOS"
		if [[ ! $OSVERSION == "7" ]]; then
			echo "Only CentOS 7 supported"
			exit 0
		fi
	elif [[ -f /etc/os-release ]]; then
		OSVERSION=$(grep ^VERSION_ID /etc/os-release | cut -d'=' -f2 | grep -Eo "[0-9]{1,2}" | head -1)
		OSNAME=$(grep ^NAME /etc/os-release | cut -d'=' -f2 | sed 's/"//g' | awk '{print $1}')
		if [[ $OSNAME == "Debian" ]] && [[ ! $OSVERSION =~ ^(8|9)$ ]]; then
			echo "Only Debian 8/9 supported"
			exit 0
		elif [[ $OSNAME == "Ubuntu" ]] && [[ ! $OSVERSION == "16" ]]; then
			echo "Only Ubuntu 16 supported"
			exit 0
		fi
	else
		echo "Only CentOS 7 / Ubuntu 16 and Debian 8/9 supported"
		exit 0
	fi

} 2>$LOGFILE

function CheckSystemd {

	if [ -z $(which systemctl) ]; then
		echo "This tool is designed to work with systemd enabled systems only"
		exit 0
	fi
}

function CheckDocker {

	if [ -z $(which docker) ]; then
		echo
		echo "Docker needs to be installed for this to work"
		exit 0
	fi

}

function BuildDockerImage {

	echo
	docker build -t xen-orchestra $(dirname $0)/docker/.
	echo
	echo
	echo "Image built. Run container:"
	echo "docker run -itd -p 80:80 xen-orchestra"
	echo
	echo "If you want to persist xen-orchestra and redis data, use volume flags like:"
	echo "docker run -itd -p 80:80 -v /path/to/data/xo-server:/var/lib/xo-server -v /path/to/data/redis:/var/lib/redis xen-orchestra"

} 2>$LOGFILE

function PullDockerImage {

	echo
	docker pull ronivay/xen-orchestra
	echo
	echo
	echo "Image pulled. Run container:"
	echo "docker run -itd -p 80:80 ronivay/xen-orchestra"
	echo
	echo "If you want to persist xen-orchestra and redis data, use volume flags like:"
	echo "docker run -itd -p 80:80 -v /path/to/data/xo-server:/var/lib/xo-server -v /path/to/data/redis:/var/lib/redis ronivay/xen-orchestra"

} 2>$LOGFILE

function StartUpScreen {

echo "-----------------------------------------"
echo
echo "This script will automatically install/update Xen-Orchestra"
echo
echo "- By default xo-server will be running as root to prevent issues with permissions and port binding."
echo "  uncomment and edit XOUSER variable in this script to run service as unprivileged user"
echo "  (Notice that you might have to make other changes depending on your system for this to work)"
echo "  This method only changes the user which runs the service. Other install tasks like node packages are still ran as root"
echo
echo "- Option 2. actually creates a new build from sources but works as an update to installations originally done with this tool"
echo "  NodeJS and Yarn packages are updated automatically. Check AUTOUPDATE variable to disable this"
echo "  Data stored in redis and /var/lib/xo-server/data will not be touched during update procedure."
echo "  3 latest installations will be preserved and older ones are deleted after successful update. Fresh installation is symlinked as active"
echo
echo "- To run option 2. without interactive mode (as cronjob for automated updates for example) use --update"
echo
echo "Following options will be used for installation:"
echo
echo "OS: $OSNAME $OSVERSION"
echo "Basedir: $INSTALLDIR"

if [ $XOUSER ]; then
	echo "User: $XOUSER"
else
	echo "User: root"
fi

echo "Port: $PORT"
echo "Git Branch for source: $BRANCH"
echo "Following plugins will be installed: "$PLUGINS""
echo
echo "Errorlog is stored to $LOGFILE for debug purposes"
echo "-----------------------------------------"

echo
echo "1. Autoinstall"
echo "2. Update / Install without packages"
echo "3. Deploy docker container"
echo "4. Exit"
echo
read -p ": " option

		case $option in
		1)
			if [[ $(ps aux | grep xo-server | grep -v grep) ]]; then
				echo "Looks like xo-server process is already running, consider running update instead. Continue anyway?"
				read -p "[y/N]: " answer
					case $answer in
						y)
						echo "Stopping xo-server..."
						/bin/systemctl stop xo-server || { echo "failed to stop service, exiting..." ; exit 1; }
					;;
						n)
						exit 0
					;;
						*)
						exit 0
					;;
						esac
			fi

			if [ $OSNAME == "CentOS" ]; then
				InstallDependenciesCentOS
				InstallXO
				exit 0
			else
				InstallDependenciesDebian
				InstallXO
				exit 0
			fi
		;;
		2)
			UpdateNodeYarn
			UpdateXO
			exit 0
		;;
		3)
			CheckDocker
			echo
			echo "Build image locally or fetch from docker hub?"
			echo "1. Build"
			echo "2. Pull"
			echo "3. Cancel"
			read -p ": " container
				case $container in
					1)
						BuildDockerImage
					;;
					2)
						PullDockerImage
						
					;;
					3)
						exit 0
					;;
					*)
						exit 0
					;;
					esac
		;;
		4)
			exit 0
		;;
		*)
			echo "Please choose one of the options"
			echo
			exit 0
		;;
esac

}

CheckUser
CheckOS
CheckSystemd

if [[ $# == "1" ]]; then
	UpdateXOAutomate "$1"
	exit 0
else
	StartUpScreen
fi
