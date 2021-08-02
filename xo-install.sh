#!/bin/bash

###########################################################################
# Title: XenOrchestraInstallerUpdater                                     #
# Author: Roni Väyrynen, Lance Fogle	                                  #
# Repository: https://github.com/OnyxFireInc/XenOrchestraInstallerUpdater #
###########################################################################

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
CONFIGPATH="/etc"
PLUGINS="${PLUGINS:-"none"}"
REPOSITORY="${REPOSITORY:-"https://github.com/vatesfr/xen-orchestra"}"

# set variables not changeable in configfile
TIME=$(date +%Y%m%d%H%M)
LOGTIME=$(date "+%Y-%m-%d %H:%M:%S")
LOGFILE="${LOGPATH}/xo-install.log-$TIME"
NODEVERSION="12"

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
		UpdateNodeYarn install
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
	
	# install fuse for non-root file system mounting
	cmdlog "which fusermount"
	if [[ -z $(which fusermount 2>>$LOGFILE) ]]; then
		echo
		printprog "Installing fuse"
		cmdlog "apt-get install -y fuse"
		apt-get install -y fuse >>$LOGFILE 2>&1
		printok "Installing fuse"
	fi

	echo
	printprog "Enabling and starting redis service"
	cmdlog "/bin/systemctl enable redis && /bin/systemctl start redis"
	/bin/systemctl enable redis >>$LOGFILE 2>&1  && /bin/systemctl start redis >>$LOGFILE 2>&1
	printok "Enabling and starting redis service"

	echo
	printprog "Enabling and starting rpcbind service"
	cmdlog "/bin/systemctl enable rpcbind && /bin/systemctl start rpcbind"
	/bin/systemctl enable rpcbind >>$LOGFILE 2>&1 && /bin/systemctl start rpcbind >>$LOGFILE 2>&1
	printok "Enabling and starting rpcbind service"

}

