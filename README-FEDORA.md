# Fedora Support for XenOrchestraInstallerUpdater

**⚠️ IMPORTANT: Xen Orchestra does not officially support Fedora. This is an experimental implementation.**

This fork adds experimental support for Fedora 41, 42, 43, and rawhide to the XenOrchestraInstallerUpdater script.

## Changes Made

### 1. Added Fedora to Supported Operating Systems
- Modified OS detection to recognize Fedora
- Added version checks for Fedora 41, 42, 43, and rawhide
- Special handling for Fedora Rawhide (rolling release)

### 2. Fixed Package Management for Fedora
- **Valkey vs Redis**: Correctly detects that Fedora 41+ uses valkey instead of redis
- **EPEL Repository**: Skips EPEL installation as it's not needed on Fedora
- **libvhdi**: Automatically installs from reversejames/libvhdi COPR repository for Fedora

### 3. Tested Configurations
- Fedora 42 (current stable)
- Fedora rawhide (development version)

## Installation on Fedora

### Prerequisites

```bash
# Ensure system is up to date
sudo dnf update -y

# Install git if not present
sudo dnf install -y git
```

### Using the Modified Script

```bash
# Clone this fork
git clone https://github.com/YOUR_USERNAME/XenOrchestraInstallerUpdater
cd XenOrchestraInstallerUpdater

# Run installation
sudo bash xo-install.sh
```

### Manual Installation Steps

If you prefer to run the installation with specific options:

```bash
# Fresh installation
sudo bash xo-install.sh --install

# Update existing installation
sudo bash xo-install.sh --update

# Rollback to previous version
sudo bash xo-install.sh --rollback
```

## Configuration

The script uses the same configuration file (`xo-install.cfg`) as the original. 

### Fedora-Specific Notes

1. **Yarn Installation**: The script installs Fedora's native `yarnpkg` package instead of using external repositories. This follows Fedora packaging best practices and avoids third-party dependencies.

2. **Node.js**: Fedora includes recent Node.js versions in the base repository, which should match XO requirements.

3. **Package Differences**: Unlike RHEL-based systems which use Yarn's official repository, Fedora uses its native `yarnpkg` package to follow distribution packaging guidelines.

3. **libvhdi**: Automatically installed from the reversejames/libvhdi COPR repository. This provides full VHD operation support.

## Known Limitations

- **Unofficial Support**: Xen Orchestra does not officially support Fedora
- **Experimental Status**: This installation may encounter unexpected issues
- libvhdi-tools is installed from reversejames/libvhdi COPR repository
- Uses Fedora's `yarnpkg` package instead of upstream yarn

## Future Improvements

- [x] COPR repository for libvhdi on Fedora (reversejames/libvhdi)
- [ ] Add support for more Fedora versions as they're released
- [ ] Improve rawhide handling for better stability

## Testing Status

| Fedora Version | Status | Notes |
|---------------|--------|-------|
| Fedora 41 | ✅ Supported | Uses valkey, libvhdi from COPR |
| Fedora 42 | ✅ Tested | Current stable, uses valkey, libvhdi from COPR |
| Fedora 43 | ✅ Supported | Uses valkey, libvhdi from COPR |
| Fedora Rawhide | ✅ Supported | Development version, uses valkey, libvhdi from COPR |

## Contributing

To contribute to Fedora support:

1. Fork this repository
2. Test on your Fedora version
3. Submit issues for any problems
4. Create pull requests with fixes

## Pull Request Status

- [ ] PR submitted to upstream repository
- [ ] Waiting for review
- [ ] Merged

## Contact

For issues specific to Fedora support, please open an issue in this fork.

For general XenOrchestraInstallerUpdater issues, see the [original repository](https://github.com/ronivay/XenOrchestraInstallerUpdater).