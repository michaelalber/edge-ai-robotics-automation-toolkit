# MCP Server Testing Patterns

## Overview

Testing MCP servers requires validating tool behavior, input schemas, error handling, and transport correctness. This reference covers testing strategies using pytest for unit and integration tests, and the MCP Inspector for interactive validation.

## Test Dependencies Setup

```bash
# Install test dependencies
pip install pytest pytest-asyncio

# Or with uv
uv add --dev pytest pytest-asyncio
```

### pyproject.toml Configuration

```toml
[project]
name = "my-mcp-server"
version = "0.1.0"
dependencies = ["mcp"]

[project.optional-dependencies]
dev = ["pytest", "pytest-asyncio"]

[tool.pytest.ini_options]
asyncio_mode = "auto"
testpaths = ["tests"]
```

## Unit Testing Tools with pytest

### Basic Tool Test

```python
# tests/test_tools.py
import pytest
from server import mcp


@pytest.mark.asyncio
async def test_add_numbers_returns_sum():
    """Test that add_numbers correctly sums two integers."""
    result = await mcp.call_tool("add_numbers", {"a": 2, "b": 3})
    assert result[0].text == "5"


@pytest.mark.asyncio
async def test_add_numbers_handles_negative():
    """Test addition with negative numbers."""
    result = await mcp.call_tool("add_numbers", {"a": -5, "b": 3})
    assert result[0].text == "-2"


@pytest.mark.asyncio
async def test_add_numbers_handles_zero():
    """Test addition with zero."""
    result = await mcp.call_tool("add_numbers", {"a": 0, "b": 0})
    assert result[0].text == "0"
```

### Testing Tool Error Handling

```python
# tests/test_error_handling.py
import pytest
from server import mcp


@pytest.mark.asyncio
async def test_search_with_empty_query_returns_error():
    """Empty search query should return a clear error message."""
    result = await mcp.call_tool("search_documents", {"query": ""})
    assert "Error" in result[0].text
    assert "empty" in result[0].text.lower()


@pytest.mark.asyncio
async def test_search_with_invalid_max_results_returns_error():
    """Out-of-range max_results should return a validation error."""
    result = await mcp.call_tool(
        "search_documents", {"query": "test", "max_results": 500}
    )
    assert "Error" in result[0].text


@pytest.mark.asyncio
async def test_read_file_nonexistent_returns_error():
    """Reading a nonexistent file should return a not-found error."""
    result = await mcp.call_tool("read_file", {"path": "/nonexistent/file.txt"})
    assert "Error" in result[0].text
    assert "not found" in result[0].text.lower()
```

### Testing Tool with Fixtures

```python
# tests/test_document_tools.py
import json
import pytest
from pathlib import Path
from server import mcp


@pytest.fixture
def temp_docs_dir(tmp_path):
    """Create a temporary documents directory with test files."""
    docs = tmp_path / "documents"
    docs.mkdir()

    (docs / "readme.md").write_text("# Welcome\nThis is the readme file.")
    (docs / "guide.md").write_text("# User Guide\nStep 1: Install the software.")
    (docs / "notes.md").write_text("# Notes\nSome internal notes here.")

    return docs


@pytest.fixture
def configured_server(temp_docs_dir, monkeypatch):
    """Configure the MCP server to use the temporary docs directory."""
    import server
    monkeypatch.setattr(server, "DOCS_DIR", temp_docs_dir)
    return mcp


@pytest.mark.asyncio
async def test_search_finds_matching_documents(configured_server):
    """Search should find documents containing the query string."""
    result = await configured_server.call_tool(
        "search_documents", {"query": "readme"}
    )
    data = json.loads(result[0].text)
    assert len(data) >= 1
    assert any("readme" in doc["path"].lower() for doc in data)


@pytest.mark.asyncio
async def test_search_respects_max_results(configured_server):
    """Search should not return more results than max_results."""
    result = await configured_server.call_tool(
        "search_documents", {"query": "#", "max_results": 2}
    )
    data = json.loads(result[0].text)
    assert len(data) <= 2


@pytest.mark.asyncio
async def test_search_returns_empty_for_no_match(configured_server):
    """Search with no matches should return an empty list."""
    result = await configured_server.call_tool(
        "search_documents", {"query": "zzz_nonexistent_zzz"}
    )
    data = json.loads(result[0].text)
    assert data == []
```

