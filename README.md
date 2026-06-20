# Edge-AI · Robotics · Automation Toolkit

[![License: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)
[![Skills](https://img.shields.io/badge/skills-11-blue)](#skills)
[![Agents](https://img.shields.io/badge/agents-3-blue)](#agents)
[![Platforms](https://img.shields.io/badge/platforms-Claude%20Code%20%7C%20OpenCode%20%7C%20Pi-informational)](#platforms)
[![Domains](https://img.shields.io/badge/domains-Edge%20AI%20%C2%B7%20Robotics%20%C2%B7%20Automation-8A2BE2)](#skills)
[![Supplements](https://img.shields.io/badge/supplements-ai--toolkit-orange)](../ai-toolkit)

**11 skills and 3 agents for Local AI, Edge AI, ML, Robotics, and Industrial Automation** —
model optimization for constrained devices, sensor integration and anomaly detection, edge
computer vision, robot behavior composition, fleet deployment, and local LLM/RAG plumbing.

Works with [Claude Code](https://claude.ai/code), [OpenCode](https://opencode.ai/), and
[Pi](https://pi.dev) (Ollama local models).

---

## Why this exists

I work across enterprise software **and** the physical/edge stack — Jetson and Raspberry Pi
devices, robots, sensors, PLCs, and locally-hosted models. My general software-engineering
skills live in [**ai-toolkit**](../ai-toolkit). This repository is the **domain supplement**:
the skills and agents that only make sense when there's a device, a sensor bus, or a local
model in the loop.

The two are designed to be used together. Install ai-toolkit for the engineering base; add this
toolkit when your work touches edge AI, robotics, or automation. If you never leave the data
center, you only need ai-toolkit.

```
ai-toolkit  ─────────────────────────►  general software dev & engineering (base)
                                          + global standards, hooks, harness config
edge-ai-robotics-automation-toolkit ──►  Local AI · Edge AI · ML · Robotics · Automation (this repo)
                                          layered on top — no duplicated globals
```

---

## How it works

Two primitives, same format as ai-toolkit:

**Skills** — structured, opinionated prompt files that encode domain procedure. Model-invoked.
Live in `skills/{professional,team}/<name>/SKILL.md`, with depth in each skill's `references/`.

**Agents** — autonomous (or approval-gated) executors that pair a skill with tools and
guardrails. Live in `claude/agents/` and `opencode/agents/`, kept in platform parity.

> **No global config here.** The universal standards (security, commit format, code-quality
> gates) and the skill/agent templates are shared and ship with ai-toolkit. This repo does not
> duplicate them — `claude/global/` and `opencode/global/` are intentionally empty placeholders.

---

## Skills

### Professional — domain-expert, hardware-specific

| Skill | What it does |
|-------|--------------|
| **anomaly-detection** | Statistical anomaly detection for sensor streams — outlier detection, drift monitoring, classification, and alert/recalibration decision trees |
| **edge-cv-pipeline** | OpenCV + TFLite computer-vision pipelines for Jetson and Raspberry Pi — camera capture, optimized inference, result publishing |
| **fleet-management** | Rolling deployment strategies, multi-device coordination, and rollback triggers for edge device fleets |
| **jetson-deploy** | Deploy and optimize on Jetson Orin Nano with TensorRT — environment setup, model conversion, power modes, containerization |
| **model-optimization** | Quantization, pruning, format conversion (TensorRT/TFLite/ONNX), and accuracy/latency benchmarking for constrained devices |
| **picar-x-behavior** | Composable robot behaviors for SunFounder Picar-X — autonomous driving, sensor-reactive patterns, behavior trees |
| **sensor-integration** | Sensor data pipelines over I2C/SPI/UART/GPIO on Raspberry Pi, Jetson, and other SBCs — collection, calibration, anomaly hooks |

### Team — broadly useful local-AI plumbing

| Skill | What it does |
|-------|--------------|
| **mcp-server-scaffold** | Custom MCP server creation with the FastMCP pattern and testing |
| **ollama-model-workflow** | Local LLM management with Ollama — model pulls, Modelfile creation, benchmarking |
| **rag-pipeline-dotnet** | RAG pipelines with Microsoft Semantic Kernel for .NET, with air-gapped/federal support |
| **rag-pipeline-python** | RAG pipelines with Ollama or cloud embeddings — vector stores, document processing |

## Agents

| Agent | Mode | Drives |
|-------|------|--------|
| **model-optimization-agent** | Autonomous | `model-optimization` |
| **fleet-deployment-agent** | Semi-autonomous — approval before each rollout, canary + health gates, auto-rollback | `jetson-deploy`, `fleet-management` |
| **sensor-anomaly-agent** | Autonomous | `sensor-integration`, `anomaly-detection` |

Each agent ships in both Claude Code and OpenCode format.

---

## Install

> Install [ai-toolkit](../ai-toolkit) first — it provides the global standards, hooks, and
> harness config this toolkit layers on top of.

```bash
# Claude Code → ~/.claude/{agents,skills}/
bash scripts/install-claude.sh

# OpenCode → ~/.config/opencode/{agents,skills}/
bash scripts/install-opencode.sh

# Pi (Ollama) → ~/.pi/agent/skills/   (see pi/SKILLS-local.md for the local-inference triage)
bash scripts/install-pi.sh
```

The install scripts copy skills and agents only; they never overwrite ai-toolkit's global config.

---

## Repository structure

```
edge-ai-robotics-automation-toolkit/
├── skills/
│   ├── professional/   # 7 hardware-specific domain skills
│   └── team/           # 4 local-AI plumbing skills
├── claude/
│   ├── agents/professional/   # 3 agents (Claude Code format)
│   ├── commands/              # (none yet — placeholder)
│   └── global/                # empty — globals ship with ai-toolkit
├── opencode/
│   ├── agents/professional/   # 3 agents (OpenCode format)
│   ├── commands/              # (none yet — placeholder)
│   └── global/                # empty — globals ship with ai-toolkit
├── pi/
│   └── SKILLS-local.md        # Green/Yellow/Red triage for Pi + Ollama
├── project-templates/         # copy into your own project roots
├── scripts/                   # install-claude.sh · install-opencode.sh · install-pi.sh
├── intent.md · constraints.md · evals.md   # how this repo is governed
└── CLAUDE.md · AGENTS.md      # project conventions (Claude Code / OpenCode)
```

---

## Local inference

Every skill is triaged in [`pi/SKILLS-local.md`](pi/SKILLS-local.md) for how well it runs on a
local Ollama model: 🟢 ship as-is, 🟡 usable but shallower, 🔴 drive interactively. Skills that
actuate real hardware (deploys, motors, GPIO) are flagged ⚙️ — never run them in an unattended
local loop.

---

## License

[MIT](LICENSE) — see `LICENSE`.
