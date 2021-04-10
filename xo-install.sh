#!/bin/bash

#########################################################################
# Title: XenOrchestraInstallerUpdater                                   #
# Author: Roni Väyrynen                                                 #
# Repository: https://github.com/ronivay/XenOrchestraInstallerUpdater   #
#########################################################################

SAMPLE_CONFIG_FILE="$(dirname $0)/sample.xo-install.cfg"
CONFIG_FILE="$(dirname $0)/xo-install.cfg"

# Deploy default configuration file if the user doesn't have their own yet.
if [[ ! -s "$CONFIG_FILE" ]]; then
	cp $SAMPLE_CONFIG_FILE $CONFIG_FILE
fi

# See this file for all script configuration variables.
source $CONFIG_FILE

# Set some default variables if sourcing config file fails for some reason
PORT=${PORT:-80}
INSTALLDIR=${INSTALLDIR:-"/opt/xo"}
BRANCH=${BRANCH:-"master"}
LOGPATH=${LOGPATH:-$(dirname "$(realpath $0)")/logs}
AUTOUPDATE=${AUTOUPDATE:-"true"}
PRESERVE=${PRESERVE:-"3"}
XOUSER=${XOUSER:-"root"}
CONFIGPATH="$(getent passwd $XOUSER | cut -d: -f6)"
PLUGINS="${PLUGINS:-"none"}"
REPOSITORY="${REPOSITORY:-"https://github.com/vatesfr/xen-orchestra"}"

# set variables not changeable in configfile
TIME=$(date +%Y%m%d%H%M)
LOGTIME=$(date "+%Y-%m-%d %H:%M:%S")
LOGFILE="${LOGPATH}/xo-install.log-$TIME"
NODEVERSION="14"
FORCE="false"
INTERACTIVE="false"

# Set path where new source is cloned/pulled
XO_SRC_DIR="$INSTALLDIR/xo-src/xen-orchestra"

# Set variables for stdout print
COLOR_N='\e[0m'
COLOR_GREEN='\e[1;32m'
COLOR_RED='\e[1;31m'
COLOR_BLUE='\e[1;34m'
COLOR_WHITE='\e[1;97m'
OK="[${COLOR_GREEN}ok${COLOR_N}]"
FAIL="[${COLOR_RED}fail${COLOR_N}]"
INFO="[${COLOR_BLUE}info${COLOR_N}]"
PROGRESS="[${COLOR_BLUE}..${COLOR_N}]"

# Protocol to use for webserver. If both of the X.509 certificate files exist,
# then assume that we want to enable HTTPS for the server.
if [[ $PATH_TO_HTTPS_CERT ]] && [[ $PATH_TO_HTTPS_KEY ]]; then
	if [[ -s $PATH_TO_HTTPS_CERT ]] && [[ -s $PATH_TO_HTTPS_KEY ]]; then
		HTTPS=true
	else
		HTTPS=false
		HTTPSFAIL="- certificate or Key doesn't exist or file is empty"
	fi
else
	HTTPS=false

fi

# create logpath if doesn't exist
if [[ ! -d $LOGPATH ]]; then
	mkdir -p $LOGPATH
fi

function CheckUser {

	# Make sure the script is ran as root

	if [[ ! "$(id -u)" == "0" ]]; then
		printfail "This script needs to be ran as root"
		exit 1
	fi

}

function cmdlog {
	echo "=== CMD ===: $@" >> $LOGFILE
	echo >> $LOGFILE
}

function printprog {
	echo -ne "${PROGRESS} $@"
}

function printok {
	echo -e "\r${OK} $@"
}

function printfail {
	echo -e "${FAIL} $@"
}

function printinfo {
	echo -e "${INFO} $@"
}

function ErrorHandling {

	set -eu

	echo
	printfail "Something went wrong, exiting. Check $LOGFILE for more details and use rollback feature if needed"

	if [[ -d $INSTALLDIR/xo-builds/xen-orchestra-$TIME ]]; then
		echo
		printfail "Removing $INSTALLDIR/xo-builds/xen-orchestra-$TIME because of failed installation."
		cmdlog "rm -rf $INSTALLDIR/xo-builds/xen-orchestra-$TIME"
		rm -rf $INSTALLDIR/xo-builds/xen-orchestra-$TIME >> $LOGFILE 2>&1
	fi

	exit 1
}