## MCP Inspector for Interactive Testing

The MCP Inspector provides a web-based UI for testing your server interactively.

### Launching the Inspector

```bash
# Launch Inspector with your server
mcp dev server.py

# This opens a browser UI where you can:
# - See all registered tools, resources, and prompts
# - Invoke tools with custom parameters
# - View response content and metadata
# - Test error cases interactively
```

### Inspector Validation Checklist

For each tool, verify in the Inspector:

1. **Schema Display** -- Tool parameters appear with correct types and descriptions
2. **Happy Path** -- Valid inputs produce expected outputs
3. **Error Cases** -- Invalid inputs return structured error messages, not stack traces
4. **Edge Cases** -- Empty strings, zero values, boundary values behave correctly
5. **Response Format** -- Output is well-formatted and useful for AI consumers
6. **Description** -- Tool description accurately communicates purpose and usage

### Using Inspector from the Command Line

```bash
# List all tools exposed by the server
mcp dev server.py --list-tools

# Call a specific tool
mcp dev server.py --call-tool search_documents '{"query": "test", "max_results": 5}'
```

## Integration Testing Patterns

### Full Server Integration Test

```python
# tests/test_integration.py
import json
import pytest
from pathlib import Path
from mcp.server.fastmcp import FastMCP


@pytest.fixture
def integration_server(tmp_path):
    """Create a fully configured server for integration testing."""
    mcp = FastMCP("test-server")

    data_dir = tmp_path / "data"
    data_dir.mkdir()
    (data_dir / "users.json").write_text(
        json.dumps([
            {"id": "1", "name": "Alice", "email": "alice@example.com"},
            {"id": "2", "name": "Bob", "email": "bob@example.com"},
        ])
    )

    @mcp.tool()
    async def get_user(user_id: str) -> str:
        """Get user by ID."""
        users = json.loads((data_dir / "users.json").read_text())
        user = next((u for u in users if u["id"] == user_id), None)
        if not user:
            return f"Error: User {user_id} not found"
        return json.dumps(user)

    @mcp.tool()
    async def list_users() -> str:
        """List all users."""
        users = json.loads((data_dir / "users.json").read_text())
        return json.dumps(users)

    @mcp.resource("users://{user_id}")
    def user_resource(user_id: str) -> str:
        """Get user as resource."""
        users = json.loads((data_dir / "users.json").read_text())
        user = next((u for u in users if u["id"] == user_id), None)
        if not user:
            return json.dumps({"error": "not found"})
        return json.dumps(user)

    return mcp


@pytest.mark.asyncio
async def test_get_user_returns_correct_user(integration_server):
    """Integration test: get_user returns matching user data."""
    result = await integration_server.call_tool("get_user", {"user_id": "1"})
    user = json.loads(result[0].text)
    assert user["name"] == "Alice"
    assert user["email"] == "alice@example.com"


@pytest.mark.asyncio
async def test_get_user_not_found(integration_server):
    """Integration test: get_user handles missing user."""
    result = await integration_server.call_tool("get_user", {"user_id": "999"})
    assert "Error" in result[0].text
    assert "not found" in result[0].text.lower()


@pytest.mark.asyncio
async def test_list_users_returns_all(integration_server):
    """Integration test: list_users returns complete user list."""
    result = await integration_server.call_tool("list_users", {})
    users = json.loads(result[0].text)
    assert len(users) == 2


@pytest.mark.asyncio
async def test_tool_and_resource_return_same_data(integration_server):
    """Integration test: tool and resource return consistent data."""
    tool_result = await integration_server.call_tool("get_user", {"user_id": "1"})
    resource_result = await integration_server.read_resource("users://1")

    tool_data = json.loads(tool_result[0].text)
    resource_data = json.loads(resource_result[0].text)

    assert tool_data["name"] == resource_data["name"]
    assert tool_data["email"] == resource_data["email"]
```