function InstallDependenciesDebian {

	set -euo pipefail

	trap ErrorHandling ERR INT

	# Install necessary dependencies for XO build

	if [[ $OSVERSION =~ (16|18|20) ]]; then
		printprog "OS Ubuntu so making sure universe repository is enabled"
		cmdlog "add-apt-repository universe"
		add-apt-repository universe >>$LOGFILE 2>&1
		printok "OS Ubuntu so making sure universe repository is enabled"
		echo
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
		printprog "Debian 10, so installing gnupg, ntfs-3g, and ssl-cert"
		cmdlog "apt-get install gnupg ntfs-3g ssl-cert -y"
		apt-get install gnupg ntfs-3g ssl-cert -y >>$LOGFILE 2>&1
		printok "Debian 10, so installing gnupg, ntfs-3g, and ssl-cert"
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
	
	# install sudo for non-root elevation
	cmdlog "which sudo"
	if [[ -z $(which sudo 2>>$LOGFILE) ]]; then
		echo
		printprog "Installing sudo"
		cmdlog "apt-get install -y sudo"
		apt-get install -y sudo >>$LOGFILE 2>&1
		printok "Installing sudo"
	fi
	
	# install fuse for non-root file system mounting
	cmdlog "which fusermount"
	if [[ -z $(which fusermount 2>>$LOGFILE) ]]; then
		echo
		printprog "Installing fuse"
		cmdlog "apt-get install -y fuse"
		apt-get install -y fuse >>$LOGFILE 2>&1
		printok "Installing fuse"
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
		UpdateNodeYarn install
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
	/bin/systemctl enable redis-server >>$LOGFILE 2>&1 && /bin/systemctl start redis-server >>$LOGFILE 2>&1
	printok "Enabling and starting redis service"

	echo
	printprog "Enabling and starting rpcbind service"
	cmdlog "/bin/systemctl enable rpcbind && /bin/systemctl start rpcbind"
	/bin/systemctl enable rpcbind >>$LOGFILE 2>&1 && /bin/systemctl start rpcbind >>$LOGFILE 2>&1
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
				if [[ $1 == "update" ]]; then
					echo
					printprog "node.js version already on $NODEV, checking updates"
					cmdlog "yum update -y nodejs yarn"
					yum update -y nodejs yarn >>$LOGFILE 2>&1
					printok "node.js version already on $NODEV, checking updates"
				elif [[ $1 == "install" ]]; then
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
				if [[ $1 == "update" ]]; then
					echo
					printprog "node.js version already on $NODEV, checking updates"
					cmdlog "apt-get install -y --only-upgrade nodejs yarn"
					apt-get install -y --only-upgrade nodejs yarn >>$LOGFILE 2>&1
					printok "node.js version already on $NODEV, checking updates"
				elif [[ $1 == "install" ]]; then
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
		cd $INSTALLDIR/xo-builds/xen-orchestra-$TIME && yarn >>$LOGFILE 2>&1 && yarn build >>$LOGFILE 2>&1
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
			cmdlog "useradd -s /sbin/nologin -m $XOUSER"
			useradd -s /sbin/nologin -m $XOUSER >>$LOGFILE 2>&1
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
	printprog "Fetching Xen Orchestra source code"
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
	printok "Fetching Xen Orchestra source code"

	# Deploy the latest xen-orchestra source to the new install directory.
	echo
	printprog "Creating install directory: $INSTALLDIR/xo-builds/xen-orchestra-$TIME"
	cmdlog "rm -rf \"$INSTALLDIR/xo-builds/xen-orchestra-$TIME\""
	rm -rf "$INSTALLDIR/xo-builds/xen-orchestra-$TIME" >>$LOGFILE 2>&1
	cmdlog "cp -r \"$XO_SRC_DIR" "$INSTALLDIR/xo-builds/xen-orchestra-$TIME\""
	cp -r "$XO_SRC_DIR" "$INSTALLDIR/xo-builds/xen-orchestra-$TIME" >>$LOGFILE 2>&1
	printok "Creating install directory: $INSTALLDIR/xo-builds/xen-orchestra-$TIME"

	if [[ "$BRANCH" == "release" ]]; then
		echo
		printprog "Checking out latest tagged release '$TAG'"
		cmdlog "cd $INSTALLDIR/xo-builds/xen-orchestra-$TIME"
		cd $INSTALLDIR/xo-builds/xen-orchestra-$TIME
		TAG=$(git describe --tags $(git rev-list --tags --max-count=1))
		cmdlog "git checkout $TAG"
		git checkout $TAG >>$LOGFILE 2>&1
		cmdlog "cd $(dirname $0)"
		cd $(dirname $0)
		printok "Checking out latest tagged release '$TAG'"
	elif [[ "$BRANCH" != "master" ]]; then
		echo
		printprog "Checking out source code from branch '$BRANCH'"
		cmdlog "cd $INSTALLDIR/xo-builds/xen-orchestra-$TIME"
		cd $INSTALLDIR/xo-builds/xen-orchestra-$TIME >>$LOGFILE 2>&1
		cmdlog "git checkout $BRANCH"
		git checkout $BRANCH >>$LOGFILE 2>&1
		cmdlog "cd $(dirname $0)"
		cd $(dirname $0) >>$LOGFILE 2>&1
		printok "Checking out source code from branch '$BRANCH'"
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
	if [[ "$NEW_REPO_HASH" == "$OLD_REPO_HASH" ]]; then
		echo
		printinfo "No changes to xen-orchestra since previous install. Skipping xo-server and xo-web build."
		echo
		printprog "Cleaning up install directory: $INSTALLDIR/xo-builds/xen-orchestra-$TIME"
		cmdlog "rm -rf $INSTALLDIR/xo-builds/xen-orchestra-$TIME"
		rm -rf $INSTALLDIR/xo-builds/xen-orchestra-$TIME >>$LOGFILE 2>&1
		printok "Cleaning up install directory: $INSTALLDIR/xo-builds/xen-orchestra-$TIME"
		return 0
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
		TASK="Update"
		printinfo "Updating xen-orchestra from '$OLD_REPO_HASH_SHORT' to '$NEW_REPO_HASH_SHORT'"
	else
		TASK="Installation"
	fi
	
	echo
	printprog "Removing open-source warning and banner"
	cmdlog "cd $INSTALLDIR/xo-builds/xen-orchestra-$TIME"
	cd $INSTALLDIR/xo-builds/xen-orchestra-$TIME
	cmdlog "/usr/bin/sed -i \"s/plan === 'Community'/plan === 'false'/\" packages/xo-web/src/xo-app/index.js"
	/usr/bin/sed -i "s/plan === 'Community'/plan === 'false'/" packages/xo-web/src/xo-app/index.js >/dev/null 2>&1
	cmdlog "/usr/bin/sed -i 's/+process.env.XOA_PLAN === 5/false/' packages/xo-web/src/xo-app/index.js"
	/usr/bin/sed -i 's/+process.env.XOA_PLAN === 5/false/' packages/xo-web/src/xo-app/index.js >/dev/null 2>&1
	printok "Removing open-source warning and banner"
	
	if [[ "$XOUSER" != "root" ]]; then
		
		if [[ ! -z "/usr/bin/sudo" ]]; then
			echo
			printprog "Setting use sudo option in config file"
			cmdlog "/usr/bin/sed -i 's/#useSudo = false/useSudo = true/' $INSTALLDIR/xo-builds/xen-orchestra-$TIME/packages/xo-server/sample.config.toml"
			/usr/bin/sed -i 's/#useSudo = false/useSudo = true/' $INSTALLDIR/xo-builds/xen-orchestra-$TIME/packages/xo-server/sample.config.toml
			printok "Setting use sudo option in config file"
			if [[ ! -e "/etc/sudoers.d/$XOUSER" ]]; then
				echo
				printprog "Adding permissions to sudoers file for $XOUSER"
				cmdlog "echo \"$XOUSER  ALL=NOPASSWD:/bin/mount, NOPASSWD:/bin/umount, NOPASSWD:/bin/mkdir, NOPASSWD:/bin/findmnt\" > /etc/sudoers.d/$XOUSER"
				echo "$XOUSER  ALL=NOPASSWD:/bin/mount, NOPASSWD:/bin/umount, NOPASSWD:/bin/mkdir, NOPASSWD:/bin/findmnt" > /etc/sudoers.d/$XOUSER
				printok "Adding permissions to sudoers file for $XOUSER"
			fi
		fi
	fi
	
	echo
	cmdlog "cd $(dirname $0)"
	cd $(dirname $0)
	printinfo "xo-server and xo-web build for quite a while. Grab a cup of coffee and lay back"
	echo
	printprog "Running installation"
	cmdlog "cd $INSTALLDIR/xo-builds/xen-orchestra-$TIME && yarn  && yarn build"
	cd $INSTALLDIR/xo-builds/xen-orchestra-$TIME >>$LOGFILE 2>&1 && yarn >>$LOGFILE 2>&1 && yarn build >>$LOGFILE 2>&1
	printok "Running installation"

	# Install plugins
	InstallXOPlugins

	echo
	printprog "Fixing binary path in systemd service configuration file"
	cmdlog "sed -i \"s#ExecStart=.*#ExecStart=$INSTALLDIR\/xo-server\/dist\/cli.mjs#\" $INSTALLDIR/xo-builds/xen-orchestra-$TIME/packages/xo-server/xo-server.service"
	sed -i "sed -i \"s#ExecStart=.*#ExecStart=$INSTALLDIR\/xo-server\/dist\/cli.mjs#\" $INSTALLDIR/xo-builds/xen-orchestra-$TIME/packages/xo-server/xo-server.service
	printok "Fixing binary path in systemd service configuration file"
	
	echo
	printprog "Adding WorkingDirectory parameter to systemd service configuration file"
	cmdlog "sed -i \"/ExecStart=.*/a WorkingDirectory=$INSTALLDIR/xo-server\" $INSTALLDIR/xo-builds/xen-orchestra-$TIME/packages/xo-server/xo-server.service"
	sed -i "/ExecStart=.*/a WorkingDirectory=$INSTALLDIR/xo-server" $INSTALLDIR/xo-builds/xen-orchestra-$TIME/packages/xo-server/xo-server.service >>$LOGFILE 2>&1
	printok "Adding WorkingDirectory parameter to systemd service configuration file"

	if [[ "$XOUSER" != "root" ]]; then
		echo
		printprog "Adding user to systemd config"
		cmdlog "sed -i \"/SyslogIdentifier=.*/a User=$XOUSER\" $INSTALLDIR/xo-builds/xen-orchestra-$TIME/packages/xo-server/xo-server.service"
		sed -i "/SyslogIdentifier=.*/a User=$XOUSER" $INSTALLDIR/xo-builds/xen-orchestra-$TIME/packages/xo-server/xo-server.service >>$LOGFILE 2>&1
		printok "Adding user to systemd config"

		if [ "$PORT" -le "1024" ]; then
			NODEBINARY="$(which node)"
			if [[ -L "$NODEBINARY" ]]; then
				NODEBINARY="$(readlink -e $NODEBINARY)"
			fi

			if [[ -n $NODEBINARY ]]; then
				echo
				printprog "Attempting to set cap_net_bind_service permission for $NODEBINARY"
				cmdlog "setcap 'cap_net_bind_service=+ep' $NODEBINARY"
				setcap 'cap_net_bind_service=+ep' $NODEBINARY >>$LOGFILE 2>&1 \
				&& printok "Attempting to set cap_net_bind_service permission for $NODEBINARY" || { printfail "Attempting to set cap_net_bind_service permission for $NODEBINARY" ; echo "	Non-privileged user might not be able to bind to <1024 port. xo-server won't start most likely" ; }
			else
				printfail "Can't find node executable, or it's a symlink to non existing file. Not trying to setcap. xo-server won't start most likely"
			fi
		fi		
	fi

	if [[ ! -f $CONFIGPATH/xo-server/config.toml ]] || [[ "$CONFIGUPDATE" == "true" ]]; then
		if [[ $PORT != "80" ]]; then
			echo
			printprog "Changing port in xo-server configuration file"
			cmdlog "sed -i \"s/port = 80/port = $PORT/\" $INSTALLDIR/xo-builds/xen-orchestra-$TIME/packages/xo-server/sample.config.toml"
			sed -i "s/port = 80/port = $PORT/" $INSTALLDIR/xo-builds/xen-orchestra-$TIME/packages/xo-server/sample.config.toml >>$LOGFILE 2>&1
			printok "Changing port in xo-server configuration file"
			sleep 2
		fi

		if [[ "$HTTPS" == "true" ]] ; then
			echo
			printprog "Enabling HTTPS in xo-server configuration file"
			cmdlog "sed -i \"s%# cert = '.\/certificate.pem'%cert = '$PATH_TO_HTTPS_CERT'%\" $INSTALLDIR/xo-builds/xen-orchestra-$TIME/packages/xo-server/sample.config.toml"
			sed -i "s%# cert = '.\/certificate.pem'%cert = '$PATH_TO_HTTPS_CERT'%" $INSTALLDIR/xo-builds/xen-orchestra-$TIME/packages/xo-server/sample.config.toml >>$LOGFILE 2>&1
			cmdlog \"sed -i "s%# key = '.\/key.pem'%key = '$PATH_TO_HTTPS_KEY'%\" $INSTALLDIR/xo-builds/xen-orchestra-$TIME/packages/xo-server/sample.config.toml"
			sed -i "s%# key = '.\/key.pem'%key = '$PATH_TO_HTTPS_KEY'%" $INSTALLDIR/xo-builds/xen-orchestra-$TIME/packages/xo-server/sample.config.toml >>$LOGFILE 2>&1
			cmdlog "sed -i \"s/# redirectToHttps/redirectToHttps/\" $INSTALLDIR/xo-builds/xen-orchestra-$TIME/packages/xo-server/sample.config.toml" 
			sed -i "s/# redirectToHttps/redirectToHttps/" $INSTALLDIR/xo-builds/xen-orchestra-$TIME/packages/xo-server/sample.config.toml >>$LOGFILE 2>&1
			printok "Enabling HTTPS in xo-server configuration file"
			sleep 2
		fi
		
		if [[ "$XOUSER" != "root" ]]; then
			echo
			printprog "Updating mounts dir in config file"
			cmdlog "/usr/bin/sed -i \"s%#mountsDir = '/run/xo-server/mounts'%mountsDir = '$INSTALLDIR/remotes/mounts'%\" $INSTALLDIR/xo-builds/xen-orchestra-$TIME/packages/xo-server/sample.config.toml"
			/usr/bin/sed -i "s%#mountsDir = '/run/xo-server/mounts'%mountsDir = '$INSTALLDIR/remotes/mounts'%" $INSTALLDIR/xo-builds/xen-orchestra-$TIME/packages/xo-server/sample.config.toml
			printok "Updating mounts dir in config file"			
		fi

		echo
		printprog "Activating modified configuration file"
		cmdlog "mkdir -p $CONFIGPATH/xo-server"
		mkdir -p $CONFIGPATH/xo-server
		cmdlog "mv -f $INSTALLDIR/xo-builds/xen-orchestra-$TIME/packages/xo-server/sample.config.toml $CONFIGPATH/xo-server/config.toml"
		mv -f $INSTALLDIR/xo-builds/xen-orchestra-$TIME/packages/xo-server/sample.config.toml $CONFIGPATH/xo-server/config.toml
		printok "Activating modified configuration file"
	fi

	echo
	printprog "Symlinking fresh xo-server install/update to $INSTALLDIR/xo-server"
	cmdlog "ln -sfn $INSTALLDIR/xo-builds/xen-orchestra-$TIME/packages/xo-server $INSTALLDIR/xo-server"
	ln -sfn $INSTALLDIR/xo-builds/xen-orchestra-$TIME/packages/xo-server $INSTALLDIR/xo-server >>$LOGFILE 2>&1
	printok "Symlinking fresh xo-server install/update to $INSTALLDIR/xo-server"
	sleep 2
	
	echo
	printprog "Symlinking fresh xo-web install/update to $INSTALLDIR/xo-web"
	cmdlog "ln -sfn $INSTALLDIR/xo-builds/xen-orchestra-$TIME/packages/xo-web $INSTALLDIR/xo-web"
	ln -sfn $INSTALLDIR/xo-builds/xen-orchestra-$TIME/packages/xo-web $INSTALLDIR/xo-web >>$LOGFILE 2>&1
	printok "Symlinking fresh xo-web install/update to $INSTALLDIR/xo-web"

	if [[ "$XOUSER" != "root" ]]; then
		cmdlog "chown -R $XOUSER:$XOUSER $INSTALLDIR/xo-builds/xen-orchestra-$TIME"
		chown -R $XOUSER:$XOUSER $INSTALLDIR/xo-builds/xen-orchestra-$TIME >>$LOGFILE 2>&1
		
		if [[ ! -d "$INSTALLDIR/remotes/mounts" ]] ; then
			printinfo "Creating new mounts directory and setting permissions"
			cmdlog "/usr/bin/mkdir -p $INSTALLDIR/remotes/mounts"
			/usr/bin/mkdir -p $INSTALLDIR/remotes/mounts
		fi

		if [ ! -d /var/lib/xo-server ]; then
			cmdlog "mkdir /var/lib/xo-server"
			mkdir /var/lib/xo-server >>$LOGFILE 2>&1
		fi
		
		cmdlog "/usr/bin/chown $XOUSER.$XOUSER $INSTALLDIR/remotes"
		/usr/bin/chown $XOUSER.$XOUSER $INSTALLDIR/remotes
		cmdlog "/usr/bin/chown $XOUSER.$XOUSER $INSTALLDIR/remotes/mounts"
		/usr/bin/chown $XOUSER.$XOUSER $INSTALLDIR/remotes/mounts

		cmdlog "chown -R $XOUSER:$XOUSER /var/lib/xo-server"
		chown -R $XOUSER:$XOUSER /var/lib/xo-server >>$LOGFILE 2>&1
		
		cmdlog "chown -R $XOUSER:$XOUSER $CONFIGPATH/xo-server"
		chown -R $XOUSER:$XOUSER $CONFIGPATH/xo-server >>$LOGFILE 2>&1
	fi

	# fix to prevent older installations to not update because systemd service is not symlinked anymore
	if [[ $(find /etc/systemd/system -maxdepth 1 -type l -name "xo-server.service") ]]; then
		cmdlog "rm -f /etc/systemd/system/xo-server.service"
		rm -f /etc/systemd/system/xo-server.service >>$LOGFILE 2>&1
	fi

	echo
	printprog "Replacing systemd service configuration file"
	cmdlog "/bin/cp -f $INSTALLDIR/xo-builds/xen-orchestra-$TIME/packages/xo-server/xo-server.service /etc/systemd/system/xo-server.service"
	/bin/cp -f $INSTALLDIR/xo-builds/xen-orchestra-$TIME/packages/xo-server/xo-server.service /etc/systemd/system/xo-server.service >>$LOGFILE 2>&1
	printok "Replacing systemd service configuration file"
	sleep 2
	
	echo
	printprog "Reloading systemd configuration"
	cmdlog "/bin/systemctl daemon-reload"
	/bin/systemctl daemon-reload >>$LOGFILE 2>&1
	printok "Reloading systemd configuration"
	sleep 2

	echo
	printprog "Starting xo-server"
	cmdlog "/bin/systemctl start xo-server"
	/bin/systemctl start xo-server >>$LOGFILE 2>&1
	printok "Starting xo-server"

	# no need to exit/trap on errors anymore
	set +eo pipefail
	trap - ERR INT

	count=0
	limit=6
	servicestatus="$(journalctl --since "$LOGTIME" -u xo-server | sed -n 'H; /Starting XO Server/h; ${g;p;}' | grep "https\{0,1\}:\/\/\[::\]:$PORT")"
	while [[ -z "$servicestatus" ]] && [[ "$count" -lt "$limit" ]]; do
		printinfo "Waiting for port to be open..."
		sleep 10
		servicestatus="$(journalctl --since "$LOGTIME" -u xo-server | sed -n 'H; /Starting XO Server/h; ${g;p;}' | grep "https\{0,1\}:\/\/\[::\]:$PORT")"
		(( count++ ))
	done

	if [[ ! -z "$servicestatus" ]]; then
		echo
		echo -e "	${COLOR_GREEN}WebUI started in port $PORT. Make sure you have firewall rules in place to allow access.${COLOR_N}"
		if [[ "$TASK" == "Installation" ]]; then
			echo -e "	${COLOR_GREEN}Default username: admin@admin.net password: admin${COLOR_N}"
		fi
		echo
		printinfo "$TASK successful"
		echo "" >> $LOGFILE
		echo "$TASK succesful" >> $LOGFILE
		
		echo
		printprog "Enabling xo-server service to start on reboot"
		cmdlog "/bin/systemctl enable xo-server"
		/bin/systemctl enable xo-server >>$LOGFILE 2>&1
		printok "Enabling xo-server service to start on reboot"
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

	case "$1" in
		--update)
			UpdateNodeYarn update
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
			CheckDiskFree
			CheckMemory
			StartUpScreen
			;;
		esac

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
				printprog "Setting $INSTALLDIR/xo-server symlink to $INSTALLATION/packages/xo-server"
				cmdlog "ln -sfn $INSTALLATION/packages/xo-server $INSTALLDIR/xo-server"
				ln -sfn $INSTALLATION/packages/xo-server $INSTALLDIR/xo-server >>$LOGFILE 2>&1
				printok "Setting $INSTALLDIR/xo-server symlink to $INSTALLATION/packages/xo-server"
				
				echo
				printprog "Setting $INSTALLDIR/xo-web symlink to $INSTALLATION/packages/xo-web"
				cmdlog "ln -sfn $INSTALLATION/packages/xo-web $INSTALLDIR/xo-web" 
				ln -sfn $INSTALLATION/packages/xo-web $INSTALLDIR/xo-web >>$LOGFILE 2>&1
				printok "Setting $INSTALLDIR/xo-web symlink to $INSTALLATION/packages/xo-web"
				
				echo
				printprog "Replacing xo.server.service systemd configuration file"
				cmdlog "/bin/cp -f $INSTALLATION/packages/xo-server/xo-server.service /etc/systemd/system/xo-server.service"
				/bin/cp -f $INSTALLATION/packages/xo-server/xo-server.service /etc/systemd/system/xo-server.service >>$LOGFILE 2>&1
				printok "Replacing xo.server.service systemd configuration file"
				
				echo
				printprog "Reloading systemd configuration"
				cmdlog "/bin/systemctl daemon-reload"
				/bin/systemctl daemon-reload >>$LOGFILE 2>&1
				printok "Reloading systemd configuration"
				
				echo
				printprog "Restarting xo-server"
				cmdlog "/bin/systemctl restart xo-server"
				/bin/systemctl restart xo-server >>$LOGFILE 2>&1
				printok "Restarting xo-server"
				break
			;;
			*)
				printfail "Try again"
			;;
			esac
		done

}