function InstallDependenciesCentOS {

	set -euo pipefail

	trap ErrorHandling ERR INT

	# Install necessary dependencies for XO build

	# install packages
	echo
	printprog "Installing build dependencies, redis server, python, git, nfs-utils, cifs-utils"
	cmdlog "yum -y install gcc gcc-c++ make openssl-devel redis libpng-devel python3 git nfs-utils cifs-utils lvm2"
	yum -y install gcc gcc-c++ make openssl-devel redis libpng-devel python3 git nfs-utils cifs-utils lvm2 >>$LOGFILE 2>&1
	printok "Installing build dependencies, redis server, python, git, nfs-utils, cifs-utils"

	# only run automated node install if executable not found
	cmdlog "which node"
	if [[ -z $(which node 2>>$LOGFILE) ]]; then
		echo
		printprog "Installing node.js"
		cmdlog "curl -s -L https://rpm.nodesource.com/setup_${NODEVERSION}.x | bash -"
		curl -s -L https://rpm.nodesource.com/setup_${NODEVERSION}.x | bash - >>$LOGFILE 2>&1
		printok "Installing node.js"
	else
		UpdateNodeYarn
	fi

	# only install yarn repo and package if not found
	cmdlog "which yarn"
	if [[ -z $(which yarn 2>>$LOGFILE) ]] ; then
		echo
		printprog "Installing yarn"
		cmdlog "curl -s -o /etc/yum.repos.d/yarn.repo https://dl.yarnpkg.com/rpm/yarn.repo && yum -y install yarn"
		curl -s -o /etc/yum.repos.d/yarn.repo https://dl.yarnpkg.com/rpm/yarn.repo >>$LOGFILE 2>&1 && \
		yum -y install yarn >>$LOGFILE 2>&1
		printok "Installing yarn"
	fi

	# only install epel-release if doesn't exist
	cmdlog "rpm -q epel-release"
	if [[ -z $(rpm -q epel-release 2>>$LOGFILE) ]] ; then
		echo
		printprog "Installing epel-repo"
		cmdlog "yum -y install epel-release"
		yum -y install epel-release >>$LOGFILE 2>&1
		printok "Installing epel-repo"
	fi

	# only install libvhdi-tools if vhdimount is not present
	cmdlog "which vhdimount"
	if [[ -z $(which vhdimount 2>>$LOGFILE) ]] ; then
		echo
		printprog "Installing libvhdi-tools from forensics repository"
		if [[ $OSVERSION == "7" ]]; then
			cmdlog "rpm -ivh https://forensics.cert.org/cert-forensics-tools-release-el7.rpm"
			rpm -ivh https://forensics.cert.org/cert-forensics-tools-release-el7.rpm >>$LOGFILE 2>&1
		fi
		if [[ $OSVERSION == "8" ]]; then
			cmdlog "rpm -ivh https://forensics.cert.org/cert-forensics-tools-release-el8.rpm"
			rpm -ivh https://forensics.cert.org/cert-forensics-tools-release-el8.rpm >>$LOGFILE 2>&1
		fi
		cmdlog "sed -i 's/enabled=1/enabled=0/g' /etc/yum.repos.d/cert-forensics-tools.repo"
		sed -i 's/enabled=1/enabled=0/g' /etc/yum.repos.d/cert-forensics-tools.repo >>$LOGFILE 2>&1
		cmdlog "yum --enablerepo=forensics install -y libvhdi-tools"
		yum --enablerepo=forensics install -y libvhdi-tools >>$LOGFILE 2>&1
		printok "Installing libvhdi-tools from forensics repository"
	fi

	echo
	printprog "Enabling and starting redis service"
	cmdlog "/bin/systemctl enable redis && /bin/systemctl start redis"
	/bin/systemctl enable redis >>$LOGFILE 2>&1  && /bin/systemctl start redis >>$LOGFILE 2>&1 || false
	printok "Enabling and starting redis service"

	echo
	printprog "Enabling and starting rpcbind service"
	cmdlog "/bin/systemctl enable rpcbind && /bin/systemctl start rpcbind"
	/bin/systemctl enable rpcbind >>$LOGFILE 2>&1 && /bin/systemctl start rpcbind >>$LOGFILE 2>&1 || false
	printok "Enabling and starting rpcbind service"

}

function InstallDependenciesDebian {

	set -euo pipefail

	trap ErrorHandling ERR INT

	# Install necessary dependencies for XO build

	if [[ $OSVERSION =~ (16|18|20) ]]; then
		echo
		printprog "OS Ubuntu so making sure universe repository is enabled"
		cmdlog "add-apt-repository universe"
		add-apt-repository universe >>$LOGFILE 2>&1
		printok "OS Ubuntu so making sure universe repository is enabled"
	fi

	echo
	printprog "Running apt-get update"
	cmdlog "apt-get update"
	apt-get update >>$LOGFILE 2>&1
	printok "Running apt-get update"

	#determine which python package is needed. Ubuntu 20 requires python2-minimal, 16 and 18 are python-minimal
	if [[ $OSVERSION == "20" ]]; then
		PYTHON="python2-minimal"
	else
		PYTHON="python-minimal"
	fi

	# install packages
	echo
	printprog "Installing build dependencies, redis server, python, git, libvhdi-utils, lvm2, nfs-common, cifs-utils, curl"
	cmdlog "apt-get install -y build-essential redis-server libpng-dev git libvhdi-utils $PYTHON lvm2 nfs-common cifs-utils curl"
	apt-get install -y build-essential redis-server libpng-dev git libvhdi-utils $PYTHON lvm2 nfs-common cifs-utils curl >>$LOGFILE 2>&1
	printok "Installing build dependencies, redis server, python, git, libvhdi-utils, lvm2, nfs-common, cifs-utils, curl"

	# Install apt-transport-https and ca-certificates because of yarn https repo url
	echo
	printprog "Installing apt-transport-https and ca-certificates packages to support https repos"
	cmdlog "apt-get install -y apt-transport-https ca-certificates"
	apt-get install -y apt-transport-https ca-certificates >>$LOGFILE 2>&1
	printok "Installing apt-transport-https and ca-certificates packages to support https repos"

	if [[ $OSVERSION == "10" ]]; then
		echo
		printprog "Debian 10, so installing gnupg also"
		cmdlog "apt-get install gnupg -y"
		apt-get install gnupg -y >>$LOGFILE 2>&1
		printok "Debian 10, so installing gnupg also"
	fi

	# install setcap for non-root port binding if missing
	cmdlog "which setcap"
	if [[ -z $(which setcap 2>>$LOGFILE) ]]; then
		echo
		printprog "Installing setcap"
		cmdlog "apt-get install -y libcap2-bin"
		apt-get install -y libcap2-bin >>$LOGFILE 2>&1
		printok "Installing setcap"
	fi


	# only run automated node install if executable not found
	cmdlog "which node"
	cmdlog "which npm"
	if [[ -z $(which node 2>>$LOGFILE) ]] || [[ -z $(which npm 2>>$LOGFILE) ]]; then
		echo
		printprog "Installing node.js"
		cmdlog "curl -sL https://deb.nodesource.com/setup_${NODEVERSION}.x | bash -"
		curl -sL https://deb.nodesource.com/setup_${NODEVERSION}.x | bash - >>$LOGFILE 2>&1
		cmdlog "apt-get install -y nodejs"
		apt-get install -y nodejs >>$LOGFILE 2>&1
		printok "Installing node.js"
	else
		UpdateNodeYarn
	fi

	# only install yarn repo and package if not found
	cmdlog "which yarn"
	if [[ -z $(which yarn 2>>$LOGFILE) ]]; then
		echo
		printprog "Installing yarn"
		cmdlog "curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | apt-key add -"
		curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | apt-key add - >>$LOGFILE 2>&1
		cmdlog "echo \"deb https://dl.yarnpkg.com/debian/ stable main\" | tee /etc/apt/sources.list.d/yarn.list"
		echo "deb https://dl.yarnpkg.com/debian/ stable main" | tee /etc/apt/sources.list.d/yarn.list >>$LOGFILE 2>&1
		cmdlog "apt-get update"
		apt-get update >>$LOGFILE 2>&1
		cmdlog "apt-get install -y yarn"
		apt-get install -y yarn >>$LOGFILE 2>&1
		printok "Installing yarn"
	fi

	echo
	printprog "Enabling and starting redis service"
	cmdlog "/bin/systemctl enable redis-server && /bin/systemctl start redis-server"
	/bin/systemctl enable redis-server >>$LOGFILE 2>&1 && /bin/systemctl start redis-server >>$LOGFILE 2>&1 || false
	printok "Enabling and starting redis service"

	echo
	printprog "Enabling and starting rpcbind service"
	cmdlog "/bin/systemctl enable rpcbind && /bin/systemctl start rpcbind"
	/bin/systemctl enable rpcbind >>$LOGFILE 2>&1 && /bin/systemctl start rpcbind >>$LOGFILE 2>&1 || false
	printok "Enabling and starting rpcbind service"

}