### Testing Workflow Sequences

```python
# tests/test_workflows.py
import json
import pytest
from mcp.server.fastmcp import FastMCP


@pytest.fixture
def task_server(tmp_path):
    """Server with task management tools."""
    mcp = FastMCP("task-server")
    tasks = []

    @mcp.tool()
    async def create_task(title: str, priority: str = "medium") -> str:
        """Create a new task."""
        task = {
            "id": str(len(tasks) + 1),
            "title": title,
            "priority": priority,
            "done": False,
        }
        tasks.append(task)
        return json.dumps(task)

    @mcp.tool()
    async def complete_task(task_id: str) -> str:
        """Mark a task as complete."""
        task = next((t for t in tasks if t["id"] == task_id), None)
        if not task:
            return f"Error: Task {task_id} not found"
        task["done"] = True
        return json.dumps(task)

    @mcp.tool()
    async def list_tasks(only_pending: bool = False) -> str:
        """List tasks, optionally filtering to pending only."""
        filtered = [t for t in tasks if not only_pending or not t["done"]]
        return json.dumps(filtered)

    return mcp


@pytest.mark.asyncio
async def test_create_then_complete_workflow(task_server):
    """Test the full create-then-complete workflow."""
    # Create a task
    create_result = await task_server.call_tool(
        "create_task", {"title": "Write tests", "priority": "high"}
    )
    task = json.loads(create_result[0].text)
    assert task["done"] is False

    # Complete the task
    complete_result = await task_server.call_tool(
        "complete_task", {"task_id": task["id"]}
    )
    completed = json.loads(complete_result[0].text)
    assert completed["done"] is True

    # Verify it does not appear in pending list
    list_result = await task_server.call_tool(
        "list_tasks", {"only_pending": True}
    )
    pending = json.loads(list_result[0].text)
    assert all(t["id"] != task["id"] for t in pending)
```

## Mocking External Dependencies

### Mocking with pytest and unittest.mock

```python
# tests/test_with_mocks.py
import pytest
from unittest.mock import AsyncMock, patch
from server import mcp


@pytest.mark.asyncio
async def test_fetch_weather_mocks_api():
    """Test weather tool without calling the real API."""
    mock_response = {"temperature": 72, "condition": "sunny", "city": "Portland"}

    with patch("server.weather_api.get_current", new_callable=AsyncMock) as mock_api:
        mock_api.return_value = mock_response

        result = await mcp.call_tool("get_weather", {"city": "Portland"})
        assert "72" in result[0].text
        assert "sunny" in result[0].text
        mock_api.assert_called_once_with("Portland")


@pytest.mark.asyncio
async def test_fetch_weather_handles_api_failure():
    """Test weather tool gracefully handles API errors."""
    with patch("server.weather_api.get_current", new_callable=AsyncMock) as mock_api:
        mock_api.side_effect = ConnectionError("API unavailable")

        result = await mcp.call_tool("get_weather", {"city": "Portland"})
        assert "Error" in result[0].text
        assert "unavailable" in result[0].text.lower()
```

### Mocking Database Connections

```python
# tests/test_db_tools.py
import json
import pytest
from unittest.mock import AsyncMock, patch


@pytest.fixture
def mock_db():
    """Create a mock database connection."""
    db = AsyncMock()
    db.query.return_value = [
        {"id": 1, "name": "Alice"},
        {"id": 2, "name": "Bob"},
    ]
    return db


@pytest.mark.asyncio
async def test_query_users_returns_results(mock_db):
    """Test database query tool with mocked database."""
    with patch("server.db", mock_db):
        from server import mcp
        result = await mcp.call_tool("query_users", {"name_filter": "A"})
        data = json.loads(result[0].text)
        assert len(data) >= 1


@pytest.mark.asyncio
async def test_query_handles_db_timeout(mock_db):
    """Test graceful handling of database timeout."""
    mock_db.query.side_effect = TimeoutError("Query timed out")

    with patch("server.db", mock_db):
        from server import mcp
        result = await mcp.call_tool("query_users", {"name_filter": "A"})
        assert "Error" in result[0].text
        assert "timed out" in result[0].text.lower()
```

