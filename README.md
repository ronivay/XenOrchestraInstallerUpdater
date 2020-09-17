
# XenOrchestraInstallerUpdater - Install / Update Xen-Orchestra from sources

# In a nutshell

This repo consist of script to install and update [Xen Orchestra](https://xen-orchestra.com/#!/) for CentOS 8/Ubuntu 18/Debian 10. If you find it difficult to create a VM on your fresh Xenserver/XCP-ng installation, take a look at the appliance method from the end of this README.

Installation is done using latest xo-server and xo-web sources by default. With this method Xen-Orchestra has all features unlocked which are normally available only with monthly fee.

Optional plugins are available and all of them will be installed by default by this script. If you need only specific ones, check list from [Xen Orchestra plugins](https://github.com/vatesfr/xen-orchestra/tree/master/packages) and edit xo-install.cfg accordingly.

Xen-Orchestra is a great project and i strongly encourage you to consider the supported version of their product.

Paid version comes with pro support and appliance and is the suggested option for larger environments. Method that this script offers comes with no support and is not the officially recommended way of using Xen-Orchestra. This is mainly intended for testing purposes and small environments which don't require support.


# Instructions

### platform

Suggested platform is a VM with fresh install of any of the supported OS. You should put at least 3GB of RAM to the machine, but preferably 2vCPU/4GB RAM. Otherwise you may encounter OOM error during installation because of running out of memory.

### script
Clone this repository, copy sample.xo-install.cfg as xo-install.cfg and edit variables to suit your preferences and run xo-install.sh as root. Sample configuration will be copied as xo-install.cfg
 if doesn't exist
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
 - Installs all dependencies (necessary packages and Xen-Orchestra itself). Doesn't do firewall changes, so make sure you allow access to port specified in xo-install.cfg.
 - Packages listed in the end of this README

2. Update / Install without dependencies
 - Updates NodeJS and Yarn packages if AUTOUPDATE variable is set to true (it is by default)
 - Installs Xen-Orchestra from latest sources (doesn't install any new packages)

3. Deploy container
 - Offers options to pull ready docker image from dockerhub, also maintained by me

4. Rollback installation
 - Offers option to choose which installation to use from existing ones (if more than 1)

notes:

 - If you choose to install with option 2, you need to take care that required packages are already installed
 - You can change xo-server and xo-web git branch/tag by editing xo-install.cfg $BRANCH variable

## Notes

Tool has been tested to work with following distros:

- CentOS 8 (note LVM file level restore issue from below)
- Debian 10
- Ubuntu 18.04

Installation works but not tested frequently:
- CentOS 7
- Debian 8
- Debian 9
- Ubuntu 16.04
- Ubuntu 20.04

In order to use file level restore from delta backups, the service needs to be ran as root.
CentOS installation is currently not able to do file level restore if the backed up disk contains LVM or only sees some of the partitions.

CentOS setup is confirmed to work with fresh minimal installation and SELinux enabled.
Although script doesn't do any SELinux checks or modifications, so you need to take care of possible changes by yourself according to your system.

Tool makes all necessary changes required for Xen-Orchestra to run (including packages, user creation, permissions). Please evaluate script if needed.
I take no responsibility of possible damage caused by this tool.

Below is a list of packages that will be installed if missing.

```
CentOS:
- curl
- epel-release
- nodejs (v12)
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
- nfs-utils
- libvhdi-tools
- cifs-utils
- lvm2

Debian/Ubuntu:
- apt-transport-https
- ca-certificates
- libcap2-bin
- curl
- yarn
- nodejs (v12) (possible debian 10 default nodejs v10 will be replaced)
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

# Appliance

If you need to import an appliance directly to your host, you may use xo-appliance.sh script for this. It'll download a prebuilt image which has Xen Orchestra and XenOrchestraInstallerUpdater installed.

Run on your Xenserver/XCP-ng host as root:

```
bash -c "$(curl https://raw.githubusercontent.com/ronivay/XenOrchestraInstallerUpdater/master/xo-appliance.sh)"
```

Default username for UI is admin@admin.net with password admin

SSH is accessible with username xo with password xopass

Remember to change both password before putting the VM to actual use.

Xen Orchestra is installed to /opt/xo, it uses self-signed certificates from /opt/ssl which you can replace if you wish. Installation script is at /opt/XenOrchestraInstallerUpdater which you can use to update existing installation in the future.

This image is updated weekly. Latest build date and MD5 checksum can be checked from https://xo-appliance.yawn.fi/downloads/image.txt

