package test

import (
	"testing"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/gruntwork-io/terratest/modules/aws"
	"github.com/stretchr/testify/assert"
)

func TestTerraformInfrastructure(t *testing.T) {
	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "../../terraform",
		Vars: map[string]interface{}{
			"aws_region": "us-east-1",
			"instance_type": "t3.micro",
			"vpc_cidr": "10.0.0.0/16",
			"subnet_cidr": "10.0.1.0/24",
			"environment": "test",
			"project_name": "kafka-clickhouse-pipeline-test",
			"tags": map[string]string{
				"Environment": "test",
				"Project":     "kafka-clickhouse-pipeline-test",
			},
		},
	})

	defer terraform.Destroy(t, terraformOptions)
	terraform.InitAndApply(t, terraformOptions)

	// Test outputs
	kafkaConsumerIP := terraform.Output(t, terraformOptions, "kafka_consumer_public_ip")
	vpcID := terraform.Output(t, terraformOptions, "vpc_id")
	sgID := terraform.Output(t, terraformOptions, "kafka_consumer_security_group_id")

	assert.NotEmpty(t, kafkaConsumerIP)
	assert.NotEmpty(t, vpcID)
	assert.NotEmpty(t, sgID)

	// Test security groups
	// Verify security group allows SSH from management CIDR
	sg := aws.GetSecurityGroup(t, sgID, vpcID)
	assert.True(t, aws.SecurityGroupOpenToPort(t, sg, 22, "0.0.0.0/0"))
}

func TestTerraformVariables(t *testing.T) {
	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "../../terraform",
		Vars: map[string]interface{}{
			"aws_region": "us-west-2",
			"instance_type": "t3.small",
			"vpc_cidr": "172.16.0.0/16",
			"subnet_cidr": "172.16.1.0/24",
			"environment": "test",
			"project_name": "kafka-clickhouse-pipeline-test",
			"tags": map[string]string{
				"Environment": "test",
				"Project":     "kafka-clickhouse-pipeline-test",
			},
		},
	})

	defer terraform.Destroy(t, terraformOptions)
	terraform.InitAndApply(t, terraformOptions)

	// Test that different variables work correctly
	kafkaConsumerIP := terraform.Output(t, terraformOptions, "kafka_consumer_public_ip")
	assert.NotEmpty(t, kafkaConsumerIP)
}

func TestTerraformValidation(t *testing.T) {
	terraformOptions := &terraform.Options{
		TerraformDir: "../../terraform",
	}

	// Test that terraform validate passes
	terraform.Validate(t, terraformOptions)
} 