### Mocking File System

```python
# tests/test_file_tools.py
import pytest
from pathlib import Path


@pytest.fixture
def mock_workspace(tmp_path):
    """Create a temporary workspace with test files."""
    workspace = tmp_path / "workspace"
    workspace.mkdir()

    # Create test file structure
    (workspace / "src").mkdir()
    (workspace / "src" / "main.py").write_text("print('hello')")
    (workspace / "src" / "utils.py").write_text("def helper(): pass")
    (workspace / "README.md").write_text("# My Project")
    (workspace / "config.json").write_text('{"key": "value"}')

    return workspace


@pytest.mark.asyncio
async def test_list_files_returns_workspace_contents(mock_workspace, monkeypatch):
    """Test file listing within constrained workspace."""
    import server
    monkeypatch.setattr(server, "WORKSPACE_DIR", mock_workspace)

    result = await server.mcp.call_tool("list_files", {"directory": "."})
    assert "main.py" in result[0].text
    assert "README.md" in result[0].text


@pytest.mark.asyncio
async def test_read_file_rejects_path_traversal(mock_workspace, monkeypatch):
    """Test that path traversal attacks are blocked."""
    import server
    monkeypatch.setattr(server, "WORKSPACE_DIR", mock_workspace)

    result = await server.mcp.call_tool("read_file", {"path": "../../etc/passwd"})
    assert "Error" in result[0].text
```

## Testing Different Transport Modes

### Testing stdio Transport

```python
# tests/test_stdio.py
import asyncio
import json
import pytest


@pytest.mark.asyncio
async def test_server_starts_on_stdio():
    """Verify server starts correctly with stdio transport."""
    proc = await asyncio.create_subprocess_exec(
        "python", "server.py",
        stdin=asyncio.subprocess.PIPE,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )

    # Send initialize request via JSON-RPC over stdio
    initialize_msg = {
        "jsonrpc": "2.0",
        "id": 1,
        "method": "initialize",
        "params": {
            "protocolVersion": "2024-11-05",
            "capabilities": {},
            "clientInfo": {"name": "test-client", "version": "1.0.0"},
        },
    }

    msg_bytes = json.dumps(initialize_msg).encode()
    header = f"Content-Length: {len(msg_bytes)}\r\n\r\n".encode()

    proc.stdin.write(header + msg_bytes)
    await proc.stdin.drain()

    # Read response
    response_data = await asyncio.wait_for(proc.stdout.read(4096), timeout=5.0)
    assert b"protocolVersion" in response_data

    proc.terminate()
    await proc.wait()
```

### Testing SSE Transport

```python
# tests/test_sse.py
import asyncio
import pytest
import httpx


@pytest.fixture
async def sse_server():
    """Start the server with SSE transport for testing."""
    proc = await asyncio.create_subprocess_exec(
        "python", "-c",
        "from server import mcp; mcp.run(transport='sse')",
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )

    # Wait for server to start
    await asyncio.sleep(2)

    yield proc

    proc.terminate()
    await proc.wait()


@pytest.mark.asyncio
async def test_sse_endpoint_responds(sse_server):
    """Verify the SSE endpoint is reachable."""
    async with httpx.AsyncClient() as client:
        response = await client.get("http://localhost:8000/sse", timeout=5.0)
        assert response.status_code == 200
```

## Test Fixtures for MCP Server Instances

### Reusable Server Fixture

