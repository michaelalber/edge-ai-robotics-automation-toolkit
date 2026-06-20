# MCP Protocol Patterns Reference

## Overview

The Model Context Protocol (MCP) provides a standardized way for AI assistants to interact with external tools, data sources, and prompt templates. This reference covers the Python `mcp` SDK using the FastMCP pattern.

## Installation

```bash
# Using uv (recommended)
uv add mcp

# Using pip
pip install mcp

# With CLI extras for mcp dev / mcp inspector
pip install "mcp[cli]"
```

## Virtual Environment Setup

```bash
# Create and activate virtual environment with uv
uv init mcp-server-project
cd mcp-server-project
uv add mcp

# Or with standard venv
python -m venv .venv
source .venv/bin/activate  # Linux/macOS
# .venv\Scripts\activate   # Windows
pip install mcp
```

## FastMCP Server Setup

The `FastMCP` class is the primary entry point for creating MCP servers. It provides a high-level, decorator-based API.

```python
# server.py
from mcp.server.fastmcp import FastMCP

# Create server instance with a descriptive name
mcp = FastMCP("my-server")

# Run the server (uses stdio transport by default)
if __name__ == "__main__":
    mcp.run()
```

### Server with Configuration

```python
from mcp.server.fastmcp import FastMCP

mcp = FastMCP(
    "my-server",
    dependencies=["httpx", "pandas"],  # Declared dependencies
)
```

## Tool Definition with @mcp.tool()

Tools are the primary way to expose executable functionality to AI assistants. They represent actions the AI can take.

### Basic Tool

```python
@mcp.tool()
async def add_numbers(a: int, b: int) -> str:
    """Add two numbers together.

    Args:
        a: First number
        b: Second number
    """
    return str(a + b)
```

### Tool with Context

The `Context` object provides logging, progress reporting, and resource access within tool handlers.

```python
from mcp.server.fastmcp import Context

@mcp.tool()
async def process_data(file_path: str, ctx: Context = None) -> str:
    """Process a data file and return summary statistics.

    Args:
        file_path: Path to the data file to process
    """
    if ctx:
        ctx.info(f"Processing file: {file_path}")
        await ctx.report_progress(0, 100)

    data = load_data(file_path)

    if ctx:
        await ctx.report_progress(50, 100)

    result = analyze(data)

    if ctx:
        await ctx.report_progress(100, 100)
        ctx.info(f"Processing complete: {len(data)} records analyzed")

    return format_summary(result)
```

### Tool with Complex Input Types

```python
from typing import Optional

@mcp.tool()
async def search_records(
    query: str,
    max_results: int = 10,
    category: Optional[str] = None,
    include_archived: bool = False,
) -> str:
    """Search records by query string.

    Args:
        query: The search query
        max_results: Maximum number of results to return (1-100)
        category: Optional category filter
        include_archived: Whether to include archived records
    """
    filters = {"archived": include_archived}
    if category:
        filters["category"] = category

    results = await db.search(query, limit=max_results, filters=filters)
    return format_results(results)
```

### Tool with Pydantic Input Validation

```python
from pydantic import BaseModel, Field


class CreateUserInput(BaseModel):
    name: str = Field(description="Full name of the user", min_length=1, max_length=200)
    email: str = Field(description="Email address", pattern=r"^[\w.-]+@[\w.-]+\.\w+$")
    role: str = Field(default="viewer", description="User role", pattern=r"^(admin|editor|viewer)$")


@mcp.tool()
async def create_user(name: str, email: str, role: str = "viewer") -> str:
    """Create a new user account.

    Args:
        name: Full name of the user
        email: Valid email address
        role: User role (admin, editor, or viewer)
    """
    # Validate using the Pydantic model
    validated = CreateUserInput(name=name, email=email, role=role)
    user = await user_service.create(validated.name, validated.email, validated.role)
    return f"Created user {user.id}: {user.name} ({user.role})"
```

## Resource Definition with @mcp.resource()

Resources expose data that AI assistants can read. They use URI patterns for addressing.

### Static Resource

