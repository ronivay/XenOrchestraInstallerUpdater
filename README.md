
# XenOrchestraInstallerUpdater - Install / Update Xen-Orchestra from sources

# In a nutshell

This repo consist of script to install and update [Xen Orchestra](https://xen-orchestra.com/#!/) and readymade files to create Docker image.

Installation is done using latest xo-server and xo-web sources. With this method Xen-Orchestra has all features unlocked which are normally available only with monthly fee.
Paid version comes with pro support and appliance and is the suggested option for larger environments. Method that this script offers comes with no support and is not the officially recommended way of using Xen-Orchestra. This is mainly intended for testing purposes and small environments which don't require support.

Xen-Orchestra is a great project and i strongly encourage you to consider the supported version of their product.

Optional plugins can be installed. They are included in XO repository, but not installed by default. Check list from [Xen Orchestra plugins](https://github.com/vatesfr/xen-orchestra/tree/master/packages) and edit xo-install.sh accordingly.

# Instructions

### script
Clone this repository, edit variables to suit your preferences from the xo-install.sh script and run it as root

```
basic functionality including menu:
./xo-install.sh

non-interactive update task (option 2):
./xo-install.sh --update

non-interactive install task (option 1):
./xo-install.sh --install

quick option to rollback (option 4):
./xo-install.sh --rollback
```

Tool makes some checks and offers options:

1. Autoinstall
 - Installs all dependencies (necessary packages and Xen-Orchestra itself)
 - Packages listed in the end of this README

2. Update / Install without dependencies
 - Updates NodeJS and Yarn packages if AUTOUPDATE variable is set to true (it is by default)
 - Installs Xen-Orchestra from latest sources (doesn't install any new packages)

3. Deploy container
 - Offers options to build container locally or pull from dockerhub

4. Rollback installation
 - Offers option to choose which installation to use from existing ones (if more than 1)

notes:

 - If you choose to install with option 2, you need to take care that required packages are already installed
 - You can change xo-server and xo-web git branch by editing xo-install.sh scripts $BRANCH variable

### docker
You can also build the docker image locally if you wish or pull it from [docker hub](https://hub.docker.com/r/ronivay/xen-orchestra/) without using the script.

```
docker build -t docker/. xen-orchestra
docker run -p 80:80 xen-orchestra
```
or
```
docker pull ronivay/xen-orchestra
docker run -p 80:80 ronivay/xen-orchestra
```

I suggest adding persistent data mounts for xo-server and redis by adding volume flags to commands above like so:

```
docker run -p 80:80 -v /path/to/xodata:/var/lib/xo-server -v /path/to/redisdata:/var/lib/redis xen-orchestra
```

## Notes

Tool has been tested to work with following distros:

- CentOS 7
- Debian 9
- Ubuntu 16.04

CentOS setup is confirmed to work with fresh minimal installation and SELinux enabled. 
Although script doesn't do any SELinux checks or modifications, so you need to take care of possible changes by yourself according to your system.

Tool makes all necessary changes required for Xen-Orchestra to run (including packages, user creation, permissions). Please evaluate script if needed.
I take no responsibility of possible damage caused by this tool.

Below is a list of packages that will be installed if missing.

```
CentOS:
- curl
- epel-release
- nodejs (v8)
- npm (v3)
- yarn
- gcc
- gcc+
- make
- openssl-devel
- redis
- libpng-devel
- python
- git

Debian/Ubuntu:
- apt-transport-https
- ca-certificates
- curl
- yarn
- nodejs (v8)
- npm (v3)
- build-essential
- redis-server
- libpng-dev
- git
- python-minimal
```
