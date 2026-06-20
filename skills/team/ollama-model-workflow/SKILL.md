---
name: ollama-model-workflow
audience: team
description: >
  Local LLM management with Ollama, Modelfile creation, and benchmarking. Use when
  pulling models, creating custom Modelfiles, or evaluating model performance locally.
  Do NOT use when the target runtime is a cloud provider API (OpenAI, Anthropic,
  Azure OpenAI); do NOT use when VRAM is unavailable on the target machine.
---

# Ollama Model Workflow

> "The best model is the one that runs reliably on the hardware you actually have."
> -- Practical AI Engineering Proverb

## Core Philosophy

This skill manages the full lifecycle of local LLMs through Ollama: selection, pulling, configuration, testing, benchmarking, and deployment. Every decision is grounded in **hardware reality** and **measurable performance**.

**Non-Negotiable Constraints:**
1. Every model selection MUST begin with a VRAM/hardware assessment
2. Every Modelfile MUST be version-controlled with documented parameter rationale
3. Every model MUST be benchmarked before deployment to any workflow
4. Every recommendation MUST include quantization-aware resource estimates
5. Never pull a model without first confirming sufficient disk space and VRAM

## Domain Principles

| # | Principle | Description | Priority |
|---|-----------|-------------|----------|
| 1 | **VRAM-Aware Selection** | Always check available VRAM before recommending or pulling a model. Match model size to hardware capacity with a safety margin. | Critical |
| 2 | **Quantization Tradeoffs** | Understand and communicate the quality/speed/size tradeoff for each quantization level. Lower quantization is not always better. | Critical |
| 3 | **System Prompt Engineering** | Craft SYSTEM prompts that constrain the model to its intended role. Keep prompts concise and unambiguous. | High |
| 4 | **Temperature Tuning** | Match temperature to task type: low for deterministic tasks (code, extraction), higher for creative tasks. Always document the rationale. | High |
| 5 | **Context Window Management** | Set `num_ctx` deliberately. Larger contexts consume more VRAM and slow inference. Size to actual need, not maximum. | High |
| 6 | **Model Comparison Methodology** | Compare models using identical prompts, parameters, and hardware conditions. Never compare across different quantization levels without noting it. | High |
| 7 | **Modelfile Reproducibility** | Every Modelfile must be self-contained and reproducible. Pin base model tags, document all parameter choices. | Critical |
| 8 | **Inference Performance** | Measure tokens/sec, time to first token, and total generation time. Track these across model updates. | High |
| 9 | **Model Versioning** | Tag and track model versions. When Ollama updates a model tag, re-benchmark before adopting. | Medium |
| 10 | **Hardware Matching** | Different hardware (Jetson, consumer GPU, Mac M-series, CPU-only) requires different model choices. Never assume one config fits all. | Critical |

## Workflow

Six-step lifecycle: **SELECT → PULL → CONFIGURE → TEST → BENCHMARK → DEPLOY**. Return to SELECT if benchmarking reveals the model doesn't meet requirements.

### Step 1: Model Selection

Choose model family by task type:

| Task | Recommended Models |
|------|--------------------|
| Coding | codellama, deepseek-coder, qwen2.5-coder |
| Chat / General | llama3.1, phi3, gemma2 |
| RAG / Tool Use | mistral, nomic-embed, mxbai-embed |

### Step 2: Quantization Selection

Choose quantization based on available VRAM:

| Available VRAM | Recommended Quantization |
|----------------|--------------------------|
| < 4 GB | Q4_K_M (small models only) |
| 4–8 GB | Q4_K_M (7B models) |
| 8–16 GB | Q5_K_M (7–13B models) |
| 16–24 GB | Q8_0 (7–13B models) |
| 24+ GB | FP16 (7–13B models) |

### Steps 3–6: Configure, Test, Benchmark, Deploy

**Configure Modelfile:** Choose base model with explicit tag. Set PARAMETER values appropriate to task. Write SYSTEM prompt constraining behavior. Set TEMPLATE if using a non-default chat format.

**Test:** Run representative prompts. Verify output quality and instruction following.

**Benchmark:** Measure tokens/sec with standardized prompts. Record time to first token. Test at target context window size. Compare against baseline or alternative models.

**Deploy:** Commit Modelfile to version control. Document model selection rationale. Record benchmark results for future reference.

## State Block

```
<ollama-state>
step: [SELECT | PULL | CONFIGURE | TEST | BENCHMARK | DEPLOY]
model_name: [name]
quantization: [Q4_K_M | Q5_K_M | Q6_K | Q8_0 | FP16]
vram_available_gb: [number]
tokens_per_second: [number or untested]
last_action: [what was done]
next_action: [what's next]
blockers: [issues]
</ollama-state>
```

## Output Templates

| Template | Required Fields |
|----------|----------------|
| Model Selection Report | Task, Hardware, Resources table (VRAM/Disk/RAM available vs. required), Candidates table, Recommendation + rationale |
| Modelfile Creation | Base model, Purpose, Parameters table with rationale column, Modelfile block, Verification checklist |
| Benchmark Results | Date, Hardware, Quantization, Performance table (tokens/sec, TTFT, VRAM), Quality table, Comparison table |