```python
@mcp.resource("config://app-settings")
def get_app_settings() -> str:
    """Return current application settings."""
    settings = load_settings()
    return json.dumps(settings, indent=2)
```

### Dynamic Resource with URI Template

```python
@mcp.resource("users://{user_id}")
def get_user(user_id: str) -> str:
    """Retrieve user profile by ID.

    Args:
        user_id: The unique user identifier
    """
    user = user_service.get(user_id)
    if not user:
        return json.dumps({"error": f"User {user_id} not found"})
    return json.dumps(user.to_dict())
```

### Resource with MIME Type

```python
@mcp.resource("reports://monthly/{year}/{month}", mime_type="application/json")
def get_monthly_report(year: str, month: str) -> str:
    """Get monthly activity report.

    Args:
        year: Four-digit year
        month: Two-digit month (01-12)
    """
    report = generate_report(int(year), int(month))
    return json.dumps(report)
```

### Binary Resource

```python
@mcp.resource("images://logo", mime_type="image/png")
def get_logo() -> bytes:
    """Return the application logo as PNG."""
    with open("assets/logo.png", "rb") as f:
        return f.read()
```

## Prompt Definition with @mcp.prompt()

Prompts are reusable templates that generate structured messages for the AI assistant.

### Basic Prompt

```python
from mcp.server.fastmcp.prompts import base

@mcp.prompt()
def review_code(code: str, language: str = "python") -> str:
    """Generate a code review prompt.

    Args:
        code: The code to review
        language: Programming language of the code
    """
    return f"""Please review the following {language} code for:
1. Correctness and potential bugs
2. Performance issues
3. Security vulnerabilities
4. Code style and readability

Code:
```{language}
{code}
```"""
```

### Prompt with Multiple Messages

```python
from mcp.server.fastmcp.prompts import base

@mcp.prompt()
def debug_error(error_message: str, stack_trace: str = "") -> list[base.Message]:
    """Generate a debugging prompt for an error.

    Args:
        error_message: The error message to debug
        stack_trace: Optional stack trace
    """
    messages = [
        base.UserMessage(
            content=f"I'm encountering this error and need help debugging it.\n\nError: {error_message}"
        ),
    ]
    if stack_trace:
        messages.append(
            base.UserMessage(content=f"Stack trace:\n```\n{stack_trace}\n```")
        )
    messages.append(
        base.AssistantMessage(
            content="I'll analyze this error. Let me break down what's happening..."
        )
    )
    return messages
```

## Input Schema Patterns with Pydantic

### Enum-Based Choices

```python
from enum import Enum


class SortOrder(str, Enum):
    ASC = "asc"
    DESC = "desc"


class Priority(str, Enum):
    LOW = "low"
    MEDIUM = "medium"
    HIGH = "high"
    CRITICAL = "critical"


@mcp.tool()
async def list_tasks(
    sort_by: str = "created",
    order: str = "desc",
    priority: str = "medium",
) -> str:
    """List tasks with filtering and sorting.

    Args:
        sort_by: Field to sort by (created, updated, priority)
        order: Sort order (asc or desc)
        priority: Minimum priority filter (low, medium, high, critical)
    """
    tasks = await task_service.list(
        sort_by=sort_by,
        order=SortOrder(order),
        min_priority=Priority(priority),
    )
    return format_task_list(tasks)
```

### Nested Pydantic Models

```python
from pydantic import BaseModel, Field
from typing import Optional


class Address(BaseModel):
    street: str = Field(description="Street address")
    city: str = Field(description="City name")
    state: str = Field(description="State or province")
    zip_code: str = Field(description="Postal/ZIP code")


class ContactInfo(BaseModel):
    email: str = Field(description="Email address")
    phone: Optional[str] = Field(default=None, description="Phone number")
    address: Optional[Address] = Field(default=None, description="Mailing address")
```

## Transport Configuration

### stdio Transport (Default)

Used for local integrations where the client spawns the server as a subprocess.

```python
# server.py
from mcp.server.fastmcp import FastMCP

mcp = FastMCP("my-server")

# Define tools, resources, prompts...

if __name__ == "__main__":
    mcp.run()  # Defaults to stdio
```

