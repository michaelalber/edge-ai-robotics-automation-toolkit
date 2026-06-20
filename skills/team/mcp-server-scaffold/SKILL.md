---
name: mcp-server-scaffold
audience: team
description: >
  Custom MCP server creation with FastMCP pattern and testing. Use when building
  MCP servers to expose tools, resources, or prompts to AI assistants.
  Do NOT use when the integration is synchronous REST-only; Do NOT use when the
  tool surface is a single function that does not benefit from the MCP protocol.
---

# MCP Server Scaffold

> "A good interface is like a good joke: if you have to explain it, it isn't that good."
> -- adapted from the Unix philosophy

## Core Philosophy

This skill guides the creation of Model Context Protocol (MCP) servers using the Python `mcp` SDK
and the FastMCP pattern. MCP servers expose **tools** (actions), **resources** (data), and
**prompts** (structured messages) to AI assistants through a standardized, transport-agnostic
protocol. The same handlers run unchanged across stdio, SSE, and streamable HTTP — transport is a
deployment concern, not a design concern.

**Non-Negotiable Constraints:**
1. CLEAR NAMING — every tool uses `verb_noun`; the name is the primary documentation for AI consumers.
2. VALIDATED INPUTS — every tool validates inputs via type annotations or Pydantic before execution.
3. STRUCTURED ERRORS — return structured error responses (`ctx.error()`); never let raw exceptions reach the transport.
4. TRANSPORT-AGNOSTIC — handlers work identically across stdio, SSE, and streamable HTTP.
5. TESTED — every tool has tests for happy path, edge cases, error cases, and input validation.
6. SCOPED — tools stay within declared scopes; file/network access is restricted; secrets never appear in responses.

The full principle table, tool-vs-resource-vs-prompt decision tree, discipline rules,
anti-patterns, and error recovery live in `references/conventions.md`.

## Workflow

```
DESIGN      Identify each capability the server exposes; classify as tool | resource | prompt
            (decision tree in references/conventions.md). Default to @mcp.tool() when unsure.

SCAFFOLD    Create the FastMCP server instance, choose transport, set up project structure.
            (Server/tool/resource/prompt patterns in references/mcp-protocol-patterns.md.)

IMPLEMENT   Write handlers with input validation, structured error handling, and ctx logging.

INSPECT     Run `mcp dev server.py`; invoke each tool in the MCP Inspector; verify response
            format, schemas, and error cases. (Inspector checklist in mcp-testing-patterns.md.)

TEST        Write pytest tests exercising tools end-to-end — one per category: happy path, edge,
            error, validation. (Patterns in references/mcp-testing-patterns.md.)

DEPLOY      Configure transport (stdio for CLI; SSE/HTTP for networked) and deploy.
```

**Exit criteria:** every capability classified and implemented with validated inputs and structured
errors; each tool validated in the Inspector; tests pass across the four categories; transport
configured for the target deployment.

## State Block

```
<mcp-server-state>
step: Design | Scaffold | Implement | Inspect | Test | Deploy
server_name: [name of the MCP server]
transport: stdio | sse | streamable-http
tools_defined: [count]
tools_tested: [count with passing tests]
last_action: [what was just completed]
next_action: [what should happen next]
blockers: [any issues preventing progress]
</mcp-server-state>
```

## Output Template

- **Server setup, tool/resource/prompt definitions, input schemas, transport config, error handling,
  context/logging** — `references/mcp-protocol-patterns.md`.
- **Unit/integration tests, mocking, Inspector validation checklist, CI setup, fixtures** —
  `references/mcp-testing-patterns.md`.
- **Principle table, decision tree, discipline rules, anti-patterns, error recovery** —
  `references/conventions.md`.

## Integration with Other Skills

| Skill | Relationship |
|-------|-------------|
| `rag-pipeline-python` | MCP servers are natural interfaces for RAG. Expose retrieval/generation as tools and documents as resources; follow that skill for retrieval quality, this one for the transport/interface layer. |
| `ollama-model-workflow` | MCP servers can front local Ollama models with a standardized interface. The MCP layer handles transport and schema; the Ollama workflow handles model selection, prompt formatting, and tuning. |
| `fastapi-scaffolder` | When the same capability also needs a REST surface, build the HTTP API there and keep MCP handlers transport-agnostic so logic is shared, not duplicated. |
