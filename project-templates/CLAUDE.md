# [PROJECT NAME] — Project Context
<!-- ⚠ PROJECT-LEVEL FILE — NOT GLOBAL
     This is the project-level CLAUDE.md for Claude Code.
     It supplements your global ~/.claude/CLAUDE.md — it does NOT replace it.
     Global standards (coding style, security rules, quality gates) live in the global file.
     This file contains only what is specific to THIS project.

     DISCIPLINE 2: Context Engineering — scoped to this project.
     Tells the agent everything it needs to KNOW about this repo.

     PLACEMENT: Copy to the root of your project repository (same level as .git/).
     Claude Code reads it automatically alongside your global CLAUDE.md.

     RELATED FILES (also in this project root):
       intent.md       — what the agent should optimize for
       constraints.md  — musts, must-nots, preferences, escalation triggers
       evals.md        — test cases and CI gate definitions
       domain-memory.md — dark factory backlog and progress log (if applicable)

     Delete placeholder comments before committing. -->

---

## Project Overview

- **Name:** [Project name]
- **Purpose:** [1–2 sentences: what problem does this solve, and for whom?]
- **Phase:** [Discovery / Build / Stabilize / Maintain]
- **Jira project key:** [e.g., PROJ — primary source for task specs and acceptance criteria]
- **Confluence space:** [e.g., https://yourorg.atlassian.net/wiki/spaces/PROJ]
- **Definition of success:** [What does "done" look like at the project level?]

---

## Technology Stack

<!-- Be specific — versions matter. The agent uses this to select idioms,
     avoid deprecated APIs, and match existing conventions. -->

- **Language(s):** [e.g., C# 13 / .NET 10, TypeScript 5.x]
- **Framework(s):** [e.g., ASP.NET Core Minimal API, Blazor Server]
- **Database:** [e.g., PostgreSQL 16 via EF Core 9]
- **UI library:** [e.g., Telerik UI for Blazor 6.x — see design.md if present]
- **Test framework:** [e.g., xUnit + FluentAssertions + Testcontainers]
- **CI/CD:** [e.g., GitHub Actions — see .github/workflows/ci.yml]
- **Package manager:** [e.g., NuGet / npm / pip]

---

## Architecture

<!-- Enough context for the agent to place any file in the mental model.
     Describe what is NOT obvious from reading the code. -->

- **Pattern:** [e.g., Vertical slice architecture — feature folders under src/Features/]
- **Entry points:** [e.g., `src/MyProject.Api/Program.cs`]
- **Key directories:**
  - `src/` — [what lives here]
  - `tests/` — [test project structure]
  - `infra/` — [IaC, migrations, scripts]
- **Non-obvious constraints:** [e.g., "No cross-feature imports — features are siblings, not parents"]

---

## Key Files

<!-- 5–8 files a new agent should read to orient itself.
     These are the files that explain the most about how the project works. -->

| File | Why It Matters |
|---|---|
| `[path/to/file]` | [What it reveals about the project] |
| `[path/to/file]` | |
| `[path/to/file]` | |

---

## Persistent Decisions

<!-- Log architectural and product decisions so the agent does not re-litigate them.
     Add a row every time a significant decision is made.
     The agent treats logged decisions as settled unless explicitly reopened. -->

| Date | Decision | Rationale |
|---|---|---|
| YYYY-MM-DD | NRT enabled project-wide (`<Nullable>enable</Nullable>`) | Single source of truth: C# nullability flows directly to EF model and DB schema. |
| YYYY-MM-DD | Optional multi-field data → owned entity on separate table | Vertical decomposition eliminates nullable columns and SQL 3VL from the principal table. |
| YYYY-MM-DD | Semantically distinct absence states → enum, not NULL | NULL collapses distinct states (pending/N/A/unknown) into one value; enums keep them queryable and readable. |
| YYYY-MM-DD | [e.g., Vertical slice over layered architecture] | [Why] |

---

## Open Loops

<!-- Unresolved questions the agent should surface proactively.
     Remove when resolved; add to Persistent Decisions above. -->

- [ ] [e.g., Caching strategy for [feature] not yet decided]
- [ ] [Open item]

---

## Team

| Name | Role | Notes |
|---|---|---|
| [Name] | [e.g., Tech Lead] | [e.g., reviews all PRs] |
| [Name] | [Role] | |

---

## Available Tools / MCP

<!-- Tools available beyond the global Claude Code defaults.
     Confirm MCP coverage before listing — unlisted tools are out of scope. -->

- [e.g., `mcp__jira` — read/write Jira issues for this project]
- [e.g., `mcp__confluence` — read Confluence pages in PROJ space]
- [e.g., `grounded-code-mcp` — local knowledge base; collection map and MCP tool signatures in global CLAUDE.md]

---

## Project Boot Ritual

At the start of every session:

1. Read this file (CLAUDE.md), `intent.md`, and `constraints.md`.
2. Check the active Jira issue for the current task spec and acceptance criteria.
3. If dark factory mode: read `domain-memory.md`.
4. Confirm context — state: current phase, active Jira issue (if any), top 3 constraints, open loops.
5. Do NOT begin work until context is confirmed.
