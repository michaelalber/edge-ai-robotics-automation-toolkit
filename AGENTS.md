# AGENTS.md — edge-ai-robotics-automation-toolkit

Canonical project conventions and inventory for this repository. This is the OpenCode-side
twin of `CLAUDE.md`; both describe the same project. For OpenCode the agent reads this file;
for Claude Code it reads `CLAUDE.md`. Keep the two in sync.

---

## Purpose

A domain supplement to [ai-toolkit](../ai-toolkit) providing **11 skills and 3 agents** for
**Local AI, Edge AI, ML, Robotics, and Industrial Automation** — model optimization for
constrained devices, sensor integration and anomaly detection, edge computer vision, robot
behavior composition, fleet deployment, and local LLM/RAG plumbing.

ai-toolkit owns the shared engineering standards and the skill/agent templates; this repo
reuses them and adds the domain content. The two install side by side.

---

## Inventory

| Primitive | Count |
|-----------|-------|
| Skills (professional) | 7 |
| Skills (team) | 4 |
| Agents (Claude Code) | 3 |
| Agents (OpenCode) | 3 |
| Slash commands | 0 (see Open Loops) |

### Skill Suites

**Professional — domain-expert, hardware-specific**

| Skill | What it does |
|-------|--------------|
| `anomaly-detection` | Statistical anomaly detection for sensor streams — outlier detection, drift monitoring, classification, alert/recalibration decision trees |
| `edge-cv-pipeline` | OpenCV + TFLite computer-vision pipelines for Jetson and Raspberry Pi — camera capture, optimized inference, result publishing |
| `fleet-management` | Rolling deployment strategies, multi-device coordination, and rollback triggers for edge device fleets |
| `jetson-deploy` | Deploy and optimize on Jetson Orin Nano with TensorRT — environment setup, model conversion, power modes, containerization |
| `model-optimization` | Quantization, pruning, format conversion (TensorRT/TFLite/ONNX), and accuracy/latency benchmarking for constrained devices |
| `picar-x-behavior` | Composable robot behaviors for SunFounder Picar-X — autonomous driving, sensor-reactive patterns, behavior trees |
| `sensor-integration` | Sensor data pipelines over I2C/SPI/UART/GPIO on Raspberry Pi, Jetson, and other SBCs — collection, calibration, anomaly hooks |

**Team — broadly useful local-AI plumbing**

| Skill | What it does |
|-------|--------------|
| `mcp-server-scaffold` | Custom MCP server creation with the FastMCP pattern and testing |
| `ollama-model-workflow` | Local LLM management with Ollama — model pulls, Modelfile creation, benchmarking |
| `rag-pipeline-dotnet` | RAG pipelines with Microsoft Semantic Kernel for .NET, with air-gapped/federal support |
| `rag-pipeline-python` | RAG pipelines with Ollama or cloud embeddings — vector stores, document processing |

### Agents

| Agent | Mode | Skills it drives |
|-------|------|------------------|
| `model-optimization-agent` | Autonomous | `model-optimization` |
| `fleet-deployment-agent` | Semi-autonomous (approval before rollout) | `jetson-deploy`, `fleet-management` |
| `sensor-anomaly-agent` | Autonomous | `sensor-integration`, `anomaly-detection` |

All agents exist in both `claude/agents/professional/` and `opencode/agents/professional/`.

---

## Conventions

These are **inherited from ai-toolkit** — do not redefine them here:

- **5-section lean skill layout** — Core Philosophy, Workflow, State, Output Template, Integration
  in `SKILL.md` (≤ 200 lines); depth pushed to `references/` (≥ 2 files), loaded just-in-time.
- **Agent template** — consistent section structure; Claude Code and OpenCode versions kept in parity.
- **State-block XML tags** — unique across every skill and agent (this repo **and** ai-toolkit).
- **Security, commit format (Conventional Commits), code-quality gates** — per ai-toolkit's global standards.

This repo adds one domain rule: **device-facing skills must name the target hardware, protocol,
and runtime explicitly.** Generic edge advice with no named device is an anti-pattern.

---

## Persistent Decisions

1. **This is a supplement, not a fork.** Global standards and templates live in ai-toolkit and
   are not duplicated here. (`claude/global/` and `opencode/global/` are empty placeholders.)
2. **Skills are single-homed.** Each skill lives in exactly one toolkit. The edge-AI/robotics/ML
   skills were moved here out of ai-toolkit; ai-toolkit no longer ships them.
3. **All three agents are tiered `professional`** — they are domain-expert executors paired with
   professional-tier skills.
4. **Pi/Ollama global config (Modelfiles, models.json) stays in ai-toolkit.** This repo ships only
   `pi/SKILLS-local.md` (the local-inference triage) and installs its skills into Pi's skill dir.

## Open Loops

- **No slash commands yet.** None of the moved primitives were user-invoked commands. Candidates if
  demand appears: `/optimize-model` (inject model metadata), `/fleet-status` (inject device health).
- **grounded-code-mcp collections** — these skills lean on the `edge_ai`, `robotics`, and
  `automation` collections; verify they are populated before relying on grounded output.
- **Hardware coverage** — currently Jetson Orin Nano, Raspberry Pi, and SunFounder Picar-X. New
  platforms (other SBCs, PLCs, industrial gateways) are an escalation per `constraints.md`.
