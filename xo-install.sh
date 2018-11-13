#!/bin/bash

#########################################################################
# Title: XenOrchestraInstallerUpdater                                   #
# Author: Roni Väyrynen                                                 #
# Repository: https://github.com/ronivay/XenOrchestraInstallerUpdater   #
#########################################################################

SAMPLE_CONFIG_FILE="$(dirname $0)/sample.xo-install.cfg"
CONFIG_FILE="$(dirname $0)/xo-install.cfg"

# Deploy default configuration file if the user doesn't have their own yet.
if [[ ! -e "$CONFIG_FILE" ]]; then
	cp $SAMPLE_CONFIG_FILE $CONFIG_FILE
fi

# See this file for all script configuration variables.
source $CONFIG_FILE

# Set some default variables if sourcing config file fails for some reason
PORT=${PORT:-80}
INSTALLDIR=${INSTALLDIR:-"/etc/xo"}
BRANCH=${BRANCH:-"master"}
LOGFILE=${LOGFILE:-"$(dirname $0)/xo-install.log"}
AUTOUPDATE=${AUTOUPDATE:-"true"}
PRESERVE=${PRESERVE:-"3"}

# Set path where new source is cloned/pulled
XO_SRC_DIR="$INSTALLDIR/xo-src/xen-orchestra"

# Protocol to use for webserver. If both of the X.509 certificate files exist,
# then assume that we want to enable HTTPS for the server.
if [[ -e $PATH_TO_HTTPS_CERT ]] && [[ -e $PATH_TO_HTTPS_KEY ]]; then
	HTTPS=true
else
	HTTPS=false
fi

function CheckUser {

	# Make sure the script is ran as root

	if [[ ! "$(id -u)" == "0" ]]; then
		echo "This script needs to be ran as root"
		exit 0
	fi

}

function ErrorHandling {

	echo "Something went wrong, exiting. Check $LOGFILE for more details and use rollback feature if needed"

	if [[ -d $INSTALLDIR/xo-builds/xen-orchestra-$TIME ]]; then
		echo "Removing $INSTALLDIR/xo-builds/xen-orchestra-$TIME because of failed installation."
		rm -rf $INSTALLDIR/xo-builds/xen-orchestra-$TIME
	fi
}

function InstallDependenciesCentOS {

	set -e

	trap ErrorHandling ERR INT

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

	# only install libvhdi-tools if vhdimount is not present
	if [[ -z $(which vhdimount) ]]; then
		echo
		echo -n "Installing libvhdi-tools from forensics repository"
		rpm -ivh https://forensics.cert.org/cert-forensics-tools-release-el7.rpm >/dev/null
		sed -i 's/enabled=1/enabled=0/g' /etc/yum.repos.d/cert-forensics-tools.repo
		yum --enablerepo=forensics install -y libvhdi-tools >/dev/null
		echo "done"
	fi

	# install
	echo
	echo -n "Installing build dependencies, redis server, python, git, nfs-utils..."
	yum -y install gcc gcc-c++ make openssl-devel redis libpng-devel python git nfs-utils >/dev/null
	echo "done"
	echo

	echo "Enabling and starting redis service"
	/bin/systemctl enable redis >/dev/null && /bin/systemctl start redis >/dev/null

	echo "Enabling and starting rpcbind service"
	/bin/systemctl enable rpcbind >/dev/null && /bin/systemctl start rpcbind >/dev/null

} 2>$LOGFILE

