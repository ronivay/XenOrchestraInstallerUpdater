# XenOrchestraInstallerUpdater - Install / Update Xen-Orchestra from sources

## In a nutshell

This tool will will install and update [Xen Orchestra](https://xen-orchestra.com/#!/) automatically. xo-server and xo-web components are built from sources.

## Instructions

Clone this repository and run xo-install.sh script as root

Tool has been tested to work with following distros:

- CentOS 7
- Debian 8
- Ubuntu 16.05

CentOS was tested without SELinux. You need to deal with labels yourself if you want to use it.

## Notes

Tool makes all necessary changes required for Xen-Orchestra to run (including packages, user creation, permissions). Please evaluate script if needed.
I take no responsibility of possible damage caused by this tool.

Below is a list of packages that will be installed (if required) if missing.

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
- apt-transport
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
