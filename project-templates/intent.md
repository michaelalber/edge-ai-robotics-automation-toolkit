# [PROJECT NAME] — Intent
<!-- Discipline 3: Intent Engineering (v2026.03.2)
     Framework: Four Prompt Disciplines & Five Primitives (Nate B. Jones)

     PURPOSE: Tells the agent what to OPTIMIZE FOR.
     Context (AGENTS.md) tells the agent what to know.
     Intent tells it what to want.

     For software development projects this file may be replaced by an
     ## Intent section directly in the project's AGENTS.md.
     Use a separate intent.md when intent is complex, contested, or needs
     to be versioned independently of context.

     Copy this template to your project root and fill in every section.
     Delete placeholder comments before committing. -->

---

## Agent Architecture

<!-- Select the architecture BEFORE writing acceptance criteria or decomposing tasks.
     This determines which project-template files apply and how the agent operates.

     Diagnostic: Is this problem software-shaped (needs working code or documents)
     or metric-shaped (needs a rate or measure optimized)?

     | Architecture    | Description                                              | Use When                        |
     |-----------------|----------------------------------------------------------|---------------------------------|
     | Coding harness  | Single agent; human reviews each output before merging   | Task-level features, bug fixes  |
     | Dark factory    | Autonomous spec-to-eval loop; human at spec + eval only  | Multi-session project work      |
     | Auto research   | LLM as optimizer against a measurable metric             | Metric-shaped problems          |
     | Orchestration   | Role-specialized agents with explicit handoff contracts  | Multi-domain workflows at scale |

     Files required per architecture:
     - Coding harness: CLAUDE.md / AGENTS.md + intent.md + constraints.md + evals.md
     - Dark factory:   above + domain-memory.md
     - Auto research:  replace evals.md with metric definition + dataset + experiment protocol
     - Orchestration:  replace decomposition with a handoff contract table per agent role -->

**This project uses:** [Coding harness / Dark factory / Auto research / Orchestration]

**Reason:** [One sentence — why this architecture fits this project's scope and cadence]

---

## Primary Goal

<!-- What is this project ultimately trying to achieve?
     Write it as an OUTCOME, not a task.
     Bad:  "Build a dashboard for Q3 metrics."
     Good: "Enable the ops team to detect anomalies within 60 seconds of
           an event, reducing mean time to resolution by 40%." -->

[STATE THE OUTCOME HERE]

---

## Values (What We Optimize For)

<!-- Rank these in priority order. Be explicit about the hierarchy.
     The agent will use this to break ties when values conflict.
     Without this you get metric gaming: the agent picks a value
     implicitly, and it is rarely the right one (see: Klarna). -->

1. [Highest priority — e.g., Correctness]
2. [Second priority — e.g., Security]
3. [Third priority — e.g., Maintainability]
4. [Fourth priority — e.g., Performance]
5. [Lowest priority — e.g., Speed of delivery]

---

## Tradeoff Rules

<!-- When values conflict, how should the agent resolve them?
     Be explicit. An agent without these rules will resolve conflicts
     arbitrarily. Each row is a decision the agent can make autonomously. -->

| Conflict | Resolution |
|---|---|
| Speed vs. correctness | Default to correctness. Flag explicitly if timeline requires compromise. |
| Completeness vs. brevity | Prefer brevity unless depth is explicitly requested. |
| [Project-specific conflict] | [Resolution] |
| [Project-specific conflict] | [Resolution] |

---

## Decision Boundaries

### Decide Autonomously

<!-- Things the agent can do without asking. Be specific.
     Generic entries ("formatting choices") are fine here. -->

- Formatting, structure, naming within established project conventions
- Tool selection for read-only exploration
- Refactoring within the approved, scoped task
- [Project-specific autonomous decision]

### Escalate to Human

<!-- Situations where the agent MUST stop and ask.
     Think: what could a smart, well-intentioned agent do that would
     technically satisfy the request but produce the wrong outcome?
     Those failure modes belong here as escalation triggers. -->

- Any output intended for external distribution (emails, reports, docs)
- Any irreversible action (delete, deploy, force-push, send)
- Any request that contradicts a logged decision in this project's AGENTS.md
- Scope changes beyond the stated task
- When acceptance criteria cannot be met within stated constraints
- [Project-specific escalation trigger]
- [Project-specific escalation trigger]

---

## What "Good" Looks Like

<!-- Describe a top-10% output for this project.
     Your judgment about what "correct" looks like IS the value.
     Encode it here so the agent can self-evaluate before delivering.
     Nate B. Jones: "Your judgment about which of 17 analyses is correct
     IS the value. Encode it here." -->

A good output for this project:

- [Quality dimension 1 — e.g., "Cites sources and links directly to the relevant code or doc"]
- [Quality dimension 2 — e.g., "Flags risks proactively, not reactively"]
- [Quality dimension 3 — e.g., "Produces working code on the first attempt within the defined scope"]

---

## Anti-Patterns (What Bad Looks Like)

<!-- What would a technically correct but organizationally wrong output
     look like? These are the failure modes to reject.
     Every entry here should trace back to an actual past rejection or
     a specific risk you've identified. -->

- [e.g., Answers that look professional but lack specificity to this project's context]
- [e.g., Recommendations that optimize for speed at the expense of correctness]
- [e.g., Completing the literal request while missing the actual intent]

---

## Persistent Decisions

<!-- Log key decisions so the agent does not re-litigate them.
     Add a row every time a significant architectural or product decision
     is made. The agent treats logged decisions as settled. -->

| Date | Decision | Rationale |
|---|---|---|
| YYYY-MM-DD | [Decision] | [Why] |

---

## Open Loops

<!-- Things unresolved that the agent should surface proactively.
     Check this list at the start of every session.
     Remove items when resolved; add them to Persistent Decisions above. -->

- [ ] [Open item — e.g., "Architecture decision for caching layer not yet made"]
- [ ] [Open item]
