# MCP Server Conventions

Depth behind the Core Philosophy constraints: the full principle set, anti-patterns, discipline
rules, and recovery steps. Code patterns for every rule live in `mcp-protocol-patterns.md`
(server/tool/resource/prompt, transports, error handling) and `mcp-testing-patterns.md` (tests,
Inspector checklist).

## Domain Principles

| # | Principle | Description | Priority |
|---|-----------|-------------|----------|
| 1 | **Tool Naming Clarity** | Tool names use `verb_noun` convention (e.g., `get_user`, `search_documents`). Names are the primary documentation for AI consumers. | Critical |
| 2 | **Schema Validation** | All tool inputs are validated through type annotations or Pydantic models. Invalid inputs are rejected before handler execution with clear error messages. | Critical |
| 3 | **Error Propagation** | Errors are returned as structured MCP error responses, not raised as exceptions. Use `ctx.error()` for operational errors. Reserve exceptions for truly unexpected failures. | Critical |
| 4 | **Transport Abstraction** | Server logic is transport-agnostic. The same tool handlers work across stdio, SSE, and streamable HTTP without modification. Transport is a deployment concern, not a design concern. | High |
| 5 | **Idempotent Operations** | Read-only tools are naturally idempotent. Write tools document their idempotency guarantees. Repeated calls with the same input produce consistent outcomes. | High |
| 6 | **Resource Lifecycle** | Resources have clear URIs, predictable content types, and well-defined freshness semantics. Resource templates use URI patterns for parameterized access. | High |
| 7 | **Prompt Templating** | Prompts declare their arguments explicitly. Templates produce well-structured messages with clear roles. Prompts are composable building blocks, not monolithic instructions. | Medium |
| 8 | **Security Boundaries** | Tools operate within declared scopes. File access is restricted to allowed directories. Network calls go only to approved endpoints. Secrets never appear in tool responses. | Critical |
| 9 | **Logging and Observability** | All tool invocations log input parameters (sanitized), execution duration, and outcome. Use `ctx.info()`, `ctx.warning()`, and `ctx.error()` for structured logging. Progress reporting uses `ctx.report_progress()`. | High |
| 10 | **Graceful Degradation** | When external dependencies fail, tools return meaningful partial results or clear error messages rather than crashing. Timeout handling is explicit. | Medium |

## Tool Design Decision Tree

```
What capability does the AI need?
├── Perform an ACTION or COMPUTATION?   → @mcp.tool()      (search_database, send_email)
├── Access DATA that changes over time? → @mcp.resource()  (config://settings, db://users/{id})
├── Generate a STRUCTURED PROMPT?        → @mcp.prompt()     (review_code, summarize_document)
└── Unsure?                              → @mcp.tool()       (the most flexible primitive)
```

## Discipline Rules

Code for each rule is in `mcp-protocol-patterns.md` / `mcp-testing-patterns.md`.

- **Always validate tool inputs.** Required params present, types match, values within declared
  constraints (min/max/pattern); validation failures return clear, actionable messages. Path-taking
  tools resolve and confirm the path is inside the allowed workspace before acting.
- **Never expose raw exceptions.** Catch exceptions and return structured error strings; a leaked
  traceback confuses AI consumers and can expose secrets.
- **Always write tool tests.** One test per category: happy path, edge cases, error cases, input
  validation. Do not ship a tool without all four.
- **Never skip MCP Inspector validation.** Run `mcp dev server.py`, invoke each tool with sample
  inputs, verify response format and error cases, confirm descriptions/schemas render. If the
  Inspector is unavailable, document the gap and open an issue.

## Anti-Patterns

| Anti-Pattern | Why It's Wrong | Correct Approach |
|--------------|----------------|------------------|
| **God tool that does everything** | Overloaded tools confuse AI consumers, make testing difficult, violate single-responsibility | Split into focused tools: `search_users`, `get_user`, `create_user` instead of `manage_users` |
| **Missing input schemas** | AI cannot construct valid requests without knowing parameter types and constraints | Always declare types, use `Field()` for descriptions and constraints |
| **Exposing raw exceptions** | Stack traces leak implementation details, confuse AI consumers, may expose secrets | Catch exceptions, return structured error strings |
| **Transport-coupled logic** | Business logic tied to a specific transport cannot be reused or tested in isolation | Keep handlers transport-agnostic; transport is configured at startup |
| **Stateful tools without documentation** | Tools depending on prior invocations create hidden coupling AI cannot reason about | Document state requirements in tool descriptions, prefer stateless designs |
| **Ignoring Context parameter** | Skipping `ctx` means no logging, no progress reporting, no resource access | Accept `Context` parameter and use it for logging and progress |
| **Overly broad resource URIs** | Resources like `data://everything` provide no structure for AI navigation | Use specific URI patterns: `users://{id}`, `config://database` |
| **Hardcoded configuration** | Secrets, endpoints, and paths baked into code cannot be changed per deployment | Use environment variables or configuration files, never hardcode |

## Error Recovery

**Transport connection errors (client cannot connect):**
1. Verify transport config matches client expectations
2. stdio: ensure the server process starts without errors
3. SSE: check the port is available and not firewalled
4. streamable HTTP: verify endpoint URL and CORS settings
5. Check server logs for startup errors; test with `mcp dev server.py`

**Schema validation failures (client sends invalid parameters):**
1. Review the error message returned to the client
2. Verify parameter types match the tool's declared schema
3. Check for missing required parameters and value constraints documented in `Field()`
4. Test the failing input in MCP Inspector; if the schema is ambiguous, improve `Field` descriptions

**Tool execution errors (handler raises unhandled exception):**
1. Check server logs for the traceback; identify the failed dependency/operation
2. Add a `try/except` for the specific exception type, return a structured error message
3. Add a test case for the failure scenario; re-test in Inspector to verify the error response format

**Resource not found (client requests a URI that does not exist):**
1. Verify the URI matches a registered resource or template
2. Check template parameters are valid (e.g., the ID exists)
3. Return a clear "not found" message rather than an empty response; log the request
4. Consider a resource-listing endpoint for discovery

**Server startup failures (server fails to start / crashes on init):**
1. Check for import errors in `server.py`
2. Verify dependencies installed (`pip install mcp`)
3. Check for port conflicts (SSE/HTTP)
4. Validate environment variables; run `server.py` directly to see error output
5. Confirm Python 3.10+
