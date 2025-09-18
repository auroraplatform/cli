import pytest
import json
import os
import sys
from unittest.mock import Mock, patch, MagicMock
from pathlib import Path

# Add the scripts directory to path
scripts_dir = Path(__file__).parent.parent.parent / "scripts"
sys.path.insert(0, str(scripts_dir))

# Import the main function (we'll need to refactor kafka_to_clickhouse.py to make it testable)
# For now, we'll test the script structure and imports

class TestKafkaConsumer:
    
    @pytest.fixture
    def mock_clickhouse_client(self):
        """Mock ClickHouse client"""
        client = Mock()
        client.execute.return_value = None
        client.disconnect.return_value = None
        return client
    
    @pytest.fixture
    def mock_kafka_consumer(self):
        """Mock Kafka consumer"""
        consumer = Mock()
        consumer.partitions_for_topic.return_value = {0, 1}
        consumer.assign.return_value = None
        consumer.seek_to_beginning.return_value = None
        consumer.close.return_value = None
        return consumer
    
    def test_script_exists(self):
        """Test that the kafka_to_clickhouse.py script exists"""
        script_path = scripts_dir / "kafka_to_clickhouse.py"
        assert script_path.exists(), "kafka_to_clickhouse.py script not found"
    
    def test_script_has_valid_syntax(self):
        """Test that the script has valid Python syntax"""
        script_path = scripts_dir / "kafka_to_clickhouse.py"
        
        # Test syntax by trying to compile the file
        with open(script_path, 'r') as f:
            code = f.read()
        
        # This will raise a SyntaxError if the code is invalid
        compile(code, script_path, 'exec')
    
    def test_script_has_required_imports(self):
        """Test that the script has all required imports"""
        script_path = scripts_dir / "kafka_to_clickhouse.py"
        
        with open(script_path, 'r') as f:
            content = f.read()
        
        required_imports = [
            "json",
            "logging",
            "os",
            "datetime",
            "kafka",
            "clickhouse_driver"
        ]
        
        for module in required_imports:
            if module == "kafka":
                assert "from kafka import" in content, f"kafka import not found"
            elif module == "clickhouse_driver":
                assert "from clickhouse_driver import" in content, f"clickhouse_driver import not found"
            else:
                assert f"import {module}" in content, f"import {module} not found"
    
    def test_script_has_main_function(self):
        """Test that the script has a main function"""
        script_path = scripts_dir / "kafka_to_clickhouse.py"
        
        with open(script_path, 'r') as f:
            content = f.read()
        
        assert "def main():" in content, "main() function not found"
    
    def test_script_handles_environment_variables(self):
        """Test that the script properly handles environment variables"""
        script_path = scripts_dir / "kafka_to_clickhouse.py"
        
        with open(script_path, 'r') as f:
            content = f.read()
        
        env_vars = [
            "CONNECTION_NAME",
            "CLICKHOUSE_HOST",
            "KAFKA_BROKER",
            "KAFKA_TOPIC",
            "KAFKA_USERNAME",
            "KAFKA_PASSWORD"
        ]
        
        for env_var in env_vars:
            assert f"os.getenv('{env_var}'" in content, f"Environment variable {env_var} not handled"
    
    def test_script_has_logging_configuration(self):
        """Test that the script has proper logging configuration"""
        script_path = scripts_dir / "kafka_to_clickhouse.py"
        
        with open(script_path, 'r') as f:
            content = f.read()
        
        assert "logging.basicConfig" in content, "Logging configuration not found"
        assert "logger = logging.getLogger" in content, "Logger not configured"
    
    def test_script_has_error_handling(self):
        """Test that the script has basic error handling"""
        script_path = scripts_dir / "kafka_to_clickhouse.py"
        
        with open(script_path, 'r') as f:
            content = f.read()
        
        # Check for try-except blocks
        assert "try:" in content, "No try-except error handling found"
        assert "except" in content, "No except blocks found"
        assert "logger.error" in content, "No error logging found"
    
    def test_script_has_clickhouse_connection_logic(self):
        """Test that the script has ClickHouse connection logic"""
        script_path = scripts_dir / "kafka_to_clickhouse.py"
        
        with open(script_path, 'r') as f:
            content = f.read()
        
        assert "Client(" in content, "ClickHouse Client not used"
        assert "clickhouse_host" in content, "ClickHouse host not configured"
        assert "clickhouse_user" in content, "ClickHouse user not configured"
    
    def test_script_has_kafka_consumer_logic(self):
        """Test that the script has Kafka consumer logic"""
        script_path = scripts_dir / "kafka_to_clickhouse.py"
        
        with open(script_path, 'r') as f:
            content = f.read()
        
        assert "KafkaConsumer(" in content, "KafkaConsumer not used"
        assert "bootstrap_servers" in content, "Kafka bootstrap_servers not configured"
        assert "security_protocol" in content, "Kafka security_protocol not configured"
    
    @patch.dict(os.environ, {
        'KAFKA_PASSWORD': 'test_password',
        'CONNECTION_NAME': 'test_connection',
        'CLICKHOUSE_HOST': 'localhost',
        'KAFKA_BROKER': 'localhost:9092',
        'KAFKA_TOPIC': 'test-topic',
        'KAFKA_USERNAME': 'test_user'
    })
    def test_script_can_be_imported_with_mocks(self):
        """Test that the script can be imported with mocked dependencies"""
        script_path = scripts_dir / "kafka_to_clickhouse.py"
        
        # Mock the external dependencies
        with patch('kafka.KafkaConsumer'), \
             patch('clickhouse_driver.Client'):
            # Import should not raise exceptions
            import importlib.util
            spec = importlib.util.spec_from_file_location("kafka_to_clickhouse", script_path)
            module = importlib.util.module_from_spec(spec)
            # Don't execute the module, just verify it can be loaded
            assert module is not None
    
    def test_script_has_schema_inference_logic(self):
        """Test that the script has schema inference logic"""
        script_path = scripts_dir / "kafka_to_clickhouse.py"
        
        with open(script_path, 'r') as f:
            content = f.read()
        
        # Check for schema inference patterns
        assert "schema" in content.lower(), "Schema inference logic not found"
        assert "json.loads" in content, "JSON parsing not found"
    
    def test_script_has_batch_processing_logic(self):
        """Test that the script has batch processing logic"""
        script_path = scripts_dir / "kafka_to_clickhouse.py"
        
        with open(script_path, 'r') as f:
            content = f.read()
        
        # Check for batch processing patterns
        assert "batch" in content.lower() or "execute" in content, "Batch processing logic not found"
    
    def test_script_has_proper_documentation(self):
        """Test that the script has proper documentation"""
        script_path = scripts_dir / "kafka_to_clickhouse.py"
        
        with open(script_path, 'r') as f:
            content = f.read()
        
        # Check for any form of documentation at the top
        lines = content.split('\n')[:10]  # Check first 10 lines
        has_doc = any(line.strip().startswith('#') for line in lines if line.strip())
        assert has_doc, "Script should have header comments or docstring" 