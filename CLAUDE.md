# CLAUDE.md — edge-ai-robotics-automation-toolkit

A **domain supplement** to [ai-toolkit](../ai-toolkit), covering Local AI, Edge AI, ML,
Robotics, and Industrial Automation. See [AGENTS.md](AGENTS.md) for the full inventory,
conventions, and persistent decisions.

> **Global standards live in ai-toolkit.** Security rules, commit format, code quality
> gates, the 5-section lean skill layout, and the agent template are shared and installed
> from ai-toolkit. This repo does not duplicate them — it adds skills and agents on top.

---

## Quick Reference

- **Skills:** `skills/{professional,team}/<name>/SKILL.md` — 5-section lean layout, depth in `references/`
- **Agents:** `claude/agents/professional/<name>.md` (Claude Code) | `opencode/agents/professional/<name>.md` (OpenCode) — must stay in parity
- **Local-inference triage:** `pi/SKILLS-local.md` — Green/Yellow/Red rating per skill for Pi + Ollama
- **Project templates:** `project-templates/` — copy into target project roots
- **Global config:** ships with ai-toolkit, not here (`claude/global/`, `opencode/global/` are empty placeholders)

---

## Inventory

| | Count |
|--|-------|
| Skills (professional) | 7 |
| Skills (team) | 4 |
| Agents (Claude Code) | 3 |
| Agents (OpenCode) | 3 |

**Professional skills:** anomaly-detection, edge-cv-pipeline, fleet-management, jetson-deploy,
model-optimization, picar-x-behavior, sensor-integration
**Team skills:** mcp-server-scaffold, ollama-model-workflow, rag-pipeline-dotnet, rag-pipeline-python
**Agents:** model-optimization-agent, fleet-deployment-agent, sensor-anomaly-agent

---

## Contributor Validation

No compiled artifacts. Validation is structural.

```bash
# Count skills
find skills -name "SKILL.md" | wc -l            # expect 11

# Each skill has ≥ 2 reference files
for d in skills/*/*/; do echo "$(ls "$d/references" 2>/dev/null | wc -l) $d"; done

# Agent parity (counts must match)
find claude/agents   -name "*.md" | wc -l        # expect 3
find opencode/agents -name "*.md" | wc -l        # expect 3

# Every agent's skills: frontmatter references a skill that exists here
grep -rhA10 '^skills:' claude/agents | grep '^\s*- ' | sort -u
```

## When Adding a Skill

1. Choose a tier — `professional` (domain-expert) or `team` (broadly useful) — set it in `audience:` frontmatter.
2. Follow the 5-section lean layout; SKILL.md ≤ 200 lines; ≥ 2 files in `references/`.
3. Name the hardware, protocol, and runtime explicitly for any device-facing skill.
4. Give the skill a unique state-block XML tag (unique across this repo **and** ai-toolkit).
5. If it needs an autonomous executor, add an agent in **both** `claude/agents/` and `opencode/agents/`.
6. Update counts/tables in `README.md` and `AGENTS.md`; add a Green/Yellow/Red row in `pi/SKILLS-local.md`.

## Global File Caution

This repo ships **no** global files. If a change genuinely belongs in the global standards
(security, commit format, code quality, skill/agent templates), make it in **ai-toolkit** —
those files install to `~/.claude/`, `~/.config/opencode/`, and `~/.pi/agent/` and affect
every project on the user's machine.
