# Edge-AI / Robotics / Automation Skills on Local Inference (Pi + Ollama) — Triage

Classifies every skill in this toolkit's `skills/` tree by how well it performs under
**Pi on a local Ollama model** (weaker at planning, sustained multi-turn coherence, and
judgment than a frontier cloud model; smaller context window).

**This is a routing guide, not a fork.** The skill format is identical across Claude Code,
OpenCode, and Pi (the Agent Skills standard). Skills ship from the single `skills/` source tree.

> The shared Pi global config (Modelfiles, `models.json`, `AGENTS.md`) lives in **ai-toolkit**.
> Install it first; this toolkit only adds the skills triaged below.

---

## Legend

| Tier | Meaning | Action |
|------|---------|--------|
| 🟢 **Green** | Bounded, procedural, single-pass — encodes a checklist/template the model executes. *More* valuable locally; it offloads planning. | Ship as-is. |
| 🟡 **Yellow** | Single-pass but reasoning-, judgment-, or reference-heavy. Works locally, output shallower. | Ship; author a lite variant for heavy-use ones. |
| 🔴 **Red** | Long multi-phase autonomous loops or device-control side effects unsafe to run unattended locally. | Drive interactively, or run on cloud. |

**Flags:** 📚 depends on `grounded-code-mcp` (degrades to training-data fallback if absent) ·
⚙️ produces or controls real hardware side effects (deploys, motor/GPIO actuation) — extra caution locally.

---

## 🟢 Green — ship as-is (4)

| Skill | Flags | Why it fits local |
|-------|-------|-------------------|
| `mcp-server-scaffold` | | FastMCP template; deterministic structure |
| `ollama-model-workflow` | | Local LLM mgmt — *purpose-built* for this setup |
| `sensor-integration` | 📚 | Protocol wiring (I2C/SPI/UART/GPIO) is template-driven; bounded |
| `jetson-deploy` | 📚 ⚙️ | TensorRT conversion + power-mode steps are a fixed checklist (the deploy step itself is ⚙️ — confirm before running on a live board) |

---

## 🟡 Yellow — usable, author a lite variant if heavily used (5)

| Skill | Flags | Local caveat |
|-------|-------|--------------|
| `model-optimization` | 📚 | Quantization/benchmark workflow; multi-step, accuracy judgment is shallower locally |
| `edge-cv-pipeline` | 📚 | Multi-stage build (capture → infer → publish); reference-heavy |
| `anomaly-detection` | 📚 | Statistical method selection needs judgment; the alert tree is mechanical |
| `rag-pipeline-python` | 📚 | Multi-step build — but Ollama-native, so a good local fit |
| `rag-pipeline-dotnet` | 📚 | Multi-step Semantic Kernel build; reference-heavy |

---

## 🔴 Red — drive interactively or run on cloud (2)

| Skill | Flags | Why not unattended-local |
|-------|-------|--------------------------|
| `fleet-management` | ⚙️ | Coordinates rollouts across many devices with rollback logic; coherence + real side effects exceed unattended 32B safety |
| `picar-x-behavior` | ⚙️ | Composes behaviors that actuate motors/steering; a drifting local loop driving hardware is unsafe. Drive one behavior at a time. |

---

## Cross-cutting notes

- **`grounded-code-mcp` (📚 — 7 of 11 skills).** These cite the `edge_ai`, `robotics`, and
  `automation` collections. The server is itself local, so running it on the same machine keeps
  these skills fully grounded offline. Without it they fall back to training data — acceptable for
  scaffolders, risky for `model-optimization` where the grounded procedure *is* the value.
- **Hardware side effects (⚙️).** `jetson-deploy`, `fleet-management`, and `picar-x-behavior` can
  actuate real hardware. Never run them in an unattended local loop; confirm each action.

> Counts: 🟢 4 · 🟡 5 · 🔴 2 = 11. Revisit when skills are added/removed or the primary local model changes.
