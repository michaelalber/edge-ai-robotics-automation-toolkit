# Model Optimization Output Templates

## Optimization Summary Report

```markdown
## Model Optimization Report: [Model Name]

**Source**: [framework] [format] ([size] MB)
**Target Device**: [device]
**Optimization Pipeline**: [list of steps applied]
**Date**: [date]

### Baseline vs Optimized

| Metric | Baseline | Optimized | Change |
|--------|----------|-----------|--------|
| File Size | [MB] | [MB] | [ratio]x compression |
| Latency (mean) | [ms] | [ms] | [speedup]x faster |
| Latency (P95) | [ms] | [ms] | [speedup]x faster |
| Memory (peak) | [MB] | [MB] | [reduction]x smaller |
| Accuracy ([metric]) | [value] | [value] | [delta] ([status]) |
| Throughput | [fps] | [fps] | [improvement]x |

### Optimization Steps Applied

| Step | Input | Output | Size | Latency | Accuracy |
|------|-------|--------|------|---------|----------|
| 1. [step] | [file] | [file] | [MB] | [ms] | [value] |
| 2. [step] | [file] | [file] | [MB] | [ms] | [value] |

### Verdict

[PASS/FAIL]: Accuracy delta of [N]% is [within/outside] the [N]% tolerance.
Speedup: [N]x. Compression: [N]x.

### Deployment Artifact

- Model file: [path]
- Metadata: [path]
- Preprocessing config: [input_shape, dtype, normalization]
```

## Tradeoff Table

```markdown
## Optimization Tradeoff Analysis: [Model Name]

| Variant | Format | Precision | Size (MB) | Latency (ms) | Accuracy | Speedup | Acc. Delta |
|---------|--------|-----------|-----------|-------------|----------|---------|-----------|
| Baseline | [fmt] | FP32 | [size] | [lat] | [acc] | 1.0x | 0.0% |
| ONNX Simplified | ONNX | FP32 | [size] | [lat] | [acc] | [x] | [%] |
| TensorRT FP16 | TRT | FP16 | [size] | [lat] | [acc] | [x] | [%] |
| TensorRT INT8 | TRT | INT8 | [size] | [lat] | [acc] | [x] | [%] |
| TFLite Float16 | TFLite | FP16 | [size] | [lat] | [acc] | [x] | [%] |
| TFLite INT8 | TFLite | INT8 | [size] | [lat] | [acc] | [x] | [%] |

**Recommendation**: [variant] provides [speedup]x speedup with only [delta]% accuracy loss.
```