function InstallDependenciesDebian {

	set -e

	trap ErrorHandling ERR INT

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

	# install setcap for non-root port binding if missing
	if [[ -z $(which setcap) ]]; then
		echo
		echo -n "Installing setcap..."
		apt-get install -y libcap2-bin >/dev/null
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
	echo -n "Installing build dependencies, redis server, python, git, libvhdi-utils, lvm2, nfs-common..."
	apt-get install -y build-essential redis-server libpng-dev git python-minimal libvhdi-utils lvm2 nfs-common >/dev/null

	echo "Enabling and starting redis service"
	/bin/systemctl enable redis-server >/dev/null && /bin/systemctl start redis-server >/dev/null

	echo "Enabling and starting rpcbind service"
	/bin/systemctl enable rpcbind >/dev/null && /bin/systemctl start rpcbind >/dev/null

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

	set -e

	trap ErrorHandling ERR INT

	if [[ "$PLUGINS" ]] && [[ ! -z "$PLUGINS" ]]; then

		if [[ "$PLUGINS" == "all" ]]; then
			echo
			echo "Installing all available plugins as defined in PLUGINS variable"
			find "$INSTALLDIR/xo-builds/xen-orchestra-$TIME/packages/" -maxdepth 1 -mindepth 1 -not -name "xo-server" -not -name "xo-web" -not -name "xo-server-cloud" -exec ln -sn {} "$INSTALLDIR/xo-builds/xen-orchestra-$TIME/packages/xo-server/node_modules/" \;
		else
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
		fi

		cd $INSTALLDIR/xo-builds/xen-orchestra-$TIME && yarn >/dev/null && yarn build >/dev/null
	else
		echo
		echo "No plugins to install"
	fi

} 2>$LOGFILE