Full templates: `references/quantization-benchmarks.md`

## AI Discipline Rules

**Always Check VRAM Before Pulling:** Run `nvidia-smi --query-gpu=name,memory.total,memory.used,memory.free --format=csv,noheader,nounits` (or `system_profiler SPDisplaysDataType` on Mac M-series). Verify free VRAM exceeds model requirement plus a 1–2 GB safety margin. If VRAM is unknown, ask before proceeding — never assume.

**Never Skip Benchmarking:** Every model must be benchmarked before deployment: tokens/sec with representative prompts, time to first token, quality on task-specific test cases, and VRAM usage confirmed under budget. Production surprises come from skipped benchmarks.

**Always Document Modelfile Parameters:** Every PARAMETER must have an inline comment explaining the choice. Example: `PARAMETER temperature 0.3 # Low for deterministic code generation — 0.7+ caused inconsistent formatting in testing.` An undocumented parameter is a parameter that will be changed without understanding the consequences.

**Never Recommend Without Hardware Context:** Require before any recommendation: target hardware (GPU model, VRAM, RAM), task description, latency requirements (interactive vs. batch), quality requirements. If any are missing, ask — a recommendation without hardware context is a guess.

## Anti-Patterns

| Anti-Pattern | Why It Fails | Correct Approach |
|--------------|-------------|------------------|
| Pulling largest model without checking VRAM | OOM crashes, disk swapping destroys performance | Always assess VRAM first; pick the largest model that fits with margin |
| Using default parameters for all tasks | temperature 0.8 is wrong for code; num_ctx 2048 is wrong for RAG | Tune parameters to the specific task and document rationale |
| Comparing models at different quantization levels | Q4_K_M vs Q8_0 comparison conflates quality and quantization effects | Compare at same quantization; compare quantization tradeoffs separately |
| Skipping system prompt in Modelfile | Model behaves unpredictably, inconsistent outputs | Always include a SYSTEM prompt constraining the model role |
| Not pinning model tags | `ollama pull llama3.1` may get different versions over time | Use explicit tags like `llama3.1:8b-instruct-q5_K_M` |
| Benchmarking with trivial prompts | "Hello world" doesn't represent production workload | Use representative prompts matching actual deployment scenarios |
| Ignoring time to first token | High tokens/sec means nothing if TTFT is 5 seconds for interactive use | Measure and report TTFT alongside generation speed |

## Error Recovery

**OOM (Out of Memory):** Check actual VRAM usage with `nvidia-smi` or `ollama ps`. Reduce `num_ctx` (halving it roughly halves KV cache VRAM). Switch to smaller quantization (Q8_0 → Q5_K_M → Q4_K_M). Switch to smaller parameter count model. Check for other processes consuming VRAM on shared GPU.

**Slow Inference (< 5 tok/s):** Verify model is running on GPU not CPU (`ollama ps` shows GPU%). Check if model is partially offloaded (too large for VRAM). Reduce `num_ctx`. Switch to more aggressive quantization. Check for thermal throttling. On CPU-only hardware, 1–5 tok/s for 7B models may be normal.

**Model Corruption / Bad Output:** Remove and re-pull: `ollama rm [model] && ollama pull [model]`. Check Modelfile TEMPLATE syntax matches the model's expected format. Test with base model (no Modelfile) to isolate the issue. Check server logs: `journalctl -u ollama` or `~/.ollama/logs/`.

**Server Issues:** Check `systemctl status ollama`. Restart: `systemctl restart ollama`. Check port conflicts: `lsof -i :11434`. Review logs: `journalctl -u ollama --since "10 minutes ago"`. Verify disk space at `~/.ollama/models/`. Confirm `OLLAMA_HOST` environment variable is set correctly.

**Pull Failures:** Check disk space: `df -h ~/.ollama/`. Retry (network interruptions are common for large models). Update Ollama version. For checksum errors: `ollama rm [model]` then re-pull. Behind proxy: set `HTTPS_PROXY` environment variable.

## Integration with Other Skills

- **`rag-pipeline-python`** — Use this skill to select and configure embedding models (e.g., `nomic-embed-text`, `mxbai-embed-large`) and generation models for RAG workflows. Benchmark embedding throughput and generation quality before integrating.
- **`mcp-server-scaffold`** — When building MCP servers that expose LLM capabilities, use this skill to select, configure, and benchmark the backing Ollama model. Commit the Modelfile alongside the MCP server code.
- **`model-optimization`** — When a pulled model needs to run on constrained hardware, use this skill to quantize, prune, or convert it (TensorRT/TFLite/ONNX) and benchmark the accuracy/latency tradeoff before committing the Modelfile.

## Reference Files

- [Modelfile Reference](references/modelfile-reference.md) — Complete Modelfile syntax, parameters, templates, and examples
- [Quantization and Benchmarks](references/quantization-benchmarks.md) — Quantization levels, VRAM tables, benchmarking methodology, hardware guide, and report templates
