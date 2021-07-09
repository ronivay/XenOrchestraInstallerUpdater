# Xen Orchestra Installer / Updater

[![](https://img.shields.io/endpoint?url=https://xo-build-status.yawn.fi/builds/debian/status.json)](https://xo-build-status.yawn.fi/builds/debian/details.html) [![](https://img.shields.io/endpoint?url=https://xo-build-status.yawn.fi/builds/centos/status.json)](https://xo-build-status.yawn.fi/builds/centos/details.html) [![](https://img.shields.io/endpoint?url=https://xo-build-status.yawn.fi/builds/ubuntu/status.json)](https://xo-build-status.yawn.fi/builds/ubuntu/details.html)

[![](https://img.shields.io/endpoint?url=https://xo-appliance.yawn.fi/downloads/status.json)](https://xo-appliance.yawn.fi/downloads/image.txt)

[![](https://github.com/ronivay/XenOrchestraInstallerUpdater/actions/workflows/main.yml/badge.svg?branch=master)](https://github.com/ronivay/XenOrchestraInstallerUpdater/actions?query=workflow%3Axo-install) [![](https://github.com/ronivay/XenOrchestraInstallerUpdater/actions/workflows/lint.yml/badge.svg?branch=master)](https://github.com/ronivay/XenOrchestraInstallerUpdater/actions?query=workflow%3Alint)

Script to install/update [Xen Orchestra](https://xen-orchestra.com/#!/) and all of it's dependencies on multiple different Linux distributions. Separate script to be used on XenServer/XCP-ng host that installs a readymade appliance utilizing the same installer script.


### What is Xen Orchestra?

Xen Orchestra is a web interface used to manage XenServer/XCP-ng hosts and pools. It runs separately and one can manage multiple different virtualization environments from one single management interface. 

Xen Orchestra is developed by company called [Vates](https://vates.fr/). They offer Xen Orchestra as a turnkey appliance with different pricing models for different needs and even a free version with limited capabilities. This is the preferred and only supported method of using Xen Orchestra product as the appliance goes through QA and each of the plans come with support. I highly recommend using the official appliance if you plan on using Xen Orchestra in production environment, to support a great product and it's development now, and in the future.


### Why to use this script?

If you're a home user/enthusiast with simple environment you want to manage but can't justify the cost of Xen Orchestra appliance and don't need the support for it.

Since Xen Orchestra is open source and majority of the paid features included in the official appliance are part of the sources, one can build it themself. This [procedure](https://xen-orchestra.com/docs/from_the_sources.html) is even documented. Note that even though this method is documented, it's not supported way of using Xen Orchestra and is intended to be used only for testing purposes and not in production.

This script offers an easy way to install all dependencies, fetch source code, compile it and do all the little details for you which you'd have to do manually otherwise. Other than that, it follows the steps described in the official documentation. All source code for Xen Orchestra is by default pulled from the official [repository](https://github.com/vatesfr/xen-orchestra). 

**This script is not supported or endorsed by Xen Orchestra. Any issue you may have, please report it first to this repository.**

The very first version of this script i did purely for myself. Now i'm mainly trying to keep it up to date for others who might already rely on it frequently. My intentions are to offer an easy way for people to get into Xen Orchestra without restricted features which could potentially help this piece of software to evolve and grow.


### Preparations

First thing you need is a VM (or even a physical machine if you wish) where to install the software. This should have at least 4GB of RAM and ~1GB of free disk space. Having more CPU does speed a the build procedure a bit but isn't really a requirement. 2vCPU's on most systems are more than fine.

Supported Linux distributions and versions:

- CentOS 8
- AlmaLinux 8
- Rocky Linux 8
- Debian 10
- Debian 9
- Debian 8
- Ubuntu 20.04
- Ubuntu 18.04
- Ubuntu 16.04

I suggest using a fresh OS installation and not to use the VM for anything else besides Xen Orchestra.

If you plan on using the prebuilt appliance VM for XenServer/XCP-ng, see the appliance section below.

### Installation

Start by cloning this repository to the machine you wish to install to.

There is a file called `sample.xo-install.cfg` which you should copy as `xo-install.cfg`. This file holds some editable configuration settings you might want to change depending on your needs.

When done editing configuration, just run the script with root privileges:
```
sudo ./xo-install.sh
```

There are few options you can choose from:

* `Install`

install all dependencies, necessary configuration and xen orchestra itself
* `Update`

update existing installation to the newest version available
* `Rollback`

should be self explanatory. if you wish to rollback to another installation after doing update or whatever

Each of these options can be run non interactively like so:

```
sudo ./xo-install.sh --install
sudo ./xo install.sh --update [--force]
sudo ./xo-install.sh --rollback
```

As mentioned before, Xen Orchestra has some external dependencies from different operating system packages. All listed below will be installed if missing:

```
rpm:
- curl
- epel-release
- nodejs (v14)
- npm (v3)
- yarn
- gcc
- gcc+
- make
- openssl-devel
- redis
- libpng-devel
- python3
- git
- nfs-utils
- libvhdi-tools
- cifs-utils
- lvm2

deb:
- apt-transport-https
- ca-certificates
- libcap2-bin
- curl
- yarn
- nodejs (v14)
- npm (v3)
- build-essential
- redis-server
- libpng-dev
- git
- python-minimal
- python2-minimal (Ubuntu 20 only, replaces python-minimal)
- libvhdi-utils
- lvm2
- nfs-common
- cifs-utils
- gnupg (debian 10)
```

### Appliance

If you need to import an appliance directly to your host, you may use xo-appliance.sh script for this. It'll download a prebuilt Debian 10 image which has Xen Orchestra and XenOrchestraInstallerUpdater installed.

Details of appliance build process [here](https://github.com/ronivay/xen-orchestra-appliance)

Run on your Xenserver/XCP-ng host with root privileges:

```
sudo bash -c "$(curl -s https://raw.githubusercontent.com/ronivay/XenOrchestraInstallerUpdater/master/xo-appliance.sh)"
```

Default username for UI is admin@admin.net with password admin

SSH is accessible with username xo with password xopass

Remember to change both passwords before putting the VM to actual use.

Xen Orchestra is installed to /opt/xo, it uses self-signed certificates from /opt/ssl which you can replace if you wish. Installation script is at /opt/XenOrchestraInstallerUpdater which you can use to update existing installation in the future.

xo-server runs as a systemd service.

xo user has full sudo access. Xen Orchestra updates etc should be ran with sudo.

This image is updated weekly. Latest build date and MD5 checksum can be checked from [here](https://xo-appliance.yawn.fi/downloads/image.txt)

Built and tested on XCP-ng 7.x

### Tests and appliance image

I run my own little implementation of automation consisting of ansible and virtual machines to test the installation on regular bases with CentOS 8, Ubuntu 20 and Debian 10. Test results are visible in badges on top of this readme.

Appliance image is also built by me and distributed from webservers i maintain.

### Contributing

Pull requests and issues (either real issues or just suggestions) are more than welcome. Note that i do not wish to make any modifications to Xen Orchestra source code as part of this script. 
