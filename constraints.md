# Edge-AI / Robotics / Automation Toolkit — Constraints
<!-- PROJECT-LEVEL FILE — supplements ai-toolkit's global standards.
     Global standards (security, commit format, code quality) apply unconditionally
     and live in ai-toolkit. This file adds constraints specific to this repository. -->

---

## Must Do

- Read `AGENTS.md` (root), `intent.md`, and this file before beginning any task.
- Follow the 5-section lean layout for skills (the layout is owned by ai-toolkit; use any
  existing skill here as a reference). Keep `SKILL.md` ≤ 200 lines; push depth (principle
  tables, anti-patterns, device specs, error recovery, templates) to `references/`.
- Follow the agent template exactly — both Claude Code and OpenCode versions must be present.
- Ensure every new skill has a `references/` directory with at least 2 supporting files.
- Ensure every new state-block XML tag is unique across this repo **and** ai-toolkit before committing.
- Keep `claude/agents/` and `opencode/agents/` versions in sync — behavior identical, formats differ.
- Update skill/agent counts whenever a skill or agent is added or removed:
  - `README.md`: skills/agents badges and the at-a-glance table
  - `AGENTS.md` (root): the inventory section and skill suite table
- Triage every new skill in `pi/SKILLS-local.md` with a Green / Yellow / Red rating and a one-line rationale.
- Name the target hardware, protocol, and runtime explicitly in any device-facing skill.

---

## Must NOT Do

- Do not leave placeholder text ("TODO", "[fill in]") in any committed skill or agent file.
- Do not reuse a state-block XML tag already used by another skill or agent (here or in ai-toolkit).
- Do not add an agent to `claude/agents/` without a matching `opencode/agents/` entry
  (unless explicitly marked single-platform with a documented reason).
- Do not duplicate ai-toolkit's global standards files (`claude/global/CLAUDE.md`,
  `opencode/global/AGENTS.md`, `pi/global/*`) into this repository. Reference them instead.
- Do not call PyTorch's evaluation-mode method in Python examples — the security hook triggers on
  that string. Use `model.train(False)` instead.
- Do not move a skill or agent without updating all cross-references in `AGENTS.md`, `README.md`,
  `pi/SKILLS-local.md`, and any skill that references it in its Integration section.
- Do not hardcode a vendor SDK path or device serial as a required value with no fallback.

---

## Preferences

- Prefer editing an existing skill over creating a new one when the use case overlaps significantly.
- Prefer adding to `references/` over embedding long reference content inline in `SKILL.md`.
- Prefer the grounded-code-mcp knowledge base (`edge_ai`, `robotics`, `automation` collections)
  over training data for hardware APIs, ML procedures, and protocol details.
- When both Claude Code and OpenCode versions need updating, update them in the same commit.

---

## Escalate Rather Than Decide

- Any proposal to change the 5-section lean layout or the agent template (owned by ai-toolkit).
- Adding a new hardware platform, robotics SDK, or agent category not currently represented.
- Moving a skill between this toolkit and ai-toolkit.
- Any change to install scripts (`scripts/`) that affects installation target paths.
- Breaking Claude Code / OpenCode agent parity intentionally.

---

## File Architecture Constraints

| Level | Owner | Scope |
|-------|-------|-------|
| **Global** (`claude/global/CLAUDE.md`, `opencode/global/AGENTS.md`, `pi/global/*`) | **ai-toolkit** | All projects on the user's machine |
| **Project** (`CLAUDE.md`, `AGENTS.md` at this repo root) | this repo | This repository only |
| **Templates** (`project-templates/`) | shared copy | Users copy into their own project roots |

- This repository does **not** ship global config. It layers skills and agents on top of
  ai-toolkit's global stack. The `claude/global/` and `opencode/global/` directories here are
  intentionally empty placeholders.