```python
# tests/conftest.py
import pytest
from mcp.server.fastmcp import FastMCP


@pytest.fixture
def fresh_server():
    """Create a fresh, empty MCP server for each test."""
    return FastMCP("test-server")


@pytest.fixture
def configured_server():
    """Create a pre-configured server with standard tools."""
    mcp = FastMCP("test-configured")

    @mcp.tool()
    async def echo(message: str) -> str:
        """Echo a message back."""
        return message

    @mcp.tool()
    async def reverse(text: str) -> str:
        """Reverse a string."""
        return text[::-1]

    @mcp.resource("test://greeting")
    def greeting() -> str:
        """Return a test greeting."""
        return "Hello, test!"

    return mcp


@pytest.fixture
def server_with_state():
    """Create a server with mutable state for testing side effects."""
    mcp = FastMCP("test-stateful")
    state = {"items": [], "count": 0}

    @mcp.tool()
    async def add_item(name: str) -> str:
        """Add an item to the list."""
        state["items"].append(name)
        state["count"] += 1
        return f"Added '{name}'. Total items: {state['count']}"

    @mcp.tool()
    async def get_items() -> str:
        """Get all items."""
        return ", ".join(state["items"]) if state["items"] else "No items"

    @mcp.tool()
    async def clear_items() -> str:
        """Clear all items."""
        state["items"].clear()
        state["count"] = 0
        return "Cleared all items"

    return mcp, state
```

### Using Fixtures in Tests

```python
# tests/test_with_fixtures.py
import pytest


@pytest.mark.asyncio
async def test_echo_returns_input(configured_server):
    """Echo tool should return the input unchanged."""
    result = await configured_server.call_tool("echo", {"message": "hello world"})
    assert result[0].text == "hello world"


@pytest.mark.asyncio
async def test_reverse_reverses_string(configured_server):
    """Reverse tool should reverse the input string."""
    result = await configured_server.call_tool("reverse", {"text": "abcd"})
    assert result[0].text == "dcba"


@pytest.mark.asyncio
async def test_resource_returns_greeting(configured_server):
    """Greeting resource should return expected text."""
    result = await configured_server.read_resource("test://greeting")
    assert result[0].text == "Hello, test!"


@pytest.mark.asyncio
async def test_stateful_add_and_get(server_with_state):
    """Adding items should be reflected in the get response."""
    server, state = server_with_state

    await server.call_tool("add_item", {"name": "apple"})
    await server.call_tool("add_item", {"name": "banana"})

    result = await server.call_tool("get_items", {})
    assert "apple" in result[0].text
    assert "banana" in result[0].text


@pytest.mark.asyncio
async def test_clear_resets_state(server_with_state):
    """Clearing items should reset the state."""
    server, state = server_with_state

    await server.call_tool("add_item", {"name": "apple"})
    await server.call_tool("clear_items", {})

    result = await server.call_tool("get_items", {})
    assert result[0].text == "No items"
    assert state["count"] == 0
```

## Testing Error Handling and Edge Cases

### Comprehensive Edge Case Tests

```python
# tests/test_edge_cases.py
import pytest
from server import mcp


@pytest.mark.asyncio
async def test_tool_with_empty_string_input():
    """Tools should handle empty string input gracefully."""
    result = await mcp.call_tool("search_documents", {"query": ""})
    assert "Error" in result[0].text


@pytest.mark.asyncio
async def test_tool_with_very_long_input():
    """Tools should handle extremely long input without crashing."""
    long_input = "a" * 100_000
    result = await mcp.call_tool("search_documents", {"query": long_input})
    # Should not raise an exception -- any response is acceptable
    assert result is not None


@pytest.mark.asyncio
async def test_tool_with_special_characters():
    """Tools should handle special characters in input."""
    special = "hello <script>alert('xss')</script> world"
    result = await mcp.call_tool("search_documents", {"query": special})
    assert result is not None


@pytest.mark.asyncio
async def test_tool_with_unicode_input():
    """Tools should handle Unicode input correctly."""
    result = await mcp.call_tool(
        "search_documents", {"query": "recherche en francais"}
    )
    assert result is not None


@pytest.mark.asyncio
async def test_concurrent_tool_calls():
    """Multiple concurrent tool calls should not interfere."""
    import asyncio

    tasks = [
        mcp.call_tool("search_documents", {"query": f"query_{i}"})
        for i in range(10)
    ]
    results = await asyncio.gather(*tasks)
    assert all(r is not None for r in results)
    assert len(results) == 10
```

