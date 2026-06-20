# [PROJECT NAME] — Constraints
<!-- Discipline 4: Specification Engineering — Primitive 3: Constraint Architecture
     Framework: Four Prompt Disciplines & Five Primitives (Nate B. Jones, v2026.03.2)

     PURPOSE: Defines what the agent MUST do, MUST NOT do, should PREFER when
     multiple valid approaches exist, and what it must ESCALATE rather than decide.

     Quality test for every line: "Would removing this cause the agent to make
     mistakes?" If the answer is no, cut it. High-signal, low-noise.

     Copy this template to your project root. Fill in project-specific entries
     under each section. Delete placeholder comments before committing. -->

---

## Must Do

<!-- Non-negotiable behaviors. These are unconditional — no exceptions.
     Seed: what must always happen regardless of context? -->

- Load and confirm context (AGENTS.md, intent.md or ## Intent section, constraints.md) before every session.
- Read the active Jira issue / Confluence spec before beginning any in-flight task.
- Write three verifiable acceptance criteria before delegating any significant subtask.
- Confirm understanding before executing any irreversible action (delete, deploy, send, push).
- End every agentic run with a passing test state and an updated domain-memory.md (dark factory only).
- Add a `# VERIFY:` comment rather than guess when uncertain about a function signature, API, or behavior.
- Enable `<Nullable>enable</Nullable>` project-wide before writing any entity or migration.
- Use `required` keyword (C# 11+) for required reference-type properties on entities.
- For optional multi-field data (e.g., address, profile): use an owned entity on a separate table (`OwnsOne(..., pb => pb.ToTable(...))`) — not nullable columns on the main table.
- Encode semantically distinct absence states (Pending, N/A, Unknown) as an enum property — not as a nullable column.
- Owned entities sharing a table with their principal must have at least one `required` property so EF Core can detect presence vs. all-null absence.
- Initialize collection navigations to empty (`= new List<T>()`) — never leave them nullable.
- [PROJECT-SPECIFIC MUST]
- [PROJECT-SPECIFIC MUST]

---

## Must NOT Do

<!-- Hard prohibitions. Same quality test: earn your place.
     Seed: what would a well-intentioned agent do that would technically
     satisfy the request but produce the wrong outcome? -->

- Do not begin a task that has no verifiable acceptance criteria.
- Do not re-litigate decisions already logged in AGENTS.md or intent.md Persistent Decisions.
- Do not exceed the scope defined in the active Jira issue / spec without explicit human approval.
- Do not hardcode secrets, tokens, or credentials — use environment variables or a secrets manager.
- Do not commit generated files, build artifacts, or .env files.
- Do not move a Jira issue to Done or Closed — that is a human action only.
- For each tool or data source this agent needs: confirm it has an MCP interface, or computer-use
  is explicitly enabled as a fallback. Tools covered by neither are out of scope for agent execution.
- Do not add nullable columns to distinguish "unknown" from "not applicable" — they collapse to a single NULL value and corrupt aggregates via SQL three-valued logic.
- Do not create an optional owned entity on a shared table without at least one required property (EF Core 6+ will warn or throw; the query result is unpredictable before that).
- Do not use `= NULL` in raw SQL predicates — use `IS NULL` / `IS NOT NULL`.
- Do not make a reference-type navigation property nullable purely to suppress compiler warnings — use `= null!` with the null-forgiving operator and document why.
- [PROJECT-SPECIFIC PROHIBITION]
- [PROJECT-SPECIFIC PROHIBITION]

---

## Preferences

<!-- When multiple valid approaches exist, default to these.
     These are tie-breakers, not mandates. The agent may deviate with justification. -->

- Prefer brevity over completeness unless depth is explicitly requested.
- Prefer asking one clarifying question over assuming and proceeding.
- Prefer flagging a problem before executing a workaround.
- Prefer editing an existing file over creating a new one.
- Prefer the grounded-code-mcp knowledge base over training data for language-specific idioms.
- [PROJECT-SPECIFIC PREFERENCE]
- [PROJECT-SPECIFIC PREFERENCE]

---

## Escalate Rather Than Decide

<!-- Situations where the agent must stop and surface to the human.
     Source: your open-promise inventory — any commitment that, if missed,
     would require human judgment to remediate.
     Agents can execute; they should escalate when a commitment is at risk
     of lapsing in a way that requires your name on it. -->

- Any output intended for external distribution (emails, reports, stakeholder docs).
- Any action that conflicts with a logged Persistent Decision in AGENTS.md.
- Any request where acceptance criteria cannot be met within stated constraints.
- More than one consecutive failing subtask in domain-memory.md (dark factory only).
- Any security-relevant decision not explicitly covered by existing constraints.
- [PROJECT-SPECIFIC ESCALATION TRIGGER]
- [PROJECT-SPECIFIC ESCALATION TRIGGER]

---

## Code Quality Gates

<!-- Thresholds the agent must not violate when generating or modifying code.
     Defaults mirror global CLAUDE.md / AGENTS.md targets — override here per project if needed.
     The agent flags any output that would breach these before delivering it. -->

- **Test coverage (business logic):** ≥ [80]% — run `[test command with coverage flag]`
- **Test coverage (security-critical paths):** ≥ [95]%
- **Cyclomatic complexity (per method):** < [10]
- **Code duplication:** ≤ [3]%
- **Commit format:** Conventional Commits — `feat:`, `fix:`, `refactor:`, `chore:`, `test:`, `docs:`
- **Commit scope:** Atomic — one logical change per commit; no bundling unrelated changes
- [PROJECT-SPECIFIC GATE]