function UpdateNodeYarn {

	if [[ $AUTOUPDATE == "true" ]]; then

		if [ $OSNAME == "CentOS" ]; then
			echo
			printinfo "Checking current node.js version"
			NODEV=$(node -v 2>/dev/null| grep -Eo '[0-9.]+' | cut -d'.' -f1)
			if [[ -n $NODEV ]] && [[ $NODEV -lt ${NODEVERSION} ]]; then
				echo
				printprog "node.js version is $NODEV, upgrading to ${NODEVERSION}.x"
				cmdlog "curl -sL https://rpm.nodesource.com/setup_${NODEVERSION}.x | bash -"
				curl -sL https://rpm.nodesource.com/setup_${NODEVERSION}.x | bash - >>$LOGFILE 2>&1
				cmdlog "yum clean all"
				yum clean all >> $LOGFILE 2>&1
				cmdlog "yum install -y nodejs"
				yum install -y nodejs >>LOGFILE 2>&1
				printok "node.js version is $NODEV, upgrading to ${NODEVERSION}.x"
			else
				if [[ "$TASK" == "Update" ]]; then
					echo
					printprog "node.js version already on $NODEV, checking updates"
					cmdlog "yum update -y nodejs yarn"
					yum update -y nodejs yarn >>$LOGFILE 2>&1
					printok "node.js version already on $NODEV, checking updates"
				elif [[ "$TASK" == "Installation" ]]; then
					echo
					printinfo "node.js version already on $NODEV"
				fi
			fi
		else
			echo
			printinfo "Checking current node.js version"
			NODEV=$(node -v 2>/dev/null| grep -Eo '[0-9.]+' | cut -d'.' -f1)
			if [[ -n $NODEV ]] && [[ $NODEV -lt ${NODEVERSION} ]]; then
				echo
				printprog "node.js version is $NODEV, upgrading to ${NODEVERSION}.x"
				cmdlog "curl -sL https://deb.nodesource.com/setup_${NODEVERSION}.x | bash -"
				curl -sL https://deb.nodesource.com/setup_${NODEVERSION}.x | bash - >>$LOGFILE 2>&1
				cmdlog "apt-get install -y nodejs"
				apt-get install -y nodejs >>$LOGFILE 2>&1
				printok	"node.js version is $NODEV, upgrading to ${NODEVERSION}.x"
			else
				if [[ "$TASK" == "Update" ]]; then
					echo
					printprog "node.js version already on $NODEV, checking updates"
					cmdlog "apt-get install -y --only-upgrade nodejs yarn"
					apt-get install -y --only-upgrade nodejs yarn >>$LOGFILE 2>&1
					printok "node.js version already on $NODEV, checking updates"
				elif [[ "$TASK" == "Installation" ]]; then
					echo
					printinfo "node.js version already on $NODEV"
				fi
			fi
		fi
	fi
}

function InstallXOPlugins {

	set -euo pipefail

	trap ErrorHandling ERR INT

	if [[ -n "$PLUGINS" ]] && [[ "$PLUGINS" != "none" ]]; then

		if [[ "$PLUGINS" == "all" ]]; then
			echo
			printprog "Installing plugins"
			cmdlog "find \"$INSTALLDIR/xo-builds/xen-orchestra-$TIME/packages/\" -maxdepth 1 -mindepth 1 -not -name \"xo-server\" -not -name \"xo-web\" -not -name \"xo-server-cloud\" -exec ln -sn {} \"$INSTALLDIR/xo-builds/xen-orchestra-$TIME/\""
			find "$INSTALLDIR/xo-builds/xen-orchestra-$TIME/packages/" -maxdepth 1 -mindepth 1 -not -name "xo-server" -not -name "xo-web" -not -name "xo-server-cloud" -exec ln -sn {} "$INSTALLDIR/xo-builds/xen-orchestra-$TIME/packages/xo-server/node_modules/" \; >>$LOGFILE 2>&1
		else
			echo
			printprog "Installing plugins"
			local PLUGINSARRAY=($(echo "$PLUGINS" | tr ',' ' '))
				for x in "${PLUGINSARRAY[@]}"; do
				if [[ $(find $INSTALLDIR/xo-builds/xen-orchestra-$TIME/packages -type d -name "$x") ]]; then
					cmdlog "ln -sn $INSTALLDIR/xo-builds/xen-orchestra-$TIME/packages/$x $INSTALLDIR/xo-builds/xen-orchestra-$TIME/packages/xo-server/node_modules/"
					ln -sn $INSTALLDIR/xo-builds/xen-orchestra-$TIME/packages/$x $INSTALLDIR/xo-builds/xen-orchestra-$TIME/packages/xo-server/node_modules/ >>$LOGFILE 2>&1
				fi
			done
		fi

		cmdlog "cd $INSTALLDIR/xo-builds/xen-orchestra-$TIME && yarn && yarn build"
		cd $INSTALLDIR/xo-builds/xen-orchestra-$TIME && yarn >>$LOGFILE 2>&1 && yarn build >>$LOGFILE 2>&1 || false
		printok "Installing plugins"
	else
		echo
		printinfo "No plugins to install"
	fi

}