### Testing Validation Boundaries

```python
# tests/test_validation.py
import pytest
from server import mcp


@pytest.mark.asyncio
async def test_max_results_at_lower_bound():
    """max_results=1 should be accepted."""
    result = await mcp.call_tool(
        "search_documents", {"query": "test", "max_results": 1}
    )
    assert "Error" not in result[0].text


@pytest.mark.asyncio
async def test_max_results_at_upper_bound():
    """max_results at maximum should be accepted."""
    result = await mcp.call_tool(
        "search_documents", {"query": "test", "max_results": 50}
    )
    assert "Error" not in result[0].text


@pytest.mark.asyncio
async def test_max_results_below_lower_bound():
    """max_results=0 should be rejected."""
    result = await mcp.call_tool(
        "search_documents", {"query": "test", "max_results": 0}
    )
    assert "Error" in result[0].text


@pytest.mark.asyncio
async def test_max_results_above_upper_bound():
    """max_results above maximum should be rejected."""
    result = await mcp.call_tool(
        "search_documents", {"query": "test", "max_results": 999}
    )
    assert "Error" in result[0].text
```

## CI/CD Testing Setup

### GitHub Actions Workflow

```yaml
# .github/workflows/test-mcp-server.yml
name: Test MCP Server

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        python-version: ["3.10", "3.11", "3.12"]

    steps:
      - uses: actions/checkout@v4

      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: ${{ matrix.python-version }}

      - name: Install dependencies
        run: pip install -e ".[dev]"

      - name: Run unit tests
        run: pytest tests/ -v --tb=short

      - name: Run tests with coverage
        run: pytest tests/ --cov=. --cov-report=xml
```

### Makefile for Common Test Commands

```makefile
# Makefile
.PHONY: test test-verbose test-coverage lint

test:
	pytest tests/ -v

test-verbose:
	pytest tests/ -v --tb=long

test-coverage:
	pytest tests/ --cov=. --cov-report=term-missing --cov-report=html

lint:
	ruff check .
	mypy server.py
```

## Example Test File Structure

```
my-mcp-server/
    server.py
    pyproject.toml
    tests/
        __init__.py
        conftest.py            # Shared fixtures
        test_tools.py          # Unit tests for individual tools
        test_resources.py      # Unit tests for resources
        test_prompts.py        # Unit tests for prompts
        test_validation.py     # Input validation edge cases
        test_error_handling.py # Error scenarios
        test_integration.py    # End-to-end workflows
        test_transport.py      # Transport-specific tests
```

### Minimal conftest.py

```python
# tests/conftest.py
import pytest
import sys
from pathlib import Path

# Ensure the server module is importable
sys.path.insert(0, str(Path(__file__).parent.parent))


@pytest.fixture(autouse=True)
def reset_server_state():
    """Reset any server-side mutable state between tests."""
    yield
    # Cleanup after each test if needed


@pytest.fixture
def sample_data():
    """Provide sample data for testing."""
    return {
        "users": [
            {"id": "1", "name": "Alice"},
            {"id": "2", "name": "Bob"},
        ],
        "documents": [
            {"id": "doc1", "title": "Getting Started", "content": "Welcome."},
            {"id": "doc2", "title": "API Reference", "content": "Endpoints."},
        ],
    }
```

## Running Tests

```bash
# Run all tests
pytest

# Run specific test file
pytest tests/test_tools.py

# Run specific test function
pytest tests/test_tools.py::test_add_numbers_returns_sum

# Run with verbose output
pytest -v

# Run and stop on first failure
pytest -x

# Run only previously failed tests
pytest --lf

# Run with coverage report
pytest --cov=. --cov-report=term-missing

# Run tests matching a keyword
pytest -k "search"

# Run tests with specific marker
pytest -m "asyncio"
```
