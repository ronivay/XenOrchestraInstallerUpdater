# Fedora Support for XenOrchestraInstallerUpdater

This fork adds support for Fedora 40, 41, 42, and rawhide to the XenOrchestraInstallerUpdater script.

## Changes Made

### 1. Added Fedora to Supported Operating Systems
- Modified OS detection to recognize Fedora
- Added version checks for Fedora 40, 41, 42, and rawhide
- Special handling for Fedora Rawhide (rolling release)

### 2. Fixed Package Management for Fedora
- **Valkey vs Redis**: Correctly detects that Fedora 40+ uses valkey instead of redis
- **EPEL Repository**: Skips EPEL installation as it's not needed on Fedora
- **libvhdi**: Provides information about libvhdi availability (currently not in Fedora repos)

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

1. **Yarn Installation**: The script will automatically configure the Yarn repository and install it, as it's not available in Fedora base repos.

2. **Node.js**: Fedora 42 includes Node.js 22 in the base repository, which matches XO requirements.

3. **libvhdi**: Currently not available in Fedora repositories. The script will skip this and inform you that XO will work without it, but some VHD operations may be limited.

## Known Limitations

- libvhdi-tools is not available from COPR for Fedora (only EPEL)
- Some VHD operations may be limited without libvhdi

## Future Improvements

- [ ] Create COPR repository for libvhdi on Fedora
- [ ] Add support for more Fedora versions as they're released
- [ ] Improve rawhide handling for better stability

## Testing Status

| Fedora Version | Status | Notes |
|---------------|--------|-------|
| Fedora 40 | ✅ Supported | Uses valkey |
| Fedora 41 | ✅ Supported | Uses valkey |
| Fedora 42 | ✅ Tested | Current stable, uses valkey |
| Fedora Rawhide | ✅ Supported | Development version, uses valkey |

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