function InstallXO {

	set -euo pipefail

	trap ErrorHandling ERR INT

	# Create user if doesn't exist (if defined)

	if [[ "$XOUSER" != "root" ]]; then
		if [[ -z $(getent passwd $XOUSER) ]]; then
			echo
			printprog "Creating missing $XOUSER user"
			cmdlog "useradd -s /sbin/nologin $XOUSER"
			useradd -s /sbin/nologin $XOUSER >>$LOGFILE 2>&1
			printok "Creating missing $XOUSER user"
			sleep 2
		fi
	fi

	# Create installation directory if doesn't exist already
	if [[ ! -d "$INSTALLDIR" ]] ; then
		echo
		printprog "Creating missing basedir to $INSTALLDIR"
		cmdlog "mkdir -p \"$INSTALLDIR\""
		mkdir -p "$INSTALLDIR"
		printok "Creating missing basedir to $INSTALLDIR"
	fi

	# Create missing xo-builds directory if doesn't exist already
	if [[ ! -d "$INSTALLDIR/xo-builds" ]]; then
		echo
		printprog "Creating missing xo-builds directory to $INSTALLDIR/xo-builds"
		cmdlog "mkdir \"$INSTALLDIR/xo-builds\""
		mkdir "$INSTALLDIR/xo-builds"
		printok "Creating missing xo-builds directory to $INSTALLDIR/xo-builds"
	fi

	echo
	printinfo "Fetching Xen Orchestra source code"
	if [[ ! -d "$XO_SRC_DIR" ]]; then
		cmdlog "mkdir -p \"$XO_SRC_DIR\""
		mkdir -p "$XO_SRC_DIR"
		cmdlog "git clone \"${REPOSITORY}\" \"$XO_SRC_DIR\""
		git clone "${REPOSITORY}" "$XO_SRC_DIR" >>$LOGFILE 2>&1
	else
		cmdlog "cd \"$XO_SRC_DIR\""
		cd "$XO_SRC_DIR" >>$LOGFILE 2>&1
		cmdlog "git pull"
		git pull >>$LOGFILE 2>&1
		cd $(dirname $0) >>$LOGFILE 2>&1
		cmdlog "cd $(dirname $0)"
	fi

	# Deploy the latest xen-orchestra source to the new install directory.
	echo
	printinfo "Creating install directory: $INSTALLDIR/xo-builds/xen-orchestra-$TIME"
	cmdlog "rm -rf \"$INSTALLDIR/xo-builds/xen-orchestra-$TIME\""
	rm -rf "$INSTALLDIR/xo-builds/xen-orchestra-$TIME" >>$LOGFILE 2>&1
	cmdlog "cp -r \"$XO_SRC_DIR" "$INSTALLDIR/xo-builds/xen-orchestra-$TIME\""
	cp -r "$XO_SRC_DIR" "$INSTALLDIR/xo-builds/xen-orchestra-$TIME" >>$LOGFILE 2>&1

	if [[ "$BRANCH" == "release" ]]; then
		cmdlog "cd $INSTALLDIR/xo-builds/xen-orchestra-$TIME"
		cd $INSTALLDIR/xo-builds/xen-orchestra-$TIME
		TAG=$(git describe --tags $(git rev-list --tags --max-count=1))

		echo
		printinfo "Checking out latest tagged release '$TAG'"

		cmdlog "git checkout $TAG"
		git checkout $TAG >>$LOGFILE 2>&1
		cmdlog "cd $(dirname $0)"
		cd $(dirname $0)
	elif [[ "$BRANCH" != "master" ]]; then
		echo
		printinfo "Checking out source code from branch '$BRANCH'"

		cmdlog "cd $INSTALLDIR/xo-builds/xen-orchestra-$TIME"
		cd $INSTALLDIR/xo-builds/xen-orchestra-$TIME >>$LOGFILE 2>&1
		cmdlog "git checkout $BRANCH"
		git checkout $BRANCH >>$LOGFILE 2>&1
		cmdlog "cd $(dirname $0)"
		cd $(dirname $0) >>$LOGFILE 2>&1
	fi

	# Check if the new repo is any different from the currently-installed
	# one. If not, then skip the build and delete the repo we just cloned.

	# Get the commit ID of the to-be-installed xen-orchestra.
	cmdlog "cd $INSTALLDIR/xo-builds/xen-orchestra-$TIME"
	cd $INSTALLDIR/xo-builds/xen-orchestra-$TIME
	cmdlog "git rev-parse HEAD"
	NEW_REPO_HASH=$(git rev-parse HEAD 2>>$LOGFILE)
	cmdlog "git rev-parse --short HEAD"
	NEW_REPO_HASH_SHORT=$(git rev-parse --short HEAD 2>>$LOGFILE)
	cmdlog "cd $(dirname $0)"
	cd $(dirname $0) >>$LOGFILE 2>&1

	# Get the commit ID of the currently-installed xen-orchestra (if one
	# exists).
	if [[ -L $INSTALLDIR/xo-server ]] && [[ -n $(readlink -e $INSTALLDIR/xo-server) ]]; then
		cmdlog "cd $INSTALLDIR/xo-server"
		cd $INSTALLDIR/xo-server >>$LOGFILE 2>&1
		cmdlog "git rev-parse HEAD"
		OLD_REPO_HASH=$(git rev-parse HEAD 2>>$LOGFILE)
		cmdlog "git rev-parse --short HEAD"
		OLD_REPO_HASH_SHORT=$(git rev-parse --short HEAD 2>>$LOGFILE)
		cmdlog "cd $(dirname $0)"
		cd $(dirname $0) >>$LOGFILE 2>&1
	else
		# If there's no existing installation, then we definitely want
		# to proceed with the bulid.
		OLD_REPO_HASH=""
		OLD_REPO_HASH_SHORT=""
	fi

	# If the new install is no different from the existing install, then don't
	# proceed with the build.
	if [[ "$NEW_REPO_HASH" == "$OLD_REPO_HASH" ]] && [[ "$FORCE" != "true" ]]; then
		echo
		if [[ "$INTERACTIVE" == "true" ]]; then
			printinfo "No changes to xen-orchestra since previous install. Run update anyway?"
			read -p "[y/N]: " answer
			answer=${answer:-n}
				case $answer in
				y)
				:
				;;
				n)
				printinfo "Cleaning up install directory: $INSTALLDIR/xo-builds/xen-orchestra-$TIME"
				cmdlog "rm -rf $INSTALLDIR/xo-builds/xen-orchestra-$TIME"
				rm -rf $INSTALLDIR/xo-builds/xen-orchestra-$TIME >>$LOGFILE 2>&1
				exit 0
				;;
			esac
		else
			printinfo "No changes to xen-orchestra since previous install. Skipping xo-server and xo-web build."
			printinfo "Cleaning up install directory: $INSTALLDIR/xo-builds/xen-orchestra-$TIME"
			cmdlog "rm -rf $INSTALLDIR/xo-builds/xen-orchestra-$TIME"
			rm -rf $INSTALLDIR/xo-builds/xen-orchestra-$TIME >>$LOGFILE 2>&1
			exit 0
		fi
	fi

	# Now that we know we're going to be building a new xen-orchestra, make
	# sure there's no already-running xo-server process.
	if [[ $(pgrep -f xo-server) ]]; then
		echo
		printprog "Shutting down xo-server"
		cmdlog "/bin/systemctl stop xo-server"
		/bin/systemctl stop xo-server || { printfail "failed to stop service, exiting..." ; exit 1; }
		printok "Shutting down xo-server"
	fi

	# If this isn't a fresh install, then list the upgrade the user is making.
	if [[ -n "$OLD_REPO_HASH" ]]; then
		echo
		if [[ "$FORCE" != "true" ]]; then
			printinfo "Updating xen-orchestra from '$OLD_REPO_HASH_SHORT' to '$NEW_REPO_HASH_SHORT'"
		else
			printinfo "Updating xen-orchestra (forced) from '$OLD_REPO_HASH_SHORT' to '$NEW_REPO_HASH_SHORT'"
		fi
	else
		TASK="Installation"
	fi

	echo
	echo
	printinfo "xo-server and xo-web build takes quite a while. Grab a cup of coffee and lay back"
	echo
	printprog "Running installation"
	cmdlog "cd $INSTALLDIR/xo-builds/xen-orchestra-$TIME && yarn  && yarn build"
	cd $INSTALLDIR/xo-builds/xen-orchestra-$TIME >>$LOGFILE 2>&1 && yarn >>$LOGFILE 2>&1 && yarn build >>$LOGFILE 2>&1 || false
	printok "Running installation"

	# Install plugins
	InstallXOPlugins

	echo
	printinfo "Fixing binary path in systemd service configuration file"
	cmdlog "sed -i \"s#ExecStart=.*#ExecStart=$INSTALLDIR\/xo-server\/bin\/xo-server#\" $INSTALLDIR/xo-builds/xen-orchestra-$TIME/packages/xo-server/xo-server.service"
	sed -i "s#ExecStart=.*#ExecStart=$INSTALLDIR\/xo-server\/bin\/xo-server#" $INSTALLDIR/xo-builds/xen-orchestra-$TIME/packages/xo-server/xo-server.service
	printinfo "Adding WorkingDirectory parameter to systemd service configuration file"
	cmdlog "sed -i \"/ExecStart=.*/a WorkingDirectory=$INSTALLDIR/xo-server\" $INSTALLDIR/xo-builds/xen-orchestra-$TIME/packages/xo-server/xo-server.service"
	sed -i "/ExecStart=.*/a WorkingDirectory=$INSTALLDIR/xo-server" $INSTALLDIR/xo-builds/xen-orchestra-$TIME/packages/xo-server/xo-server.service >>$LOGFILE 2>&1

	if [[ "$XOUSER" != "root" ]]; then
		printinfo "Adding user to systemd config"
		cmdlog "sed -i \"/SyslogIdentifier=.*/a User=$XOUSER\" $INSTALLDIR/xo-builds/xen-orchestra-$TIME/packages/xo-server/xo-server.service"
		sed -i "/SyslogIdentifier=.*/a User=$XOUSER" $INSTALLDIR/xo-builds/xen-orchestra-$TIME/packages/xo-server/xo-server.service >>$LOGFILE 2>&1

		if [ "$PORT" -le "1024" ]; then
			NODEBINARY="$(which node)"
			if [[ -L "$NODEBINARY" ]]; then
				NODEBINARY="$(readlink -e $NODEBINARY)"
			fi

			if [[ -n $NODEBINARY ]]; then
				printprog "Attempting to set cap_net_bind_service permission for $NODEBINARY"
				cmdlog "setcap 'cap_net_bind_service=+ep' $NODEBINARY"
				setcap 'cap_net_bind_service=+ep' $NODEBINARY >>$LOGFILE 2>&1 \
				&& printok " Attempting to set cap_net_bind_service permission for $NODEBINARY" || { printfail "Attempting to set cap_net_bind_service permission for $NODEBINARY" ; echo "	Non-privileged user might not be able to bind to <1024 port. xo-server won't start most likely" ; }
			else
				printfail "Can't find node executable, or it's a symlink to non existing file. Not trying to setcap. xo-server won't start most likely"
			fi
		fi
	fi

        if [[ ! -f $CONFIGPATH/.config/xo-server/config.toml ]] || [[ "$CONFIGUPDATE" == "true" ]]; then

		printinfo "Fixing relative path to xo-web installation in xo-server configuration file"

		INSTALLDIRESC=$(echo $INSTALLDIR | sed 's/\//\\\//g')
		cmdlog "sed -i \"s/#'\/any\/url' = '\/path\/to\/directory'/'\/' = '$INSTALLDIRESC\/xo-web\/dist\/'/\" $INSTALLDIR/xo-builds/xen-orchestra-$TIME/packages/xo-server/sample.config.toml"
		sed -i "s/#'\/any\/url' = '\/path\/to\/directory'/'\/' = '$INSTALLDIRESC\/xo-web\/dist\/'/" $INSTALLDIR/xo-builds/xen-orchestra-$TIME/packages/xo-server/sample.config.toml >>$LOGFILE 2>&1
                sleep 2

                if [[ $PORT != "80" ]]; then
			printinfo "Changing port in xo-server configuration file"
			cmdlog "sed -i \"s/port = 80/port = $PORT/\" $INSTALLDIR/xo-builds/xen-orchestra-$TIME/packages/xo-server/sample.config.toml"
                        sed -i "s/port = 80/port = $PORT/" $INSTALLDIR/xo-builds/xen-orchestra-$TIME/packages/xo-server/sample.config.toml >>$LOGFILE 2>&1
                        sleep 2
                fi

                if [[ "$HTTPS" == "true" ]] ; then
			printinfo "Enabling HTTPS in xo-server configuration file"
			cmdlog "sed -i \"s%# cert = '.\/certificate.pem'%cert = '$PATH_TO_HTTPS_CERT'%\" $INSTALLDIR/xo-builds/xen-orchestra-$TIME/packages/xo-server/sample.config.toml"
			sed -i "s%# cert = '.\/certificate.pem'%cert = '$PATH_TO_HTTPS_CERT'%" $INSTALLDIR/xo-builds/xen-orchestra-$TIME/packages/xo-server/sample.config.toml >>$LOGFILE 2>&1
			cmdlog \"sed -i "s%# key = '.\/key.pem'%key = '$PATH_TO_HTTPS_KEY'%\" $INSTALLDIR/xo-builds/xen-orchestra-$TIME/packages/xo-server/sample.config.toml"
			sed -i "s%# key = '.\/key.pem'%key = '$PATH_TO_HTTPS_KEY'%" $INSTALLDIR/xo-builds/xen-orchestra-$TIME/packages/xo-server/sample.config.toml >>$LOGFILE 2>&1
			cmdlog "sed -i \"s/# redirectToHttps/redirectToHttps/\" $INSTALLDIR/xo-builds/xen-orchestra-$TIME/packages/xo-server/sample.config.toml" 
			sed -i "s/# redirectToHttps/redirectToHttps/" $INSTALLDIR/xo-builds/xen-orchestra-$TIME/packages/xo-server/sample.config.toml >>$LOGFILE 2>&1
			sleep 2
		fi

		printinfo "Activating modified configuration file"
		cmdlog "mkdir -p $CONFIGPATH/.config/xo-server"
		mkdir -p $CONFIGPATH/.config/xo-server
		cmdlog "mv -f $INSTALLDIR/xo-builds/xen-orchestra-$TIME/packages/xo-server/sample.config.toml $CONFIGPATH/.config/xo-server/config.toml"
                mv -f $INSTALLDIR/xo-builds/xen-orchestra-$TIME/packages/xo-server/sample.config.toml $CONFIGPATH/.config/xo-server/config.toml


        fi

	echo
	printinfo "Symlinking fresh xo-server install/update to $INSTALLDIR/xo-server"
	cmdlog "ln -sfn $INSTALLDIR/xo-builds/xen-orchestra-$TIME/packages/xo-server $INSTALLDIR/xo-server"
	ln -sfn $INSTALLDIR/xo-builds/xen-orchestra-$TIME/packages/xo-server $INSTALLDIR/xo-server >>$LOGFILE 2>&1
	sleep 2
	printinfo "Symlinking fresh xo-web install/update to $INSTALLDIR/xo-web"
	cmdlog "ln -sfn $INSTALLDIR/xo-builds/xen-orchestra-$TIME/packages/xo-web $INSTALLDIR/xo-web"
	ln -sfn $INSTALLDIR/xo-builds/xen-orchestra-$TIME/packages/xo-web $INSTALLDIR/xo-web >>$LOGFILE 2>&1

	if [[ "$XOUSER" != "root" ]]; then
		cmdlog "chown -R $XOUSER:$XOUSER $INSTALLDIR/xo-builds/xen-orchestra-$TIME"
		chown -R $XOUSER:$XOUSER $INSTALLDIR/xo-builds/xen-orchestra-$TIME >>$LOGFILE 2>&1

		if [ ! -d /var/lib/xo-server ]; then
			cmdlog "mkdir /var/lib/xo-server"
			mkdir /var/lib/xo-server >>$LOGFILE 2>&1
		fi

		cmdlog "chown -R $XOUSER:$XOUSER /var/lib/xo-server"
		chown -R $XOUSER:$XOUSER /var/lib/xo-server >>$LOGFILE 2>&1

		cmdlog "chown -R $XOUSER:$XOUSER $CONFIGPATH/.config/xo-server"
		chown -R $XOUSER:$XOUSER $CONFIGPATH/.config/xo-server >>$LOGFILE 2>&1
	fi

	# fix to prevent older installations to not update because systemd service is not symlinked anymore
	if [[ $(find /etc/systemd/system -maxdepth 1 -type l -name "xo-server.service") ]]; then
		cmdlog "rm -f /etc/systemd/system/xo-server.service"
		rm -f /etc/systemd/system/xo-server.service >>$LOGFILE 2>&1
	fi

	echo
	printinfo "Replacing systemd service configuration file"

	cmdlog "/bin/cp -f $INSTALLDIR/xo-builds/xen-orchestra-$TIME/packages/xo-server/xo-server.service /etc/systemd/system/xo-server.service"
	/bin/cp -f $INSTALLDIR/xo-builds/xen-orchestra-$TIME/packages/xo-server/xo-server.service /etc/systemd/system/xo-server.service >>$LOGFILE 2>&1
	sleep 2
	printinfo "Reloading systemd configuration"
	echo
	cmdlog "/bin/systemctl daemon-reload"
	/bin/systemctl daemon-reload >>$LOGFILE 2>&1
	sleep 2

	echo
	printinfo "Starting xo-server..."
	cmdlog "/bin/systemctl start xo-server"
	/bin/systemctl start xo-server >>$LOGFILE 2>&1

	# no need to exit/trap on errors anymore
	set +eo pipefail
	trap - ERR INT

	count=0
	limit=6
	servicestatus="$(journalctl --since "$LOGTIME" -u xo-server | grep "https\{0,1\}:\/\/.*:$PORT")"
	while [[ -z "$servicestatus" ]] && [[ "$count" -lt "$limit" ]]; do
		echo " waiting for port to be open"
		sleep 10
		servicestatus="$(journalctl --since "$LOGTIME" -u xo-server | grep "https\{0,1\}:\/\/.*:$PORT")"
		(( count++ ))
	done

	if [[ ! -z "$servicestatus" ]]; then
		echo
		echo -e "	${COLOR_GREEN}WebUI started in port $PORT. Make sure you have firewall rules in place to allow access.${COLOR_N}"
		if [[ "$TASK" == "Installation" ]]; then
			echo -e "	${COLOR_GREEN}Default username: admin@admin.net password: admin${COLOR_N}"
		fi
		echo
		printinfo "$TASK successful. Enabling xo-server service to start on reboot"
		echo "" >> $LOGFILE
		echo "$TASK succesful" >> $LOGFILE
		cmdlog "/bin/systemctl enable xo-server"
		echo
		/bin/systemctl enable xo-server >>$LOGFILE 2>&1
	else
		echo
		printfail "$TASK completed, but looks like there was a problem when starting xo-server/reading journalctl. Please see logs for more details"
		echo "" >> $LOGFILE
		echo "$TASK failed" >> $LOGFILE
		echo "xo-server service log:" >> $LOGFILE
		echo "" >> $LOGFILE
		journalctl --since "$LOGTIME" -u xo-server >> $LOGFILE
		echo
		echo "Control xo-server service with systemctl for stop/start/restart etc."
		exit 1
	fi

}