Run with:
```bash
python server.py
# Or with mcp dev for Inspector
mcp dev server.py
```

### SSE Transport

Used for network-accessible servers. The server runs as an HTTP endpoint with Server-Sent Events.

```python
if __name__ == "__main__":
    mcp.run(transport="sse")
```

Run with:
```bash
python server.py
# Server listens on http://localhost:8000/sse by default
```

### Streamable HTTP Transport

The newer HTTP-based transport for production deployments.

```python
if __name__ == "__main__":
    mcp.run(transport="streamable-http")
```

### Client Configuration for Each Transport

```json
{
  "mcpServers": {
    "my-stdio-server": {
      "command": "python",
      "args": ["server.py"]
    },
    "my-sse-server": {
      "url": "http://localhost:8000/sse"
    },
    "my-http-server": {
      "url": "http://localhost:8000/mcp"
    }
  }
}
```

## Error Handling Patterns

### Returning Errors vs Raising Exceptions

In MCP tools, prefer returning error strings over raising exceptions. The AI consumer needs actionable information, not stack traces.

```python
# Pattern 1: Return error strings (preferred for operational errors)
@mcp.tool()
async def read_file(path: str) -> str:
    """Read contents of a file.

    Args:
        path: Path to the file to read
    """
    resolved = Path(path).resolve()
    if not resolved.exists():
        return f"Error: File not found: {path}"
    if not resolved.is_file():
        return f"Error: Path is not a file: {path}"
    try:
        return resolved.read_text()
    except PermissionError:
        return f"Error: Permission denied reading: {path}"
    except UnicodeDecodeError:
        return f"Error: File is not a text file: {path}"
```

```python
# Pattern 2: Raise McpError for protocol-level errors
from mcp.shared.exceptions import McpError

@mcp.tool()
async def critical_operation(token: str) -> str:
    """Perform a critical operation requiring authentication.

    Args:
        token: Authentication token
    """
    if not is_valid_token(token):
        raise McpError("INVALID_PARAMS", "Invalid authentication token")
    return await perform_operation()
```

### Comprehensive Error Handling Template

```python
@mcp.tool()
async def robust_tool(param: str, ctx: Context = None) -> str:
    """A tool with comprehensive error handling.

    Args:
        param: Input parameter
    """
    # Input validation
    if not param or not param.strip():
        return "Error: Parameter 'param' cannot be empty"

    try:
        if ctx:
            ctx.info(f"Starting operation with param={param}")

        result = await external_service.call(param)

        if ctx:
            ctx.info(f"Operation completed successfully")

        return format_result(result)

    except ConnectionError as e:
        if ctx:
            ctx.error(f"Connection failed: {e}")
        return "Error: Unable to connect to external service. Please try again later."

    except TimeoutError:
        if ctx:
            ctx.error("Operation timed out")
        return "Error: Operation timed out. The service may be under heavy load."

    except ValueError as e:
        return f"Error: Invalid input - {e}"

    except Exception as e:
        if ctx:
            ctx.error(f"Unexpected error: {type(e).__name__}: {e}")
        return "Error: An unexpected error occurred. Please check server logs."
```

## Context Usage

The `Context` object is injected into tool handlers and provides several capabilities.

### Logging

```python
@mcp.tool()
async def example_tool(data: str, ctx: Context = None) -> str:
    """Example tool demonstrating context logging.

    Args:
        data: Input data to process
    """
    if ctx:
        ctx.info("Starting processing")
        ctx.debug(f"Input data length: {len(data)}")
        ctx.warning("Large dataset detected") if len(data) > 10000 else None
        ctx.error("Processing failed") if not data else None
    return "Done"
```

### Progress Reporting

```python
@mcp.tool()
async def batch_process(items: str, ctx: Context = None) -> str:
    """Process a batch of items with progress reporting.

    Args:
        items: Comma-separated list of items to process
    """
    item_list = items.split(",")
    total = len(item_list)
    results = []

    for i, item in enumerate(item_list):
        if ctx:
            await ctx.report_progress(i, total)
        result = await process_item(item.strip())
        results.append(result)

    if ctx:
        await ctx.report_progress(total, total)

    return "\n".join(results)
```

