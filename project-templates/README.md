# Project Templates

Per-project context files for AI coding agents. Copy the relevant files into your project root — they give agents the persistent context they need to operate effectively across sessions and after context resets.

## Framework

These templates implement the **Four Prompt Disciplines & Five Primitives** framework by [Nate B. Jones](https://natesnewsletter.substack.com/). The core insight: a well-structured information environment transforms an AI from a capable autocomplete into a reliable engineering partner.

The four disciplines, in order:

| # | Discipline | Question it answers | File |
|---|-----------|---------------------|------|
| 1 | **Prompt Craft** | Am I asking clearly? | Your prompt |
| 2 | **Context Engineering** | What does the agent need to *know*? | `CLAUDE.md` / `AGENTS.md` |
| 3 | **Intent Engineering** | What should the agent *optimize for*? | `intent.md` |
| 4 | **Specification Engineering** | What does *done* look like? | `constraints.md`, `evals.md` |

Disciplines 1–3 are table stakes. Discipline 4 is what enables autonomous, multi-session work.

---

## Files

| File | Discipline | Purpose | Required |
|------|-----------|---------|---------|
| `CLAUDE.md` | Context | Project context for Claude Code: stack, architecture, key files, boot ritual | Every project using Claude Code |
| `AGENTS.md` | Context | Same as above for OpenCode / Pi — auto-discovered from project root | Every project using OpenCode or Pi |
| `SYSTEM.md` | Prompt | Pi-specific: replaces or appends to Pi's default system prompt. Two variants in one file — delete the one you don't need. Copy from `pi/global/SYSTEM.md`. | Pi projects only |
| `intent.md` | Intent | What the agent optimizes for: goal, value hierarchy, tradeoff rules, decision boundaries | Every project |
| `constraints.md` | Specification | Musts, must-nots, preferences, escalation triggers | Every project |
| `evals.md` | Specification | Test cases, CI gate definitions, taste rules, rejection log | Every project |
| `domain-memory.md` | Agent state | Dark factory backlog and progress log — read on every boot | Multi-session agentic work only |
| `design.md` | Context | Design system tokens, component hierarchy, interaction patterns | UI-heavy projects only |

**Minimum viable set:** `CLAUDE.md` (or `AGENTS.md`) + `intent.md` + `constraints.md` + `evals.md`.

**Pi minimum set:** `AGENTS.md` + `SYSTEM.md` + `intent.md` + `constraints.md` + `evals.md`. For 7B models, keep all files lean — strip comment blocks before committing; every token loads on session boot.

Specs (problem statements, acceptance criteria, task decomposition) live in **Jira / Confluence** — not in a local file. Link to the relevant issue or page from `CLAUDE.md`.

---

## Agent Architecture Selection

Before filling in `intent.md`, decide which architecture fits your project. This determines which files apply and how the agent operates.

| Architecture | Description | Files needed |
|---|---|---|
| **Coding harness** | Single agent; human reviews every output before merging | Minimum set |
| **Dark factory** | Autonomous spec-to-eval loop; human only at spec and eval | Minimum set + `domain-memory.md` |
| **Auto research** | LLM optimizer against a measurable metric | Minimum set + metric + dataset |
| **Orchestration** | Role-specialized agents with explicit handoff contracts | Minimum set + handoff contract |

**Diagnostic:** Is the problem *software-shaped* (needs working code or documents) or *metric-shaped* (needs a rate or measure optimized)? Software-shaped → coding harness or dark factory. Metric-shaped → auto research.

---

## Usage

```bash
# Copy the minimum set into your project root
cp project-templates/CLAUDE.md   /path/to/your-project/CLAUDE.md
cp project-templates/intent.md   /path/to/your-project/intent.md
cp project-templates/constraints.md /path/to/your-project/constraints.md
cp project-templates/evals.md    /path/to/your-project/evals.md

# Add for dark factory / multi-session work
cp project-templates/domain-memory.md /path/to/your-project/domain-memory.md
```

Then fill in every placeholder. Delete comment blocks before committing — they cost tokens on every request.

---

## Global vs. Project Files

These templates are **project-level** files. They do not replace your global config:

| Scope | File | Lives in |
|-------|------|---------|
| Global | `CLAUDE.md` / `AGENTS.md` | `~/.claude/` or `~/.config/opencode/` or `~/.pi/agent/` |
| Project | `CLAUDE.md` / `AGENTS.md` | Project root |

Global files carry universal standards (coding style, security rules, quality gates). Project files carry what is specific to this codebase — stack, architecture, key files, active decisions. Do not duplicate global rules in project files.