function UpdateXO {

	InstallXO

	set -euo pipefail

	if [[ "$PRESERVE" != "0" ]]; then

		# remove old builds. leave as many as defined in PRESERVE variable
		echo
		printprog "Removing old installations. Leaving $PRESERVE latest"
		cmdlog "find $INSTALLDIR/xo-builds/ -maxdepth 1 -type d -name \"xen-orchestra*\" -printf \"%T@ %p\\n\" | sort -n | cut -d' ' -f2- | head -n -$PRESERVE | xargs -r rm -r"
		find $INSTALLDIR/xo-builds/ -maxdepth 1 -type d -name "xen-orchestra*" -printf "%T@ %p\n" | sort -n | cut -d' ' -f2- | head -n -$PRESERVE | xargs -r rm -r >>$LOGFILE 2>&1
		printok "Removing old installations. Leaving $PRESERVE latest"
	else
		printinfo "PRESERVE variable is set to 0. This needs to be at least 1. Not doing a cleanup"
	fi

}

function HandleArgs {

	OPTS=$(getopt -o: --long force,rollback,update,install -- "$@")

	if [[ $? != 0 ]]; then
		echo "Usage: $(dirname $0)/$(basename $0) [--install | --update | --rollback ] [--force]"
		exit 1
	fi

	eval set -- "$OPTS"

	local UPDATEARG=0
	local INSTALLARG=0
	local ROLLBACKARG=0

	while true; do
	case "$1" in
		--force)
			shift
			FORCE="true"
			;;
		--update)
			shift
			local UPDATEARG=1
			TASK="Update"
			;;
		--install)
			shift
			local INSTALLARG=1
			TASK="Installation"
			;;
		--rollback)
			shift
			local ROLLBACKARG=1
			;;
		--)
			shift
			break
			;;
		*)
			shift
			break
			;;
		esac
	done

	if [[ "$((INSTALLARG+UPDATEARG+ROLLBACKARG))" -gt 1 ]]; then
		echo "Define either install/update or rollback"
		exit 1
	fi

	if [[ $UPDATEARG -gt 0 ]]; then
		UpdateNodeYarn
		UpdateXO
		exit
	fi

	if [[ $INSTALLARG -gt 0 ]]; then
		if [ $OSNAME == "CentOS" ]; then
			InstallDependenciesCentOS
			InstallXO
			exit
		else
			InstallDependenciesDebian
			InstallXO
			exit
		fi
	fi

	if [[ $ROLLBACKARG -gt 0 ]]; then
		RollBackInstallation
		exit
	fi

}

