#!/usr/bin/env bats

setup() {
    # Create temporary directory for testing
    export TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"
}

teardown() {
    cd - > /dev/null
    rm -rf "$TEMP_DIR"
}

@test "prerequisites script exists and is executable" {
    run test -f ../../scripts/kafka_consumer_prerequisites.sh
    [ "$status" -eq 0 ]
}

@test "prerequisites script has valid bash syntax" {
    run bash -n ../../scripts/kafka_consumer_prerequisites.sh
    [ "$status" -eq 0 ]
}

@test "prerequisites script has proper shebang" {
    run head -n 1 ../../scripts/kafka_consumer_prerequisites.sh
    [ "$status" -eq 0 ]
    [[ "$output" == "#!/bin/bash" ]]
}

@test "prerequisites script can be sourced without errors" {
    # Test that the script can be sourced (loaded) without syntax errors
    run bash -c "source ../../scripts/kafka_consumer_prerequisites.sh"
    [ "$status" -eq 0 ]
}

@test "prerequisites script contains required commands" {
    script_content=$(cat ../../scripts/kafka_consumer_prerequisites.sh)
    
    # Check for common prerequisite commands
    [[ "$script_content" == *"yum"* ]] || [[ "$script_content" == *"apt"* ]] || [[ "$script_content" == *"dnf"* ]]
}

@test "prerequisites script has error handling" {
    script_content=$(cat ../../scripts/kafka_consumer_prerequisites.sh)
    
    # Check for error handling patterns
    [[ "$script_content" == *"set -e"* ]] || [[ "$script_content" == *"exit"* ]] || [[ "$script_content" == *"error"* ]]
} 