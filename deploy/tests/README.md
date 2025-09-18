# Framework-Specific Tests

This directory contains comprehensive tests for the Kafka-to-ClickHouse deployment project, implemented using language-appropriate testing frameworks.

## Test Structure

```
tests/
├── terraform/           # Go/Terratest tests for infrastructure
│   ├── main_test.go
│   └── go.mod
├── scripts/            # Bats tests for shell scripts
│   ├── connect_test.bats
│   ├── disconnect_test.bats
│   └── prerequisites_test.bats
├── python/             # Pytest tests for Python scripts
│   └── test_kafka_consumer.py
├── requirements.txt    # Python test dependencies
└── README.md          # This file
```

## Test Categories

### 1. Terraform Tests (`tests/terraform/`)

**Framework:** Terratest (Go)
**Purpose:** Infrastructure validation and deployment testing

**Tests:**
- ✅ Infrastructure deployment and validation
- ✅ Resource creation verification
- ✅ Security group configuration
- ✅ Variable handling
- ✅ Output validation

**Requirements:**
- Go 1.21+
- AWS credentials configured
- Terraform CLI installed

**Run Terraform Tests:**
```bash
cd tests/terraform
go mod tidy
go test -v
```

### 2. Shell Script Tests (`tests/scripts/`)

**Framework:** Bats (Bash Automated Testing System)
**Purpose:** Shell script validation and behavior testing

**Tests:**
- ✅ Parameter validation
- ✅ Error handling
- ✅ Usage documentation
- ✅ File existence checks
- ✅ Syntax validation

**Requirements:**
- Bats-core installed
- Bash shell available

**Install Bats:**
```bash
# macOS
brew install bats-core

# Ubuntu/Debian
sudo apt-get install bats

# Or install from source
git clone https://github.com/bats-core/bats-core.git
cd bats-core
sudo ./install.sh /usr/local
```

**Run Shell Script Tests:**
```bash
# Run all script tests
bats tests/scripts/

# Run specific test file
bats tests/scripts/connect_test.bats
```

### 3. Python Tests (`tests/python/`)

**Framework:** Pytest
**Purpose:** Python script validation and unit testing

**Tests:**
- ✅ Syntax validation
- ✅ Import verification
- ✅ Environment variable handling
- ✅ Error handling patterns
- ✅ Documentation checks

**Requirements:**
- Python 3.6+
- Dependencies in requirements.txt

**Run Python Tests:**
```bash
# Install dependencies
pip install -r tests/requirements.txt

# Run all Python tests
pytest tests/python/ -v

# Run specific test file
pytest tests/python/test_kafka_consumer.py -v
```

## Running All Tests

### Prerequisites Setup

1. **Install Go and dependencies:**
```bash
cd tests/terraform
go mod tidy
```

2. **Install Bats:**
```bash
# See installation instructions above
```

3. **Install Python dependencies:**
```bash
pip install -r tests/requirements.txt
```

### Run All Tests

```bash
# Terraform tests
cd tests/terraform && go test -v && cd ../..

# Shell script tests
bats tests/scripts/

# Python tests
pytest tests/python/ -v
```

## Test Output Examples

### Terraform Tests
```
=== RUN   TestTerraformInfrastructure
--- PASS: TestTerraformInfrastructure (45.23s)
=== RUN   TestTerraformVariables
--- PASS: TestTerraformVariables (38.91s)
=== RUN   TestTerraformValidation
--- PASS: TestTerraformValidation (0.12s)
PASS
```

### Bats Tests
```
 ✓ connect.sh validates required parameters
 ✓ connect.sh shows usage with -h flag
 ✓ connect.sh validates CA certificate file exists
 ✓ connect.sh accepts valid parameters
 ✓ disconnect.sh validates connection name parameter
 ✓ disconnect.sh shows usage with -h flag

6 tests, 0 failures
```

### Pytest Tests
```
tests/python/test_kafka_consumer.py::TestKafkaConsumer::test_script_exists PASSED
tests/python/test_kafka_consumer.py::TestKafkaConsumer::test_script_has_valid_syntax PASSED
tests/python/test_kafka_consumer.py::TestKafkaConsumer::test_script_has_required_imports PASSED
...

12 passed in 0.15s
```

## What These Tests Validate

### Critical Functionality
- **Infrastructure Deployment:** Actual AWS resource creation and validation
- **Script Behavior:** Real shell script execution with parameter validation
- **Code Quality:** Syntax, imports, and error handling patterns
- **Integration Points:** Cross-component validation

### Test Coverage
- **Terraform:** Infrastructure as Code validation
- **Shell Scripts:** Command-line interface and automation
- **Python:** Data processing and business logic

## Troubleshooting

### Common Issues

1. **Terraform Tests Fail:**
   - Ensure AWS credentials are configured
   - Check Terraform version compatibility
   - Verify network connectivity

2. **Bats Tests Fail:**
   - Install bats-core framework
   - Ensure scripts have proper permissions
   - Check bash syntax

3. **Python Tests Fail:**
   - Install required dependencies
   - Check Python version compatibility
   - Verify import paths

### Environment Setup

**For CI/CD:**
```yaml
# Example GitHub Actions setup
- name: Setup Go
  uses: actions/setup-go@v3
  with:
    go-version: '1.21'

- name: Setup Python
  uses: actions/setup-python@v4
  with:
    python-version: '3.9'

- name: Install Bats
  run: |
    git clone https://github.com/bats-core/bats-core.git
    cd bats-core
    sudo ./install.sh /usr/local
```

## Framework Benefits

### Terratest (Go)
- **Real Infrastructure Testing:** Actually deploys and validates AWS resources
- **Fast Execution:** Go's performance for large test suites
- **Rich Ecosystem:** Extensive AWS and Terraform testing utilities

### Bats (Bash)
- **Native Shell Testing:** Designed specifically for bash scripts
- **Real Execution:** Tests actual script behavior, not just syntax
- **Simple Setup:** Minimal dependencies, works in any bash environment

### Pytest (Python)
- **Rich Assertions:** Powerful assertion library
- **Mocking Support:** Excellent mocking capabilities for external dependencies
- **Plugin Ecosystem:** Extensive plugin support for various testing needs

## Next Steps

For advanced testing, consider adding:
- **Integration Tests:** End-to-end data flow validation
- **Performance Tests:** Load testing and performance benchmarks
- **Security Tests:** Vulnerability scanning and security validation
- **Compliance Tests:** Regulatory and policy compliance validation 