# Gobi Plugin Tests

This directory contains the test suite for the Koha Gobi plugin.

## Test Structure

### Unit Tests

- **`00-load.t`** - Load test that verifies all plugin modules can be loaded without errors
- **`01-plugin-methods.t`** - Basic plugin functionality and method availability tests

### Running Tests

#### Local Development
```bash
# In the plugin directory
prove -v -r -s t/
```

#### With KTD (Koha Testing Docker)
```bash
# From KTD environment
cd /kohadevbox/plugins/koha-plugin-gobi
export PERL5LIB=$PERL5LIB:Koha/Plugin/Com/Theke/GOBI/lib:.
prove -v -r -s t/
```

#### GitHub Actions
Tests are automatically run on:
- Every push to any branch
- Every pull request to main branch
- Daily scheduled runs (6 AM UTC)
- Against multiple Koha versions (main, stable, oldstable)

## Test Coverage

The current test suite covers:

### Load Testing
- ✅ Module loading verification
- ✅ Syntax checking
- ✅ Dependency validation

### Plugin Methods
- ✅ Plugin instantiation
- ✅ Metadata validation
- ✅ Core plugin methods (install, upgrade, uninstall)
- ✅ Configuration methods
- ✅ API methods
- ✅ Hook methods (placeholder)

### Future Test Areas

Areas that should be expanded:

- **Purchase Order Processing** - Test GOBI order handling
- **MARC Record Processing** - Test bibliographic record creation
- **Vendor Integration** - Test GOBI API interactions
- **Configuration Validation** - Test plugin settings
- **Error Handling** - Test exception scenarios
- **Database Operations** - Test data persistence

## Adding New Tests

When adding new tests:

1. **Follow naming convention**: `##-description.t`
2. **Include proper headers** with license information
3. **Use transactions** for database tests to avoid side effects
4. **Add documentation** for complex test scenarios
5. **Update this README** when adding new test categories

## Test Dependencies

Tests require:
- **Koha testing environment** (KTD recommended)
- **Test::More** - Core testing framework
- **Test::MockModule** - For mocking dependencies
- **Koha::Database** - For database transactions

## Continuous Integration

The GitHub Actions workflow:
- Runs tests against multiple Koha versions
- Provides detailed failure reporting
- Includes log output for debugging
- Automatically cleans up test environments

See `.github/workflows/main.yml` for complete CI configuration.
