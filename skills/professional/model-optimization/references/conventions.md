# Model Optimization Conventions

Depth behind the Core Philosophy constraints: principles, knowledge-base grounding, the pre-flight
checklist, decision trees, discipline rules, anti-patterns, and recovery. Quantization strategy
detail is in `quantization-workflows.md`; conversion pipelines in `conversion-pipelines.md`.

## Domain Principles

| Principle | Description | Priority |
|-----------|-------------|----------|
| **Measure Before Optimizing** | Profile the unmodified model for latency, accuracy, size, memory before any optimization | Critical |
| **Accuracy Floor Enforcement** | Define an acceptable degradation threshold; reject any optimization that violates it | Critical |
| **Format-Device Alignment** | TensorRT for NVIDIA GPU, TFLite for ARM CPU, ONNX for portable | Critical |
| **Calibration Data Quality** | INT8 is only as good as its calibration set; use representative, domain-specific data | High |
| **Sequential Optimization** | One optimization at a time, benchmark, then keep or revert | High |
| **Reproducible Benchmarks** | Lock clocks, set power modes, run warmup, report percentile latencies | High |
| **Original Preservation** | Never modify/move/delete the original; all outputs use new descriptive filenames | High |
| **Per-Layer Sensitivity** | Not all layers respond equally to quantization; identify and protect sensitive ones | Medium |
| **Mixed Precision** | When uniform INT8 fails accuracy, use FP16 for sensitive layers and INT8 for the rest | Medium |
| **Deployment Metadata** | Package optimized models with benchmark results, preprocessing config, provenance | Medium |

## Knowledge Base Lookups

Search `edge_ai` first for optimization patterns, `python` for framework-specific code. Cite the
source path. Report accuracy degradation before proceeding.

| Query | When to Call |
|-------|--------------|
| `search_knowledge("quantization INT8 PTQ calibration dataset")` | OPTIMIZE — PTQ strategy |
| `search_knowledge("TensorRT FP16 INT8 engine conversion")` | OPTIMIZE — TensorRT for Jetson |
| `search_knowledge("TFLite quantization ARM Raspberry Pi")` | OPTIMIZE — TFLite for ARM |
| `search_knowledge("ONNX model export PyTorch TensorFlow")` | PROFILE/OPTIMIZE — ONNX interchange |
| `search_knowledge("model pruning structured unstructured channels")` | OPTIMIZE — pruning |
| `search_knowledge("inference benchmark latency percentile P95")` | BENCHMARK — statistical rigor |
| `search_code_examples("TensorRT calibration INT8 Python")` | Before INT8 calibration |
| `search_code_examples("ONNX export PyTorch torch.onnx")` | Before ONNX export — opset/options |

## Pre-Flight Checklist

Before starting any optimization workflow, verify:
- [ ] Source model file exists and is loadable
- [ ] Model framework identified (PyTorch / TensorFlow / ONNX)
- [ ] Target device identified (Jetson / RPi / CPU)
- [ ] Test/validation dataset available
- [ ] Accuracy metric defined (mAP / top-1 / F1 / custom)
- [ ] Accuracy tolerance defined (default: 2% relative drop)
- [ ] Latency target defined (optional but recommended)
- [ ] Calibration dataset available (for INT8 quantization)
- [ ] Disk space sufficient for multiple model variants

## Quantization Strategy Decision Tree

```
What is the target device?
├── NVIDIA Jetson (GPU)
│   └── Start with TensorRT FP16 → meets latency target?
│       ├── YES → ship FP16
│       └── NO  → calibration dataset (500-1000 images) → TensorRT INT8 → accuracy in tolerance?
│                ├── YES → ship INT8
│                └── NO  → mixed precision or smaller model
├── Raspberry Pi / ARM CPU
│   └── Start with TFLite float16 → meets latency target?
│       ├── YES → ship float16
│       └── NO  → calibration dataset (200-500 images) → TFLite full INT8 PTQ → accuracy in tolerance?
│                ├── YES → ship INT8
│                └── NO  → QAT or smaller model
└── General CPU / Cloud
    └── ONNX Runtime graph optimizations → dynamic range quantization → if needed, full INT8 with calibration
```