function RollBackInstallation {

	set -euo pipefail

	INSTALLATIONS=($(find $INSTALLDIR/xo-builds/ -maxdepth 1 -type d -name "xen-orchestra-*" 2>/dev/null))

	if [[ $(echo ${#INSTALLATIONS[@]}) -le 1 ]]; then
		printinfo "One or less installations exist, nothing to change"
		exit 0
	fi

	echo "Which installation to roll back?"
	echo
	local PS3="Pick a number. CTRL+C to exit: "
	select INSTALLATION in "${INSTALLATIONS[@]}"; do
		case $INSTALLATION in
			*xen-orchestra*)
				echo
				printinfo "Setting $INSTALLDIR/xo-server symlink to $INSTALLATION/packages/xo-server"
				cmdlog "ln -sfn $INSTALLATION/packages/xo-server $INSTALLDIR/xo-server"
				ln -sfn $INSTALLATION/packages/xo-server $INSTALLDIR/xo-server >>$LOGFILE 2>&1
				printinfo "Setting $INSTALLDIR/xo-web symlink to $INSTALLATION/packages/xo-web"
				cmdlog "ln -sfn $INSTALLATION/packages/xo-web $INSTALLDIR/xo-web" 
				ln -sfn $INSTALLATION/packages/xo-web $INSTALLDIR/xo-web >>$LOGFILE 2>&1
				echo
				printinfo "Replacing xo.server.service systemd configuration file"
				cmdlog "/bin/cp -f $INSTALLATION/packages/xo-server/xo-server.service /etc/systemd/system/xo-server.service"
				/bin/cp -f $INSTALLATION/packages/xo-server/xo-server.service /etc/systemd/system/xo-server.service >>$LOGFILE 2>&1
				cmdlog "/bin/systemctl daemon-reload"
				/bin/systemctl daemon-reload >>$LOGFILE 2>&1
				echo
				printinfo "Restarting xo-server..."
				cmdlog "/bin/systemctl restart xo-server"
				/bin/systemctl restart xo-server >>$LOGFILE 2>&1
				echo
				break
			;;
			*)
				printfail "Try again"
			;;
			esac
		done

}

function CheckOS {

	if [[ $(uname -m) != "x86_64" ]]; then
		printfail "Installation supports only x86_64. You seem to be running architecture: $(uname -m)"
		exit 1
	fi

	if [ -f /etc/centos-release ] ; then
		OSVERSION=$(grep -Eo "[0-9]" /etc/centos-release | head -1)
		OSNAME="CentOS"
		if [[ $OSVERSION != "8" ]]; then
			printfail "Only CentOS 8 supported"
			exit 1
		fi
		cmdlog "which xe"
		if [[ $(which xe 2>>$LOGFILE) ]]; then
			printfail "xe binary found, don't try to run install on xcp-ng/xenserver host. use xo-appliance.sh instead"
			exit 1
		fi
	elif [[ -f /etc/os-release ]]; then
		OSVERSION=$(grep ^VERSION_ID /etc/os-release | cut -d'=' -f2 | grep -Eo "[0-9]{1,2}" | head -1)
		OSNAME=$(grep ^NAME /etc/os-release | cut -d'=' -f2 | sed 's/"//g' | awk '{print $1}')
		if [[ $OSNAME == "Debian" ]] && [[ ! $OSVERSION =~ ^(8|9|10)$ ]]; then
			printfail "Only Debian 8/9/10 supported"
			exit 1
		elif [[ $OSNAME == "Ubuntu" ]] && [[ ! $OSVERSION =~ ^(16|18|20)$ ]]; then
			printfail "Only Ubuntu 16/18/20 supported"
			exit 1
		fi
	else
		printfail "Only CentOS 8 / Ubuntu 16/18 and Debian 8/9 supported"
		exit 1
	fi

}

function CheckSystemd {

	if [[ -z $(which systemctl) ]]; then
		printfail "This tool is designed to work with systemd enabled systems only"
		exit 1
	fi
}

function CheckCertificate {
	if [[ "$HTTPS" == "true" ]]; then
		local CERT="$(openssl x509 -modulus -noout -in "$PATH_TO_HTTPS_CERT" | openssl md5)"
		local KEY="$(openssl rsa -modulus -noout -in "$PATH_TO_HTTPS_KEY" | openssl md5)"
		if [[ "$CERT" != "$KEY" ]]; then
			echo
			printinfo "$PATH_TO_HTTPS_CERT:"
			printinfo "$CERT"
			printinfo "$PATH_TO_HTTPS_KEY:"
			printinfo "$KEY"
			echo
			printfail "MD5 of your TLS key and certificate dont match. Please check files and try again."
			exit 1
		fi
	fi

}

function CheckMemory {
	SYSMEM=$(grep MemTotal /proc/meminfo | awk '{print $2}')

	if [[ $SYSMEM -lt 3000000 ]]; then
		echo
		echo -e "${COLOR_RED}WARNING: you have less than 3GB of RAM in your system. Installation might run out of memory, continue anyway?${COLOR_N}"
		echo
		read -p "y/N: " answer
		case $answer in
			y)
				:
				;;
			n)
				exit 0
				;;
			*)
				exit 0
				;;
		esac
	fi

}