function InstallXO {

	set -e

	trap ErrorHandling ERR INT

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
	echo "Fetching Xen Orchestra source code ..."
	echo
	if [[ ! -d "$XO_SRC_DIR" ]]; then
		mkdir -p "$XO_SRC_DIR"
		git clone https://github.com/vatesfr/xen-orchestra "$XO_SRC_DIR"
	else
		cd "$XO_SRC_DIR"
		git pull
		cd $(dirname $0)
	fi

	# Deploy the latest xen-orchestra source to the new install directory.
	echo
	echo "Creating install directory: $INSTALLDIR/xo-builds/xen-orchestra-$TIME"
	rm -rf "$INSTALLDIR/xo-builds/xen-orchestra-$TIME"
	cp -r "$XO_SRC_DIR" "$INSTALLDIR/xo-builds/xen-orchestra-$TIME"

	if [[ "$BRANCH" == "release" ]]; then
		cd $INSTALLDIR/xo-builds/xen-orchestra-$TIME
		TAG=$(git describe --tags $(git rev-list --tags --max-count=1))

		echo
		echo "Checking out latest tagged release '$TAG'"

		git checkout $TAG 2> /dev/null  # Suppress the detached-head message.
		cd $(dirname $0)
	elif [[ "$BRANCH" != "master" ]]; then
		echo
		echo "Checking out source code from branch '$BRANCH'"

		cd $INSTALLDIR/xo-builds/xen-orchestra-$TIME
		git checkout $BRANCH
		cd $(dirname $0)
	fi

	echo
	echo "done"

	# Check if the new repo is any different from the currently-installed
	# one. If not, then skip the build and delete the repo we just cloned.

	# Get the commit ID of the to-be-installed xen-orchestra.
	cd $INSTALLDIR/xo-builds/xen-orchestra-$TIME
	NEW_REPO_HASH=$(git rev-parse HEAD)
	NEW_REPO_HASH_SHORT=$(git rev-parse --short HEAD)
	cd $(dirname $0)

	# Get the commit ID of the currently-installed xen-orchestra (if one
	# exists).
	if [[ -L $INSTALLDIR/xo-server ]]; then
		cd $INSTALLDIR/xo-server
		OLD_REPO_HASH=$(git rev-parse HEAD)
		OLD_REPO_HASH_SHORT=$(git rev-parse --short HEAD)
		cd $(dirname $0)
	else
		# If there's no existing installation, then we definitely want
		# to proceed with the bulid.
		OLD_REPO_HASH=""
		OLD_REPO_HASH_SHORT=""
	fi

	# If the new install is no different from the existing install, then don't
	# proceed with the build.
	if [[ "$NEW_REPO_HASH" == "$OLD_REPO_HASH" ]]; then
		echo
		echo "No changes to xen-orchestra since previous install. Skipping xo-server and xo-web build."
		echo "Cleaning up install directory: $INSTALLDIR/xo-builds/xen-orchestra-$TIME"
		rm -rf $INSTALLDIR/xo-builds/xen-orchestra-$TIME
		return 0
	fi

	# Now that we know we're going to be building a new xen-orchestra, make
	# sure there's no already-running xo-server process.
	if [[ $(ps aux | grep xo-server | grep -v grep) ]]; then
		echo
		echo -n "Shutting down xo-server..."
		/bin/systemctl stop xo-server || { echo "failed to stop service, exiting..." ; exit 1; }
		echo "done"
	fi

	# If this isn't a fresh install, then list the upgrade the user is making.
	if [[ ! -z "$OLD_REPO_HASH" ]]; then
		echo
		echo "Updating xen-orchestra from '$OLD_REPO_HASH_SHORT' to '$NEW_REPO_HASH_SHORT'"
	fi

	echo
	echo "xo-server and xo-web build quite a while. Grab a cup of coffee and lay back"
	echo
	echo -n "Running installation..."
	cd $INSTALLDIR/xo-builds/xen-orchestra-$TIME && yarn >/dev/null && yarn build >/dev/null
	echo "done"

	# Install plugins
	InstallXOPlugins

	echo
	echo "Fixing binary path in systemd service configuration file"
	sed -i "s#ExecStart=.*#ExecStart=$INSTALLDIR\/xo-server\/bin\/xo-server#" $INSTALLDIR/xo-builds/xen-orchestra-$TIME/packages/xo-server/xo-server.service
	echo
	echo "Adding WorkingDirectory parameter to systemd service configuration file"
	sed -i "/ExecStart=.*/a WorkingDirectory=$INSTALLDIR/xo-server" $INSTALLDIR/xo-builds/xen-orchestra-$TIME/packages/xo-server/xo-server.service

	if [ $XOUSER ]; then
		echo "Adding user to systemd config"
		sed -i "/SyslogIdentifier=.*/a User=$XOUSER" $INSTALLDIR/xo-builds/xen-orchestra-$TIME/packages/xo-server/xo-server.service

		if [ "$PORT" -le "1024" ]; then
			NODEBINARY="$(which node)"
			if [[ -L "$NODEBINARY" ]]; then
				NODEBINARY="$(readlink -e $NODEBINARY)"
			fi

			if [[ ! -z $NODEBINARY ]]; then
				echo -n "Attempting to set cap_net_bind_service permission for $NODEBINARY..."
				setcap 'cap_net_bind_service=+ep' $NODEBINARY >/dev/null \
				&& echo "Success" || echo "Failed. Non-privileged user might not be able to bind to <1024 port. xo-server won't start most likely"
			else
				echo "Can't find node executable, or it's a symlink to non existing file. Not trying to setcap. xo-server won't start most likely"
			fi
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

	if $HTTPS ; then
		echo "Enabling HTTPS in xo-server configuration file"
		sed -i "s%#   cert: '.\/certificate.pem'%  cert: '$PATH_TO_HTTPS_CERT'%" $INSTALLDIR/xo-builds/xen-orchestra-$TIME/packages/xo-server/sample.config.yaml
		sed -i "s%#   key: '.\/key.pem'%  key: '$PATH_TO_HTTPS_KEY'%" $INSTALLDIR/xo-builds/xen-orchestra-$TIME/packages/xo-server/sample.config.yaml
		sed -i "s/#redirectToHttps/redirectToHttps/" $INSTALLDIR/xo-builds/xen-orchestra-$TIME/packages/xo-server/sample.config.yaml
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

		chown -R $XOUSER:$XOUSER /var/lib/xo-server
	fi

	# fix to prevent older installations to not update because systemd service is not symlinked anymore
	if [[ $(find /etc/systemd/system -maxdepth 1 -type l -name "xo-server.service") ]]; then
		rm -f /etc/systemd/system/xo-server.service
	fi

	echo
	echo "Replacing systemd service configuration file"

	/bin/cp -f $INSTALLDIR/xo-builds/xen-orchestra-$TIME/packages/xo-server/xo-server.service /etc/systemd/system/xo-server.service
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
		while [[ -z $(journalctl -u xo-server | sed -n 'H; /Starting XO Server/h; ${g;p;}' | grep "https\{0,1\}:\/\/\[::\]:$PORT") ]]; do
			echo "waiting for port to be open"
			sleep 10
		done
	EOF

	if [[ $(journalctl -u xo-server | sed -n 'H; /Starting XO Server/h; ${g;p;}' | grep "https\{0,1\}:\/\/\[::\]:$PORT") ]]; then
		echo
		echo "WebUI started in port $PORT"
		echo "Default username: admin@admin.net password: admin"
		echo
		echo "Installation successful. Enabling xo-server to start on reboot"
		/bin/systemctl enable xo-server > /dev/null
	else
		echo
		echo "Looks like there was a problem when starting xo-server/reading journalctl. Please see logs for more details"
		exit 1
	fi

} 2>$LOGFILE


