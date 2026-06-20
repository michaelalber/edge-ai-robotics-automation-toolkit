# Edge-AI / Robotics / Automation Toolkit — Evals
<!-- Acceptance criteria an independent observer can verify without asking questions.
     Structural checks are mechanical; quality checks require reading the skill. -->

---

## Structural Evals (mechanical — must all pass)

| # | Criterion | Check | Expected |
|---|-----------|-------|----------|
| S1 | Skill count | `find skills -name SKILL.md \| wc -l` | `11` |
| S2 | Professional skills | `ls skills/professional \| wc -l` | `7` |
| S3 | Team skills | `ls skills/team \| wc -l` | `4` |
| S4 | Every skill has ≥ 2 references | `for d in skills/*/*/; do [ "$(ls "$d"references 2>/dev/null \| wc -l)" -ge 2 ] \|\| echo "FAIL $d"; done` | no output |
| S5 | Agent parity | `find claude/agents -name '*.md' \| wc -l` == `find opencode/agents -name '*.md' \| wc -l` | both `3` |
| S6 | Agent `skills:` references resolve | every skill named in an agent's `skills:` frontmatter exists under `skills/` | all resolve |
| S7 | No global config shipped | `claude/global/` and `opencode/global/` contain only `.gitkeep` | true |
| S8 | No placeholder text | `grep -rIl 'TODO\|\[fill in\]' skills claude opencode` | no output |
| S9 | Install scripts executable | `test -x scripts/install-claude.sh && test -x scripts/install-opencode.sh && test -x scripts/install-pi.sh` | exit 0 |

## Quality Evals (require reading — pass/fail per skill)

| # | Criterion |
|---|-----------|
| Q1 | Every device-facing skill names a specific target (Jetson Orin Nano, Raspberry Pi, Picar-X, …), not "an edge device". |
| Q2 | Every device-facing skill names the protocol/runtime it uses (TensorRT, TFLite, I2C/SPI/UART/GPIO, Ollama). |
| Q3 | `model-optimization` measures accuracy cost, not just size/latency reduction. |
| Q4 | No skill instructs calling PyTorch's eval-mode method by name (use `model.train(False)`); the security hook would block it. |
| Q5 | Each skill's Integration section references only skills that exist (here or in ai-toolkit), with no dangling pointers. |
| Q6 | State-block XML tags are unique across this repo and ai-toolkit. |

## Migration Evals (one-time — the move out of ai-toolkit)

| # | Criterion |
|---|-----------|
| M1 | ai-toolkit no longer contains: model-optimization, rag-pipeline-dotnet, rag-pipeline-python, ollama-model-workflow, mcp-server-scaffold. |
| M2 | ai-toolkit no longer contains the model-optimization-agent (claude + opencode). |
| M3 | ai-toolkit's `README.md`, `AGENTS.md`, and `pi/SKILLS-local.md` counts/tables reflect the removals. |
| M4 | No skill remaining in ai-toolkit references a moved skill in its Integration section without that being updated. |

---

## Done means

All structural evals pass, all quality evals pass for every skill, and all migration evals pass.
A green test suite is not enough — a skill that scaffolds code which will not run on the named
hardware fails Q1–Q3 even if every file is well-formed.