function CheckOS {

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
		printfail "Only CentOS 8 / Ubuntu 16/18/20 and Debian 8/9/10 supported"
		exit 1
	fi

}

function CheckSystemd {

	if [[ -z $(which systemctl) ]]; then
		printfail "This tool is designed to work with systemd enabled systems only"
		exit 1
	fi
}

function CheckDocker {

	if [[ -z $(which docker) ]]; then
		echo
		printfail "Docker needs to be installed for this to work"
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

function PullDockerImage {

	echo
	docker pull ronivay/xen-orchestra
	echo
	echo
	printinfo "Image pulled. Run container:"
	echo "	docker run -itd -p 80:80 ronivay/xen-orchestra"
	echo
	printinfo "If you want to persist xen-orchestra and redis data, use volume flags like:"
	echo "	docker run -itd -p 80:80 -v /path/to/data/xo-server:/var/lib/xo-server -v /path/to/data/redis:/var/lib/redis ronivay/xen-orchestra"

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
echo -e "Xen Orchestra configuration will be stored to ${COLOR_WHITE}$CONFIGPATH/xo-server/config.toml${COLOR_N} --- if you don't want it to be replaced with every update, set ${COLOR_WHITE}CONFIGUPDATE${COLOR_N} to false in ${COLOR_WHITE}xo-install.cfg${COLOR_N}"
echo "-----------------------------------------"

echo
echo -e "${COLOR_WHITE}1. Autoinstall${COLOR_N}"
echo -e "${COLOR_WHITE}2. Update / Install without packages${COLOR_N}"
echo -e "${COLOR_WHITE}3. Deploy docker container${COLOR_N}"
echo -e "${COLOR_WHITE}4. Rollback to another existing installation${COLOR_N}"
echo -e "${COLOR_WHITE}5. Exit${COLOR_N}"
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
			UpdateNodeYarn update
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
CheckCertificate

if [[ $# == "1" ]]; then
	HandleArgs "$1"
	exit 0
else
	CheckDiskFree
	CheckMemory
	StartUpScreen
fi
