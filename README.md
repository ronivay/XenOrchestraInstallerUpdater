
# XenOrchestraInstallerUpdater - Install / Update Xen-Orchestra from sources

# In a nutshell

This repo consist of script to install and update [Xen Orchestra](https://xen-orchestra.com/#!/) and readymade files to create Docker image.

# Instructions

### script
Clone this repository and run xo-install.sh script as root

```
./install-xo.sh
```

Tool makes some checks and offers options to update/install Xen-Orchestra or deploy a container.

### docker
You can also build the docker image locally if you wish or pull it from docker hub without using the script.

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
- Debian 8
- Ubuntu 16.05

CentOS was tested without SELinux. You need to deal with labels and permissions yourself if you want to use it.

Tool makes all necessary changes required for Xen-Orchestra to run (including packages, user creation, permissions). Please evaluate script if needed.
I take no responsibility of possible damage caused by this tool.

Below is a list of packages that will be installed if missing.

```
CentOS:
- curl
- epel-release
- nodejs
- npm
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
- nodejs
- npm
- build-essential
- redis-server
- libpng-dev
- git
- python-minimal
```