## Pruning Strategy Decision Tree

```
Is the model overparameterized for the task?
├── YES (accuracy well above requirements)
│   └── Structured pruning (remove channels/filters) → start 20% → fine-tune 5-10 epochs → in tolerance?
│       ├── YES → increase ratio (30%, 40%, …)
│       └── NO  → reduce ratio or switch to unstructured
└── NO (accuracy near the floor)
    └── Do NOT prune; focus on quantization and format conversion instead
```

## Discipline Rules

- **Never skip baseline profiling.** Load and test the original; measure latency with 100+
  iterations + warmup; measure accuracy on the test set; record all baseline numbers in the state
  block. *Wrong:* "MobileNetV2 is usually ~30ms, so let's quantize." *Right:* "Measured baseline:
  mean=34.2ms, P95=37.1ms, accuracy=71.8% top-1."
- **Validate preprocessing compatibility after every conversion.** Assert input shape and dtype
  match the converted model's `get_input_details()`. INT8 models take uint8 (0-255), float models
  take float32 (0.0-1.0) unless model-specific.
- **Report accuracy degradation immediately.** If accuracy drops beyond tolerance: STOP, report the
  exact numbers, present alternatives (less aggressive quantization, mixed precision, QAT), let the
  user decide. Never proceed silently past an accuracy violation.
- **Benchmark on target hardware when available.** Host numbers are estimates, not deployment
  metrics. On target: set power mode (Jetson `nvpmodel`, RPi governor), lock clocks, run a 5+ minute
  sustained test for thermal throttling. If unavailable: label results "Host Estimate (not target
  hardware)"; accuracy is still valid, latency may differ 2-10x.

## Anti-Patterns

| Anti-Pattern | Why It Fails | Correct Approach |
|--------------|-------------|------------------|
| Optimizing without baseline | Cannot quantify improvement; may ship a regression | Profile the original first |
| Stacking optimizations at once | Cannot attribute accuracy loss to a specific change | One optimization, benchmark, decide |
| Random data for INT8 calibration | Quantization ranges won't match real distribution | 500-1000 representative domain samples |
| Reporting mean latency only | Hides tail spikes from thermal throttling | Report P50/P95/P99 + sustained load tests |
| Assuming FP16 is lossless | Large dynamic ranges lose accuracy at FP16 | Always validate accuracy after FP16 |
| Deleting the original | Cannot re-optimize or debug later | Keep original; descriptive names for variants |
| Building TensorRT engine on x86 for ARM | Engines are architecture-specific | Build on the target device/architecture |
| Uniform INT8 across the model | Attention/final classifier layers are INT8-sensitive | Per-layer sensitivity; mixed precision |

## Error Recovery

**Calibration dataset too small** (INT8 produces inconsistent/degraded accuracy):
1. Increase to 500-1000 samples covering the full input distribution
2. Avoid training augmentations in calibration data
3. Try a different calibration algorithm (Entropy vs MinMax)
4. Compare INT8 vs FP32 outputs on calibration samples

**ONNX export produces invalid model:**
1. `onnx.checker.check_model()` for structural validation
2. Compare ONNX vs original framework output on the same input
3. Try a different opset (lower = more compatible, higher = more ops)
4. Simplify with `onnxsim`; replace unsupported dynamic ops with static alternatives

**Latency target not met after all optimizations:**
1. Review the profiling breakdown — which stage is the bottleneck?
2. Reduce input resolution (e.g., 640×640 → 320×320)
3. Switch to a smaller architecture (e.g., YOLOv8n instead of YOLOv8s)
4. Apply structured pruning to reduce channel counts
5. Consider distillation to a smaller student model
6. Accept a lower FPS target if accuracy is non-negotiable
