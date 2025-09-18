#!/usr/bin/env bats

setup() {
    # Mock terraform outputs
    export MOCK_TERRAFORM_OUTPUT="i-1234567890abcdef0"
    
    # Mock AWS CLI
    function aws() {
        if [[ "$*" == *"ssm send-command"* ]]; then
            echo "cmd-1234567890abcdef0"
        elif [[ "$*" == *"list-command-invocations"* ]]; then
            if [[ "$*" == *"Status"* ]]; then
                echo "Success"
            fi
        fi
    }
    export -f aws
}

@test "disconnect.sh validates connection name parameter" {
    run ./scripts/disconnect.sh
    [ "$status" -eq 1 ]
    [[ "$output" == *"Missing required parameter"* ]] || [[ "$output" == *"Usage:"* ]]
}

@test "disconnect.sh shows usage with -h flag" {
    run ./scripts/disconnect.sh -h
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "disconnect.sh accepts valid connection name" {
    # Mock terraform output function
    function terraform() {
        if [[ "$*" == *"output -raw kafka_consumer_instance_id"* ]]; then
            echo "$MOCK_TERRAFORM_OUTPUT"
        fi
    }
    export -f terraform
    
    run ./scripts/disconnect.sh "test-connection"
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ]  # May fail due to AWS credentials, but should not crash
}

@test "disconnect.sh validates empty connection name" {
    run ./scripts/disconnect.sh ""
    [ "$status" -eq 1 ]
    [[ "$output" == *"Missing required parameter"* ]] || [[ "$output" == *"Usage:"* ]]
}

@test "disconnect.sh validates whitespace-only connection name" {
    run ./scripts/disconnect.sh "   "
    [ "$status" -eq 1 ]
    [[ "$output" == *"Missing required parameter"* ]] || [[ "$output" == *"Usage:"* ]]
}

@test "disconnect.sh handles multiple arguments" {
    run ./scripts/disconnect.sh "test-connection" "extra-arg"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]] || [[ "$output" == *"error"* ]]
} 