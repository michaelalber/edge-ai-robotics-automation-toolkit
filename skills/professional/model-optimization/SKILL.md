---
name: model-optimization
audience: professional
description: Optimize ML models for edge deployment through quantization, pruning, format conversion (TensorRT/TFLite/ONNX), and accuracy/latency benchmarking. Use when preparing models for resource-constrained devices.
---

# Model Optimization for Edge Deployment

> "Quantization is not about making models worse. It is about finding the representation that
> preserves what matters while discarding what does not."
> -- adapted from Benoit Jacob, Google Quantization Team

## Core Philosophy

This skill covers the complete model optimization pipeline: profiling baseline performance, applying
quantization and pruning, converting between inference formats, and benchmarking the results. Every
optimization decision is driven by measurement, not intuition — optimize for speed subject to an
accuracy floor, never the other way around.

**Non-Negotiable Constraints:**
1. BASELINE FIRST — measure the original (latency, accuracy, size, memory) before touching it; without a baseline you cannot quantify improvement or regression.
2. ACCURACY IS THE CONSTRAINT, LATENCY THE OBJECTIVE — optimize speed subject to an accuracy floor, never the reverse.
3. ONE CHANGE AT A TIME — apply optimizations sequentially, benchmark after each; compound changes hide regressions.
4. FORMAT FOLLOWS HARDWARE — TensorRT for Jetson, TFLite for Raspberry Pi, ONNX Runtime for general CPU; never deploy the wrong format.
5. PRESERVE THE ORIGINAL — never modify or delete the source model; all outputs are new files.

Full principle table, KB lookups, pre-flight checklist, decision trees, discipline rules,
anti-patterns, and error recovery live in `references/conventions.md`.

## Workflow

```
            PROFILE → OPTIMIZE → BENCHMARK → VALIDATE → PACKAGE
            baseline  quantize/  speedup +   accuracy   deploy-ready
            metrics   convert    compression within tol  artifact

PROFILE     Run the pre-flight checklist (conventions.md). Measure baseline latency (100+ iters +
            warmup), accuracy on the test set, size, and memory. Record all in the state block.

OPTIMIZE    Pick the path from the quantization/pruning decision trees (conventions.md) by target
            device. Apply ONE optimization at a time. (Strategy: quantization-workflows.md;
            conversions: conversion-pipelines.md.) Validate preprocessing compatibility after each conversion.

BENCHMARK   Measure on target hardware when available (set power mode, lock clocks, 5+ min sustained
            for thermal throttling). Report P50/P95/P99, not just mean. Label host-only runs as estimates.

VALIDATE    Compare accuracy against the floor. If outside tolerance → STOP, report exact numbers,
            present alternatives, let the user decide. Never proceed silently past a violation.

PACKAGE     Emit the deployment artifact with benchmark report, preprocessing config, and provenance.
```

**Exit criteria:** baseline measured and recorded; optimizations applied one at a time and
benchmarked; accuracy within the stated tolerance (or the tradeoff explicitly accepted by the user);
deployment artifact packaged with metadata. The original model is untouched.

## State Block

```
<model-opt-state>
phase: PROFILE | OPTIMIZE | BENCHMARK | VALIDATE | PACKAGE
model_name: [name]
source_format: pytorch | tensorflow | onnx | tflite | tensorrt
target_device: jetson-orin-nano | raspberry-pi-5 | raspberry-pi-4 | cpu-generic
baseline_latency_ms: [number or "unmeasured"]
baseline_accuracy: [number or "unmeasured"]
accuracy_tolerance: [percentage, e.g., "2%"]
optimizations_applied: [comma-separated list or "none"]
current_best_latency_ms: [number or "unmeasured"]
current_best_accuracy: [number or "unmeasured"]
original_model_path: [absolute path to original model file]
last_action: [what was just done]
next_action: [what should happen next]
blockers: [any issues]
</model-opt-state>
```

## Output Template

- **Optimization summary report, tradeoff table** — `references/output-templates.md`.
- **INT8/FP16 strategy, PTQ vs QAT, calibration requirements, per-layer sensitivity** — `references/quantization-workflows.md`.
- **PyTorch→ONNX→TensorRT, TF→TFLite, ONNX Runtime optimization, dynamic batching** — `references/conversion-pipelines.md`.
- **Principle table, KB lookups, pre-flight, decision trees, discipline rules, anti-patterns, error recovery** — `references/conventions.md`.

## Integration with Other Skills

| Skill | Relationship |
|-------|-------------|
| `ollama-model-workflow` | When the model runs locally via Ollama, use that skill to select the base model and quantization, then apply this skill's quantize/prune/convert and benchmark steps to fit the target hardware's VRAM and latency budget. |
| `rag-pipeline-python` / `rag-pipeline-dotnet` | When the optimized model is the generation or embedding backbone of a RAG pipeline, hand the converted artifact off to the RAG scaffolder. |
