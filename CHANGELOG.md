# Changelog

All notable changes to the Koha GOBI plugin will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [3.1.6] - 2026-04-15

### Added
- Keepalive workflow to prevent GitHub Actions from being disabled due to inactivity

### Changed
- Increased KTD `--wait-ready` timeout from 120 to 240 seconds in CI

## [3.1.5] - 2026-04-15

### Fixed
- LocalData fields now matched by Description instead of array index position,
  fixing Managing Library (LocalData4) being mapped to Internal Note when
  LocalData3 is empty ([#6](https://github.com/thekesolutions/koha-plugin-gobi/issues/6))

## [3.1.4] - 2025-08-19

### Added
- GitHub Actions CI/CD pipeline with automated testing
- Comprehensive test suite with load and unit tests
- Modern build system with error handling and verification
- Automated release process with GitHub Releases
- GitHub badges in README for CI status and releases

### Changed
- Migrated from GitLab CI to GitHub Actions
- Updated Node.js version from 12 to 22 (LTS)
- Modernized package.json with better metadata and scripts
- Enhanced gulpfile with better error handling and logging
- Improved build process with verification steps
- Updated repository URLs to GitHub

### Fixed
- Build process now includes proper error handling
- Release artifacts are properly verified before publishing
- CI pipeline includes comprehensive test coverage

## [3.1.2] - Previous Release

### Features
- GOBI integration for automated acquisitions
- Purchase order processing
- MARC record handling
- Vendor integration capabilities

### Technical Details
- Compatible with Koha LTS versions
- Plugin-based architecture
- RESTful API integration
- Configurable workflows

---

## Migration Notes

### From GitLab to GitHub

This version includes the migration from GitLab CI to GitHub Actions:

- **CI/CD**: Now uses GitHub Actions instead of GitLab CI
- **Releases**: Automated through GitHub Releases
- **Testing**: Enhanced test suite with multiple Koha version support
- **Build**: Modernized build system with better error handling

### Upgrade Instructions

1. **For Developers**:
   - Update local repository remotes to point to GitHub
   - Install updated dependencies: `npm ci`
   - Use new build commands: `npm run build`

2. **For Users**:
   - Download releases from GitHub Releases page
   - Installation process remains the same
   - Configuration is backward compatible

### Breaking Changes

None in this release. All existing configurations and data remain compatible.

---

## Support

- **Issues**: Report bugs and feature requests on [GitHub Issues](https://github.com/thekesolutions/koha-plugin-gobi/issues)
- **Documentation**: See README.md for installation and usage instructions
- **Support**: Contact [Theke Solutions](https://theke.io) for commercial support
