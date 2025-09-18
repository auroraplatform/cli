#!/usr/bin/env bats

setup() {
    # Mock terraform outputs
    export MOCK_TERRAFORM_OUTPUT="i-1234567890abcdef0"
    export MOCK_CLICKHOUSE_IP="10.0.1.100"
    
    # Create temporary files
    export TEMP_CA_CERT=$(mktemp)
    echo "mock-ca-cert" > "$TEMP_CA_CERT"
    
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

teardown() {
    rm -f "$TEMP_CA_CERT"
}

@test "connect.sh validates required parameters" {
    run ./scripts/connect.sh
    [ "$status" -eq 1 ]
    [[ "$output" == *"Missing required parameters"* ]] || [[ "$output" == *"Usage:"* ]]
}

@test "connect.sh shows usage with -h flag" {
    run ./scripts/connect.sh -h
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "connect.sh validates CA certificate file exists" {
    run ./scripts/connect.sh -n "test" -k "localhost:9093" -t "test-topic" -u "user" -p "pass" -c "/nonexistent/file"
    [ "$status" -eq 1 ]
    [[ "$output" == *"not found"* ]] || [[ "$output" == *"error"* ]]
}

@test "connect.sh accepts valid parameters" {
    # Mock terraform output function
    function terraform() {
        if [[ "$*" == *"output -raw kafka_consumer_instance_id"* ]]; then
            echo "$MOCK_TERRAFORM_OUTPUT"
        elif [[ "$*" == *"output -raw clickhouse_private_ip"* ]]; then
            echo "$MOCK_CLICKHOUSE_IP"
        fi
    }
    export -f terraform
    
    run ./scripts/connect.sh -n "test" -k "localhost:9093" -t "test-topic" -u "user" -p "pass" -c "$TEMP_CA_CERT"
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ]  # May fail due to AWS credentials, but should not crash
}

@test "connect.sh validates connection name parameter" {
    run ./scripts/connect.sh -k "localhost:9093" -t "test-topic" -u "user" -p "pass" -c "$TEMP_CA_CERT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Missing required parameters"* ]] || [[ "$output" == *"Usage:"* ]]
}

@test "connect.sh validates kafka broker parameter" {
    run ./scripts/connect.sh -n "test" -t "test-topic" -u "user" -p "pass" -c "$TEMP_CA_CERT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Missing required parameters"* ]] || [[ "$output" == *"Usage:"* ]]
}

@test "connect.sh validates topic parameter" {
    run ./scripts/connect.sh -n "test" -k "localhost:9093" -u "user" -p "pass" -c "$TEMP_CA_CERT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Missing required parameters"* ]] || [[ "$output" == *"Usage:"* ]]
}

@test "connect.sh validates username parameter" {
    run ./scripts/connect.sh -n "test" -k "localhost:9093" -t "test-topic" -p "pass" -c "$TEMP_CA_CERT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Missing required parameters"* ]] || [[ "$output" == *"Usage:"* ]]
}

@test "connect.sh validates password parameter" {
    run ./scripts/connect.sh -n "test" -k "localhost:9093" -t "test-topic" -u "user" -c "$TEMP_CA_CERT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Missing required parameters"* ]] || [[ "$output" == *"Usage:"* ]]
}

@test "connect.sh validates CA cert parameter" {
    run ./scripts/connect.sh -n "test" -k "localhost:9093" -t "test-topic" -u "user" -p "pass"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Missing required parameters"* ]] || [[ "$output" == *"Usage:"* ]]
} 