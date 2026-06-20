# [PROJECT NAME] — Domain Memory
<!-- Agent Harness State: Initializer + Worker Pattern
     Framework: Four Prompt Disciplines & Five Primitives (Nate B. Jones, v2026.03.2)

     FOR DARK FACTORY / MULTI-SESSION AGENTIC WORK ONLY.
     Not needed for single-session coding harness work.

     PATTERN:
     - Initializer runs ONCE: reads the approved spec (Jira/Confluence or spec.md),
       populates this file with a machine-readable task backlog, sets all items Failing.
     - Worker runs N times: reads this file on every boot, picks ONE Failing item,
       works atomically, updates status, exits.
     - The worker agent has NO persistent memory between runs. This file IS the memory.

     MEMORY HYGIENE:
     Before specifying what to store here, ask: what's worth remembering across sessions?
     What's noise that will create confusion in future runs?
     Accumulated context helps when it increases pattern recognition; it harms when it
     creates outdated assumptions. Review and prune the Progress Log regularly —
     stale context is worse than no context.

     Copy this template to your project root. The Initializer populates the backlog.
     Delete placeholder comments before committing. -->

---

## Project Goal

<!-- Single clear statement. The worker reads this on every boot.
     This should match the Primary Goal in intent.md exactly. -->

[STATE THE SINGLE OUTCOME THIS AGENT IS WORKING TOWARD]

---

## Feature / Task Backlog

<!-- Machine-readable backlog. Worker picks ONE Failing item per run,
     works on it atomically, updates status, then exits.
     Decomposition rule: each task must be independently executable and verifiable.
     If the worker needs to "remember" something from a previous task to do this one,
     the decomposition is incomplete — split it further.

     Status options: 🔴 Failing | ✅ Passing | 🔄 In Progress | 🚫 Blocked | ⏸ Deferred -->

| ID  | Task | Status | Pass Condition | Notes |
|-----|------|--------|----------------|-------|
| T01 | [Task] | 🔴 Failing | [How we know it's done — binary, verifiable] | |
| T02 | [Task] | 🔴 Failing | [Pass condition] | |
| T03 | [Task] | 🔴 Failing | [Pass condition] | |
| T04 | [Task] | 🔴 Failing | [Pass condition] | |
| T05 | [Task] | 🔴 Failing | [Pass condition] | |

---

## Scaffolding

<!-- How to operate this project. Worker reads this to understand the environment.
     Be explicit — the worker has no memory of previous setup steps. -->

- **How to run:** [e.g., `dotnet run --project src/MyProject`]
- **How to test:** [e.g., `dotnet test` or `pytest tests/`]
- **How to extend:** [Where to add new tasks, what conventions to follow]
- **Key files:** [List the 3–5 files most relevant to understanding the codebase]
- **Known blockers / constraints:** [Anything the worker must know to avoid dead ends]

---

## Worker Boot Ritual

<!-- Execute in this exact order on every run. No exceptions.
     The worker has no persistent memory between runs — this ritual IS the handoff. -->

1. Read this file (`domain-memory.md`) completely.
2. Read `constraints.md`.
3. Check the active Jira issue for any human updates or new comments since the last run.
4. Summarize: passing items, failing items, open blockers.
5. Select the ONE failing item with the lowest ID.
6. Work on it atomically. Run the tests. Do NOT move on until it passes or is explicitly Blocked.
7. Update the backlog status table above.
8. Append a progress log entry below.
9. Exit. Leave the codebase in a fully passing test state.

---

## Proactive Action Rules

<!-- For scheduled or autonomous agents only — delete this section if the agent is human-triggered.
     Defines what the agent may do autonomously on each run vs. what requires human confirmation.
     The agent MUST NOT act autonomously on irreversible actions without an explicit trigger defined here. -->

- **Autonomous (safe to execute without confirmation):**
  - [e.g., Read files, run tests, update backlog status]
  - [e.g., Append progress log entries]
  - [PROJECT-SPECIFIC AUTONOMOUS ACTION]

- **Requires human confirmation (irreversible or high-stakes):**
  - [e.g., Deploy to staging or production]
  - [e.g., Send external communications]
  - [e.g., Delete or overwrite data]
  - [PROJECT-SPECIFIC CONFIRMATION-REQUIRED ACTION]

---

## Rules of Engagement

- Work on **ONE item per run only** — never attempt multiple backlog items in a single run.
- Never mark ✅ Passing unless the Pass Condition in the backlog is verifiably met.
- If blocked, mark ⏸ Blocked, explain why in the Notes column, and surface to the human before exiting.
- **No regressions** — end every run with all previously-passing items still passing.
- Update the backlog status table and append a progress log entry before exiting.
- Leave the codebase in a clean, fully passing test state at the end of every run.

> At project scale, consider a planner/executor split: a planner agent reads the full backlog,
> selects and decomposes the next task, and spawns short-lived executor agents per subtask.
> The planner holds project context; executors hold only task context.

---

## Progress Log

<!-- Append after every run. Never delete entries.
     Review weekly and prune outdated assumptions from the backlog above.
     The progress log is how a new session understands what the previous sessions did. -->

### Run: YYYY-MM-DD HH:MM

- **Session intent:** [What this run was trying to accomplish]
- **Items attempted:** [T01, T02]
- **Items completed:** [T01 — now ✅ Passing]
- **Items blocked:** [T02 — blocked on X; see Notes column]
- **Decisions made:** [Any architectural or implementation choices made during this run]
- **Open questions:** [Anything that needs human input before the next run]
