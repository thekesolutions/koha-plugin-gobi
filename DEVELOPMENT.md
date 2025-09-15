# Technical Reference

## Document Purpose
This document serves as a technical reference for AI assistants working on the Koha GOBI plugin. It contains essential information about the plugin's architecture, build system, and development workflow.

## Plugin Overview

### Basic Information
- **Plugin Name**: Koha GOBI Integration Plugin
- **Version**: 3.1.4 (as of 2025-08-19)
- **Main Class**: `Koha::Plugin::Com::Theke::GOBI`
- **Plugin File**: `Koha/Plugin/Com/Theke/GOBI.pm`
- **Repository**: https://github.com/thekesolutions/koha-plugin-gobi
- **License**: GPL-3.0-or-later

### Purpose
Integrates Koha with GOBI Library Solutions from EBSCO for automated acquisitions workflow. Processes purchase orders and creates corresponding records in Koha.

## Architecture

### Directory Structure
```
koha-plugin-gobi/
├── .github/workflows/main.yml    # GitHub Actions CI/CD
├── Koha/Plugin/Com/Theke/        # Main plugin code
│   └── GOBI.pm                   # Primary plugin file
├── t/                            # Test suite
│   ├── 00-load.t                # Load test
│   ├── 01-plugin-methods.t      # Unit tests
│   └── README.md                # Test documentation
├── tools/                       # Plugin tools
├── sample_data/                 # Sample data files
├── gulpfile.js                  # Build system
├── package.json                 # Node.js configuration
├── CHANGELOG.md                 # Version history
└── README.md                    # Main documentation
```

### Key Components
1. **Purchase Order Processing** - Handles GOBI messages
2. **MARC Record Integration** - Processes bibliographic records
3. **Basket Management** - Creates and manages acquisition baskets
4. **Item Creation** - Generates items based on quantity
5. **Order Management** - Links items to orders

## Build System

### Technology Stack
- **Node.js**: 22 LTS (minimum 18.0.0)
- **Build Tool**: Gulp 5.0.0
- **Package Manager**: npm (minimum 8.0.0)
- **Archive Format**: KPZ (Koha Plugin Zip)

### Build Process
1. **Static Processing** - Handles static file endpoints (currently none)
2. **File Copying** - Copies plugin files to dist directory
3. **Date Updates** - Updates plugin date stamps
4. **Archive Creation** - Creates KPZ file with proper structure
5. **Verification** - Validates build output

### NPM Scripts
- `npm run build` - Full build process
- `npm run test` - Run all tests
- `npm run clean` - Remove build artifacts
- `npm run dev` - Development build
- `npm run kpz` - Output KPZ filename
- `npm run print-name` - Output plugin name

### Important Note: NPM Script Differences
The GOBI plugin uses `print-name` instead of `name` for the plugin name script, unlike other plugins that use `name`. This is critical for CI/CD compatibility.

## CI/CD Pipeline

### GitHub Actions Workflow
- **File**: `.github/workflows/main.yml`
- **Triggers**: Push, PR to main, daily schedule, version tags
- **Jobs**: unit_tests, release

### Testing Matrix
Tests against multiple Koha versions:
- `main` - Development branch
- `stable` - Current stable release
- `oldstable` - Previous stable release

### Test Environment
- **KTD**: Koha Testing Docker
- **Container Name**: `gobitest`
- **Test Command**: `prove -v -r -s t/`
- **PERL5LIB**: Includes plugin lib directory

### Release Process
1. **Trigger**: Git tag starting with 'v' (e.g., v3.1.4)
2. **Build**: Node.js 22 setup, npm ci, build execution
3. **Verification**: File existence and content validation
4. **Release**: GitHub Releases with KPZ and CHANGELOG.md

## Development Workflow

### Local Development
```bash
# Install dependencies
npm ci

# Run tests
npm test

# Build plugin
npm run build

# Clean artifacts
npm run clean
```

### Version Management
```bash
# Update version in package.json and plugin file
npm version patch|minor|major

# The preversion script automatically updates GOBI.pm
```

### Testing
```bash
# Load test only
npm run test:load

# Unit tests only
npm run test:unit

# All tests
npm test
```

## Plugin-Specific Details

### Main Plugin Class Methods
- `new()` - Constructor
- `install()` - Plugin installation
- `upgrade()` - Plugin upgrade
- `uninstall()` - Plugin removal
- `configure()` - Configuration interface
- `tool()` - Plugin tools
- `api_routes()` - API endpoint definitions
- `api_namespace()` - API namespace

### Configuration
Plugin stores configuration data using Koha's plugin data storage system. Configuration includes vendor settings, basket preferences, and processing options.

### API Integration
Provides RESTful API endpoints for GOBI integration. Endpoints handle purchase order reception and processing.

## Common Issues and Solutions

### Build Issues
- **KPZ not created**: Check gulpfile.js build process, verify file permissions
- **Missing files in KPZ**: Ensure additionalFiles array includes required files
- **Date update fails**: Check sed command compatibility with file format

### CI/CD Issues
- **Test failures**: Check KTD setup, verify PERL5LIB includes plugin lib
- **Release failures**: Verify tag format (v*), check GitHub token permissions
- **Build verification fails**: Ensure main plugin file exists in KPZ

### NPM Script Issues
- **Wrong filename**: Remember GOBI uses `print-name`, not `name`
- **Version mismatch**: Ensure package.json and plugin file versions match
- **Build command fails**: Check gulp installation and gulpfile.js syntax

## Migration History

### GitLab to GitHub (v3.1.4)
- **Date**: 2025-08-19
- **Changes**: Complete CI/CD migration, modernized build system
- **Breaking Changes**: None (backward compatible)
- **New Features**: GitHub Actions, comprehensive testing, automated releases

### Key Migration Decisions
1. **No keep-alive workflow** - Removed automated empty commits
2. **Multi-version testing** - Tests against main, stable, oldstable
3. **Modern Node.js** - Updated from 12 to 22 LTS
4. **Enhanced build system** - Added error handling and verification

## Future Considerations

### Potential Improvements
1. **Linting** - Add ESLint or similar for code quality
2. **Code Coverage** - Implement test coverage reporting
3. **Documentation** - Add JSDoc comments for better API documentation
4. **Performance** - Optimize build process for larger plugins

### Maintenance Notes
1. **Node.js Updates** - Monitor LTS releases, update engines in package.json
2. **Dependency Updates** - Regular npm audit and updates
3. **Koha Compatibility** - Test against new Koha releases
4. **GitHub Actions** - Monitor for action updates and security patches

## Contact Information
- **Maintainer**: Tomás Cohen Arazi <tomascohen@theke.io>
- **Organization**: Theke Solutions (https://theke.io)
- **Support**: https://theke.io/support
- **Issues**: https://github.com/thekesolutions/koha-plugin-gobi/issues

---

*This document was created on 2025-08-19 for AI assistant reference. Update as needed when making significant changes to the plugin architecture or workflow.*