function UpdateXO {

	InstallXO

	if [[ "$PRESERVE" != "0" ]]; then

		# remove old builds. leave as many as defined in PRESERVE variable
		echo
		echo -n "Removing old installations (leaving $PRESERVE latest)..."
		find $INSTALLDIR/xo-builds/ -maxdepth 1 -type d -name "xen-orchestra*" -printf "%T@ %p\n" | sort -n | cut -d' ' -f2- | head -n -$PRESERVE | xargs -r rm -r
		echo "done"
	else
		echo "PRESERVE variable is set to 0. This needs to be at least 1. Not doing a cleanup"
	fi

} 2>$LOGFILE

function HandleArgs {

	case "$1" in
		--update)
			UpdateNodeYarn
			UpdateXO
			;;
		--install)
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
		--rollback)
			RollBackInstallation
			exit 0
			;;
		*)
			StartUpScreen
			;;
		esac

}

function RollBackInstallation {

	INSTALLATIONS=($(find $INSTALLDIR/xo-builds/ -maxdepth 1 -type d -name "xen-orchestra-*"))

	if [[ $(echo ${#INSTALLATIONS[@]}) -le 1 ]]; then
		echo "Only one installation exists, nothing to change"
		exit 0
	fi

	echo "Which installation to roll back?"
	echo
	local PS3="Pick a number. CTRL+C to exit: "
	select INSTALLATION in "${INSTALLATIONS[@]}"; do
		case $INSTALLATION in
			*xen-orchestra*)
				echo
				echo "Setting $INSTALLDIR/xo-server symlink to $INSTALLATION/packages/xo-server"
				ln -sfn $INSTALLATION/packages/xo-server $INSTALLDIR/xo-server
				echo "Setting $INSTALLDIR/xo-web symlink to $INSTALLATION/packages/xo-web"
				ln -sfn $INSTALLATION/packages/xo-web $INSTALLDIR/xo-web
				echo
				echo "Replacing xo.server.service systemd configuration file"
				/bin/cp -f $INSTALLATION/packages/xo-server/xo-server.service /etc/systemd/system/xo-server.service
				/bin/systemctl daemon-reload
				echo
				echo "Restarting xo-server..."
				/bin/systemctl restart xo-server
				echo
				break
			;;
			*)
				echo "Try again"
			;;
			esac
		done

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
echo "  X (defined in PRESERVE variable) number of latest installations will be preserved and older ones are deleted after successful update. Fresh installation is symlinked as active"
echo "  Rollback to another installation with --rollback"
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
echo "Number of previous installations to preserve: $PRESERVE"
echo
echo "Errorlog is stored to $LOGFILE for debug purposes"
echo "-----------------------------------------"

echo
echo "1. Autoinstall"
echo "2. Update / Install without packages"
echo "3. Deploy docker container"
echo "4. Rollback to another existing installation"
echo "5. Exit"
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
			PullDockerImage
		;;
		4)
			RollBackInstallation
			exit 0
		;;
		5)
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
	HandleArgs "$1"
	exit 0
else
	StartUpScreen
fi