### Reading Resources from Within Tools

```python
@mcp.tool()
async def analyze_with_config(data: str, ctx: Context = None) -> str:
    """Analyze data using settings from the config resource.

    Args:
        data: Data to analyze
    """
    if ctx:
        config_data = await ctx.read_resource("config://analysis-settings")
        config = json.loads(config_data)
    else:
        config = default_config()

    return perform_analysis(data, config)
```

## Logging and Progress Reporting

### Structured Logging Pattern

```python
import logging
from mcp.server.fastmcp import FastMCP

# Configure Python logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("my-mcp-server")

mcp = FastMCP("my-server")


@mcp.tool()
async def logged_tool(query: str, ctx: Context = None) -> str:
    """A tool with comprehensive logging.

    Args:
        query: Search query
    """
    # Use ctx for MCP-level logging (sent to client)
    if ctx:
        ctx.info(f"Executing search: {query}")

    # Use Python logger for server-side logging (goes to stderr/files)
    logger.info(f"Search requested: query={query}")

    try:
        results = await search(query)
        logger.info(f"Search completed: {len(results)} results")
        if ctx:
            ctx.info(f"Found {len(results)} results")
        return format_results(results)
    except Exception as e:
        logger.exception(f"Search failed: {e}")
        if ctx:
            ctx.error(f"Search failed: {e}")
        return f"Error: Search failed - {e}"
```

## Complete Server Example

```python
# server.py
"""Document management MCP server."""

import json
from pathlib import Path
from mcp.server.fastmcp import FastMCP, Context

mcp = FastMCP("document-server")

DOCS_DIR = Path("./documents")


@mcp.tool()
async def search_documents(query: str, max_results: int = 10, ctx: Context = None) -> str:
    """Search documents by keyword.

    Args:
        query: Search query string
        max_results: Maximum number of results (1-50)
    """
    if not query.strip():
        return "Error: Query cannot be empty"
    if not 1 <= max_results <= 50:
        return "Error: max_results must be between 1 and 50"

    if ctx:
        ctx.info(f"Searching for '{query}' (max {max_results})")

    matches = []
    for doc_path in DOCS_DIR.glob("**/*.md"):
        content = doc_path.read_text()
        if query.lower() in content.lower():
            matches.append({"path": str(doc_path), "preview": content[:200]})
            if len(matches) >= max_results:
                break

    if ctx:
        ctx.info(f"Found {len(matches)} matching documents")

    return json.dumps(matches, indent=2)


@mcp.resource("docs://{path}")
def get_document(path: str) -> str:
    """Read a document by its path.

    Args:
        path: Relative path to the document
    """
    doc_path = (DOCS_DIR / path).resolve()
    if not doc_path.is_relative_to(DOCS_DIR.resolve()):
        return json.dumps({"error": "Access denied: path outside documents directory"})
    if not doc_path.exists():
        return json.dumps({"error": f"Document not found: {path}"})
    return doc_path.read_text()


@mcp.resource("docs://index")
def list_documents() -> str:
    """List all available documents."""
    docs = [str(p.relative_to(DOCS_DIR)) for p in DOCS_DIR.glob("**/*.md")]
    return json.dumps(sorted(docs), indent=2)


@mcp.prompt()
def summarize_document(content: str, style: str = "concise") -> str:
    """Generate a prompt to summarize a document.

    Args:
        content: Document content to summarize
        style: Summary style (concise, detailed, bullet-points)
    """
    return f"""Please summarize the following document in a {style} style.

Document:
{content}

Provide a clear, well-structured summary."""


if __name__ == "__main__":
    mcp.run()
```

## Running and Testing

```bash
# Run server with stdio (default)
python server.py

# Run with MCP Inspector for interactive testing
mcp dev server.py

# Install as a Claude Desktop server
mcp install server.py

# Install with a custom name
mcp install server.py --name "My Document Server"

# Run with SSE transport
python -c "
from server import mcp
mcp.run(transport='sse')
"
```
