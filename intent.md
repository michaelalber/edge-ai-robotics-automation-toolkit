# Edge-AI / Robotics / Automation Toolkit — Intent
<!-- Discipline 3: Intent Engineering
     PROJECT-LEVEL FILE — supplements ai-toolkit's global standards.
     This file tells the agent what to OPTIMIZE FOR when working on this repository.
     Project context (what to know) lives in the root CLAUDE.md / AGENTS.md. -->

---

## Relationship to ai-toolkit

This repository is a **domain supplement** to [ai-toolkit](../ai-toolkit). ai-toolkit
covers general software development and engineering; this toolkit covers **Local AI,
Edge AI, ML, Robotics, and Industrial Automation**. The two share one set of global
standards (security, commit format, code quality, the 5-section lean skill layout, the
agent template) — those live in ai-toolkit and are **not duplicated here**. A user
installs ai-toolkit for the base, and this toolkit on top when they work in these domains.

---

## Primary Goal

Give engineers working on edge devices, robots, sensors, and local model deployments a
set of installable, opinionated skills and agents that encode the procedures these
domains get wrong most often — model optimization without accuracy regression, sensor
calibration and drift detection, safe fleet rollouts, and local LLM/RAG plumbing.

---

## Values (What We Optimize For)

1. **Correctness on real hardware** — a skill that scaffolds code that will not run on a
   Jetson, Pi, or PLC is worse than no skill. Procedures must match the actual device,
   protocol, and runtime.
2. **Quality** — every skill follows the 5-section lean layout (depth in `references/`);
   every agent follows the agent template and exists in both Claude Code and OpenCode form.
3. **Consistency with ai-toolkit** — same formats, same conventions, same install model.
   No divergent patterns just because the domain is different.
4. **Usability** — skills work out of the box on the named hardware; no configuration guessing.
5. **Speed of delivery** — lowest priority; never trade correctness or quality for it.

---

## Tradeoff Rules

| Conflict | Resolution |
|---|---|
| Speed vs. correctness | Correctness. Edge/robotics bugs surface on physical hardware, far from a debugger. |
| Hardware-specific vs. generic guidance | Hardware-specific. Name the device, protocol, and runtime; generic edge advice is low-value. |
| Completeness vs. brevity | Completeness for skill/agent bodies; brevity for frontmatter descriptions. |
| Claude Code vs. OpenCode parity | Keep both versions. If parity is temporarily broken, document it in the agent file. |
| Duplicating ai-toolkit globals vs. referencing | Reference. Never copy the universal standards stack into this repo. |

---

## Decision Boundaries

### Decide Autonomously
- Formatting and structure within the 5-section lean layout
- Which references to include in a skill's `references/` directory
- Wording of skill descriptions and trigger phrases
- File naming within established conventions

### Escalate to Human
- Adding a skill suite or agent category not currently represented (e.g., a new robotics platform)
- Changing the 5-section lean layout or agent template (these are owned by ai-toolkit)
- Breaking Claude Code / OpenCode parity intentionally
- Moving a skill back to ai-toolkit, or pulling a new one in from it
- Naming a specific hardware vendor's proprietary SDK as a hard dependency without a fallback

---

## What "Good" Looks Like

- A skill that names the exact device/protocol/runtime, follows the 5-section lean layout
  (≤ 200 lines, depth in `references/`, ≥ 2 reference files), and has a unique state-block tag
- An agent present in both `claude/agents/` and `opencode/agents/` with consistent behavior,
  whose `skills:` frontmatter references only skills that exist in this toolkit
- Hardware claims that are verifiable: a power mode that exists on the named board, a protocol
  pin-out that matches the datasheet, a quantization step that preserves a stated accuracy bound

---

## Anti-Patterns (What Bad Looks Like)

- Generic "edge AI best practices" with no named hardware, protocol, or runtime
- A skill whose `references/` directory has fewer than 2 files
- An agent added to one platform but not the other
- A state-block XML tag that collides with one already used in ai-toolkit or this repo
- Duplicating ai-toolkit's global standards files into this repository
- A model-optimization step that shrinks the model without measuring the accuracy it costs

---

## Persistent Decisions

See `AGENTS.md` § Persistent Decisions.

## Open Loops

See `AGENTS.md` § Open Loops.