function CheckDiskFree {
	FREEDISK=$(df -P -k ${INSTALLDIR%/*} | tail -1 | awk '{print $4}')

	if [[ $FREEDISK -lt 1048576 ]]; then
		echo
		echo -e "${COLOR_RED}free disk space in ${INSTALLDIR%/*} seems to be less than 1GB. Install/update will most likely fail, continue anyway?${COLOR_N}"
		echo
		read -p "y/N: " answer
			case $answer in
			y)
				:
				;;
			n)
				exit 0
				;;
			*)
				exit 0
				;;
		esac
	fi
}

function StartUpScreen {

echo "-----------------------------------------"
echo
echo "Welcome to automated Xen Orchestra install"
echo
echo "Following options will be used for installation:"
echo
echo -e "OS: ${COLOR_WHITE}$OSNAME $OSVERSION ${COLOR_N}"
echo -e "Basedir: ${COLOR_WHITE}$INSTALLDIR ${COLOR_N}"

if [ $XOUSER ]; then
	echo -e "User: ${COLOR_WHITE}$XOUSER ${COLOR_N}"
else
	echo -e "User: ${COLOR_WHITE}root ${COLOR_N}"
fi

echo -e "Port: ${COLOR_WHITE}$PORT${COLOR_N}"
echo -e "HTTPS: ${COLOR_WHITE}${HTTPS}${COLOR_N} ${COLOR_RED}${HTTPSFAIL}${COLOR_N}"
echo -e "Git Branch for source: ${COLOR_WHITE}$BRANCH${COLOR_N}"
echo -e "Following plugins will be installed: ${COLOR_WHITE}"$PLUGINS"${COLOR_N}"
echo -e "Number of previous installations to preserve: ${COLOR_WHITE}$PRESERVE${COLOR_N}"
echo -e "Node.js and yarn auto update: ${COLOR_WHITE}$AUTOUPDATE${COLOR_N}"
echo
echo -e "Errorlog is stored to ${COLOR_WHITE}$LOGFILE${COLOR_N} for debug purposes"
echo
echo -e "Xen Orchestra configuration will be stored to ${COLOR_WHITE}$CONFIGPATH/.config/xo-server/config.toml${COLOR_N}, if you don't want it to be replaced with every update, set ${COLOR_WHITE}CONFIGUPDATE${COLOR_N} to false in ${COLOR_WHITE}xo-install.cfg${COLOR_N}"
echo "-----------------------------------------"

echo
echo -e "${COLOR_WHITE}1. Autoinstall${COLOR_N}"
echo -e "${COLOR_WHITE}2. Update / Install without packages${COLOR_N}"
echo -e "${COLOR_WHITE}3. Rollback to another existing installation${COLOR_N}"
echo -e "${COLOR_WHITE}4. Exit${COLOR_N}"
echo
read -p ": " option

		case $option in
		1)
			if [[ $(pgrep -f xo-server) ]]; then
				echo "Looks like xo-server process is already running, consider running update instead. Continue anyway?"
				read -p "[y/N]: " answer
					case $answer in
						y)
						echo "Stopping xo-server..."
						cmdlog "/bin/systemctl stop xo-server"
						/bin/systemctl stop xo-server >>$LOGFILE 2>&1 || { printfail "failed to stop service, exiting..." ; exit 1; }
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
				TASK="Installation"
				INTERACTIVE="true"
				InstallDependenciesCentOS
				InstallXO
				exit 0
			else
				TASK="Installation"
				INTERACTIVE="true"
				InstallDependenciesDebian
				InstallXO
				exit 0
			fi
		;;
		2)
			TASK="Update"
			INTERACTIVE="true"
			UpdateNodeYarn
			UpdateXO
			exit 0
		;;
		3)
			RollBackInstallation
			exit 0
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
CheckCertificate

if [[ $# != "0" ]]; then
	HandleArgs "$@"
	exit 0
else
	CheckDiskFree
	CheckMemory
	StartUpScreen
fi
