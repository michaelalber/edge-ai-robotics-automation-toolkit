# Quantization and Benchmarking Reference

Comprehensive guide to quantization levels, VRAM requirements, benchmarking methodology, and hardware matching for Ollama models.

## Quantization Levels Explained

Quantization reduces model precision from the original floating-point representation to lower bit-widths, trading some quality for significant reductions in model size and VRAM usage.

### Quantization Types

| Level | Bits | Description | Quality | Size Reduction | Use Case |
|-------|------|-------------|---------|----------------|----------|
| **FP16** | 16 | Half-precision float | Baseline (best) | 0% (reference) | When quality is paramount and VRAM is abundant |
| **Q8_0** | 8 | 8-bit integer | Near-lossless | ~50% | High quality with moderate VRAM savings |
| **Q6_K** | 6 | 6-bit k-quant | Very good | ~60% | Good balance for well-resourced systems |
| **Q5_K_M** | 5 | 5-bit k-quant (medium) | Good | ~65% | Best general-purpose tradeoff |
| **Q5_K_S** | 5 | 5-bit k-quant (small) | Good | ~67% | Slightly smaller than Q5_K_M |
| **Q4_K_M** | 4 | 4-bit k-quant (medium) | Acceptable | ~75% | Budget VRAM, still usable for most tasks |
| **Q4_K_S** | 4 | 4-bit k-quant (small) | Fair | ~77% | Tight VRAM, some quality loss |
| **Q3_K_M** | 3 | 3-bit k-quant (medium) | Degraded | ~82% | Emergency use only, noticeable quality loss |
| **Q2_K** | 2 | 2-bit k-quant | Poor | ~88% | Not recommended for production |

### K-Quant Naming Convention

The "K" in quantization names refers to the k-quant method developed by llama.cpp:
- **K_S** (Small): Slightly more aggressive quantization, smaller size
- **K_M** (Medium): Balanced quantization, best quality/size tradeoff
- **K_L** (Large): Less aggressive, closer to the next higher bit level

### Quality Impact by Task

| Task | Q4_K_M | Q5_K_M | Q6_K | Q8_0 | FP16 |
|------|--------|--------|------|------|------|
| General chat | Good | Very good | Excellent | Baseline | Baseline |
| Code generation | Acceptable | Good | Very good | Excellent | Baseline |
| Reasoning/math | Degraded | Acceptable | Good | Very good | Baseline |
| Creative writing | Good | Very good | Excellent | Baseline | Baseline |
| JSON extraction | Acceptable | Good | Very good | Excellent | Baseline |
| RAG QA | Good | Very good | Excellent | Baseline | Baseline |

## VRAM Requirements Table

Estimated VRAM usage includes model weights plus KV cache overhead at the default context size. Actual usage varies by implementation and context length.

### 7B Parameter Models

| Model (7B) | Q4_K_M | Q5_K_M | Q6_K | Q8_0 | FP16 |
|-------------|--------|--------|------|------|------|
| **Model size (GB)** | 4.1 | 4.8 | 5.5 | 7.2 | 14.0 |
| **VRAM w/ 2K ctx** | 4.8 | 5.5 | 6.3 | 8.0 | 14.8 |
| **VRAM w/ 4K ctx** | 5.3 | 6.0 | 6.8 | 8.5 | 15.3 |
| **VRAM w/ 8K ctx** | 6.3 | 7.0 | 7.8 | 9.5 | 16.3 |
| **VRAM w/ 16K ctx** | 8.3 | 9.0 | 9.8 | 11.5 | 18.3 |
| **Min GPU** | 6 GB | 8 GB | 8 GB | 10 GB | 16 GB |

### 13B Parameter Models

| Model (13B) | Q4_K_M | Q5_K_M | Q6_K | Q8_0 | FP16 |
|-------------|--------|--------|------|------|------|
| **Model size (GB)** | 7.4 | 8.6 | 9.9 | 13.0 | 26.0 |
| **VRAM w/ 2K ctx** | 8.4 | 9.6 | 10.9 | 14.0 | 27.0 |
| **VRAM w/ 4K ctx** | 9.2 | 10.4 | 11.7 | 14.8 | 27.8 |
| **VRAM w/ 8K ctx** | 10.8 | 12.0 | 13.3 | 16.4 | 29.4 |
| **Min GPU** | 10 GB | 12 GB | 12 GB | 16 GB | 32 GB |

### 34B Parameter Models

| Model (34B) | Q4_K_M | Q5_K_M | Q6_K | Q8_0 | FP16 |
|-------------|--------|--------|------|------|------|
| **Model size (GB)** | 19.5 | 22.5 | 26.0 | 34.0 | 68.0 |
| **VRAM w/ 4K ctx** | 21.5 | 24.5 | 28.0 | 36.0 | 70.0 |
| **VRAM w/ 8K ctx** | 23.5 | 26.5 | 30.0 | 38.0 | 72.0 |
| **Min GPU** | 24 GB | 24 GB | 32 GB | 40 GB | 80 GB |

### 70B Parameter Models

| Model (70B) | Q4_K_M | Q5_K_M | Q6_K | Q8_0 | FP16 |
|-------------|--------|--------|------|------|------|
| **Model size (GB)** | 40.0 | 46.0 | 53.0 | 70.0 | 140.0 |
| **VRAM w/ 4K ctx** | 43.0 | 49.0 | 56.0 | 73.0 | 143.0 |
| **Min GPU** | 48 GB | 48 GB | 2x32 GB | 80 GB | 2x80 GB |

### Embedding Models

| Model | Dimensions | Size (GB) | VRAM (GB) |
|-------|-----------|-----------|-----------|
| nomic-embed-text | 768 | 0.27 | 0.5 |
| mxbai-embed-large | 1024 | 0.67 | 1.0 |
| all-minilm | 384 | 0.045 | 0.3 |
| snowflake-arctic-embed | 1024 | 0.67 | 1.0 |

## Model Size Estimation Formulas

### Quick Estimation

For a rough estimate of model file size based on parameter count and quantization:

```
Size (GB) = (Parameters in billions) * (Bits per weight) / 8

Examples:
  7B Q4_K_M:  7 * 4.5 / 8 = ~3.9 GB  (actual ~4.1 GB due to overhead)
  7B Q8_0:    7 * 8.0 / 8 = ~7.0 GB  (actual ~7.2 GB)
  7B FP16:    7 * 16  / 8 = ~14  GB  (actual ~14 GB)
  13B Q5_K_M: 13 * 5.2 / 8 = ~8.5 GB (actual ~8.6 GB)
```

Note: K-quant methods use mixed precision (some layers quantized more than others), so the effective bits per weight is not exactly the named bit level.

### VRAM Estimation with Context

```
VRAM (GB) = Model Size (GB) + KV Cache (GB) + Overhead (GB)

KV Cache (GB) = 2 * num_layers * num_kv_heads * head_dim * num_ctx * 2 / (1024^3)
Overhead (GB) = ~0.5 - 1.0 GB (compute buffers, CUDA context)
```

### Python VRAM Estimator

```python
def estimate_vram_gb(
    params_billions: float,
    bits_per_weight: float,
    num_ctx: int = 4096,
    num_layers: int = 32,
    num_kv_heads: int = 8,
    head_dim: int = 128,
    overhead_gb: float = 0.8,
) -> dict:
    """Estimate VRAM usage for a given model configuration.

    Args:
        params_billions: Model parameter count in billions.
        bits_per_weight: Effective bits per weight for quantization level.
        num_ctx: Context window size in tokens.
        num_layers: Number of transformer layers.
        num_kv_heads: Number of key-value attention heads.
        head_dim: Dimension of each attention head.
        overhead_gb: Estimated overhead for compute buffers.

    Returns:
        Dictionary with model size, KV cache size, and total VRAM estimate.
    """
    model_size_gb = params_billions * bits_per_weight / 8

    # KV cache: 2 (K+V) * layers * kv_heads * head_dim * ctx_len * 2 bytes (FP16)
    kv_cache_bytes = 2 * num_layers * num_kv_heads * head_dim * num_ctx * 2
    kv_cache_gb = kv_cache_bytes / (1024 ** 3)

    total_gb = model_size_gb + kv_cache_gb + overhead_gb

    return {
        "model_size_gb": round(model_size_gb, 2),
        "kv_cache_gb": round(kv_cache_gb, 2),
        "overhead_gb": overhead_gb,
        "total_vram_gb": round(total_gb, 2),
    }


# Common quantization effective bits
QUANT_BITS = {
    "Q4_K_M": 4.5,
    "Q4_K_S": 4.3,
    "Q5_K_M": 5.2,
    "Q5_K_S": 5.0,
    "Q6_K": 6.3,
    "Q8_0": 8.0,
    "FP16": 16.0,
}

# Example: Estimate VRAM for Llama 3.1 8B at Q5_K_M with 8K context
estimate = estimate_vram_gb(
    params_billions=8.0,
    bits_per_weight=QUANT_BITS["Q5_K_M"],
    num_ctx=8192,
    num_layers=32,
    num_kv_heads=8,
    head_dim=128,
)
print(f"Estimated VRAM: {estimate['total_vram_gb']} GB")
```

## Benchmarking Methodology

### Key Metrics

| Metric | Description | How to Measure |
|--------|-------------|----------------|
| **Tokens/sec (generation)** | Speed of token generation after first token | Total generated tokens / (total time - TTFT) |
| **Time to first token (TTFT)** | Latency before first token appears | Time from request to first streamed token |
| **Total generation time** | End-to-end response time | Time from request to final token |
| **Prompt eval rate** | Speed of processing input tokens | Prompt tokens / prompt eval time |
| **VRAM usage** | GPU memory consumed during inference | nvidia-smi during inference |
| **Perplexity** | Model quality metric (lower is better) | Requires test corpus; measures prediction accuracy |

### Standardized Benchmark Prompts

Use consistent prompts across all benchmarks for comparability:

```python
BENCHMARK_PROMPTS = {
    "short_generation": {
        "prompt": "Write a Python function that checks if a number is prime.",
        "expected_tokens": 100,
        "category": "code",
    },
    "medium_generation": {
        "prompt": (
            "Explain the differences between TCP and UDP protocols. "
            "Include use cases, advantages, and disadvantages of each."
        ),
        "expected_tokens": 300,
        "category": "explanation",
    },
    "long_generation": {
        "prompt": (
            "Write a comprehensive Python class for a thread-safe LRU cache "
            "with TTL support. Include type hints, docstrings, unit tests, "
            "and usage examples."
        ),
        "expected_tokens": 800,
        "category": "code",
    },
    "reasoning": {
        "prompt": (
            "A farmer has a fox, a chicken, and a bag of grain. He needs to "
            "cross a river in a boat that can only carry him and one item at "
            "a time. If left alone, the fox will eat the chicken, and the "
            "chicken will eat the grain. How does the farmer get everything "
            "across safely? Show your reasoning step by step."
        ),
        "expected_tokens": 400,
        "category": "reasoning",
    },
    "json_extraction": {
        "prompt": (
            'Extract the following information as JSON: {"name": str, "age": int, '
            '"city": str}. Text: "John Smith, aged 34, lives in Portland, Oregon.'
            ' He works as a software engineer."'
        ),
        "expected_tokens": 50,
        "category": "structured",
    },
}
```

### Python Benchmarking Script (ollama-python)

```python
import time
import statistics
import ollama


def benchmark_model(
    model: str,
    prompt: str,
    num_runs: int = 5,
    num_ctx: int = 4096,
    warmup_runs: int = 1,
) -> dict:
    """Benchmark an Ollama model with consistent methodology.

    Args:
        model: The Ollama model name/tag to benchmark.
        prompt: The prompt to use for benchmarking.
        num_runs: Number of benchmark iterations (excluding warmup).
        num_ctx: Context window size to use.
        warmup_runs: Number of warmup runs before benchmarking.

    Returns:
        Dictionary containing benchmark results with statistics.
    """
    messages = [{"role": "user", "content": prompt}]
    options = {"num_ctx": num_ctx}

    # Warmup runs (not counted)
    for _ in range(warmup_runs):
        ollama.chat(model=model, messages=messages, options=options)

    results = {
        "tokens_per_second": [],
        "ttft_ms": [],
        "total_time_s": [],
        "prompt_eval_rate": [],
        "generated_tokens": [],
    }

    for run in range(num_runs):
        start_time = time.perf_counter()
        first_token_time = None
        token_count = 0

        stream = ollama.chat(
            model=model,
            messages=messages,
            options=options,
            stream=True,
        )

        for chunk in stream:
            if first_token_time is None and chunk["message"]["content"]:
                first_token_time = time.perf_counter()
            if chunk["message"]["content"]:
                token_count += 1

        end_time = time.perf_counter()

        total_time = end_time - start_time
        ttft = (first_token_time - start_time) if first_token_time else total_time
        generation_time = end_time - first_token_time if first_token_time else total_time
        tps = token_count / generation_time if generation_time > 0 else 0

        results["tokens_per_second"].append(tps)
        results["ttft_ms"].append(ttft * 1000)
        results["total_time_s"].append(total_time)
        results["generated_tokens"].append(token_count)

        print(f"  Run {run + 1}/{num_runs}: {tps:.1f} tok/s, TTFT {ttft*1000:.0f}ms, {token_count} tokens")

    summary = {}
    for key, values in results.items():
        summary[key] = {
            "mean": round(statistics.mean(values), 2),
            "median": round(statistics.median(values), 2),
            "stdev": round(statistics.stdev(values), 2) if len(values) > 1 else 0,
            "min": round(min(values), 2),
            "max": round(max(values), 2),
        }

    summary["model"] = model
    summary["prompt_length"] = len(prompt)
    summary["num_ctx"] = num_ctx
    summary["num_runs"] = num_runs

    return summary


def print_benchmark_report(result: dict) -> None:
    """Print a formatted benchmark report."""
    print(f"\n{'='*60}")
    print(f"BENCHMARK REPORT: {result['model']}")
    print(f"{'='*60}")
    print(f"Prompt length: {result['prompt_length']} chars")
    print(f"Context window: {result['num_ctx']}")
    print(f"Runs: {result['num_runs']}")
    print(f"\n{'Metric':<30} {'Mean':>8} {'Median':>8} {'StdDev':>8}")
    print(f"{'-'*54}")

    tps = result["tokens_per_second"]
    print(f"{'Tokens/sec':<30} {tps['mean']:>8.1f} {tps['median']:>8.1f} {tps['stdev']:>8.1f}")

    ttft = result["ttft_ms"]
    print(f"{'TTFT (ms)':<30} {ttft['mean']:>8.0f} {ttft['median']:>8.0f} {ttft['stdev']:>8.0f}")

    total = result["total_time_s"]
    print(f"{'Total time (s)':<30} {total['mean']:>8.2f} {total['median']:>8.2f} {total['stdev']:>8.2f}")

    tokens = result["generated_tokens"]
    print(f"{'Generated tokens':<30} {tokens['mean']:>8.0f} {tokens['median']:>8.0f} {tokens['stdev']:>8.0f}")

    print(f"{'='*60}\n")
```

### Python Benchmarking Script (httpx - Low Level)

For more precise timing and access to Ollama's internal metrics:

```python
import time
import json
import statistics
import httpx


OLLAMA_BASE_URL = "http://localhost:11434"


def benchmark_with_httpx(
    model: str,
    prompt: str,
    num_runs: int = 5,
    num_ctx: int = 4096,
    warmup_runs: int = 1,
) -> dict:
    """Benchmark using httpx for access to Ollama's internal timing metrics.

    Args:
        model: The Ollama model name/tag to benchmark.
        prompt: The prompt to use for benchmarking.
        num_runs: Number of benchmark iterations.
        num_ctx: Context window size.
        warmup_runs: Number of warmup runs.

    Returns:
        Dictionary with detailed benchmark results including Ollama internals.
    """
    payload = {
        "model": model,
        "prompt": prompt,
        "stream": False,
        "options": {"num_ctx": num_ctx},
    }

    # Warmup
    for _ in range(warmup_runs):
        httpx.post(
            f"{OLLAMA_BASE_URL}/api/generate",
            json=payload,
            timeout=120.0,
        )

    results = []

    for run in range(num_runs):
        start = time.perf_counter()
        response = httpx.post(
            f"{OLLAMA_BASE_URL}/api/generate",
            json=payload,
            timeout=120.0,
        )
        wall_time = time.perf_counter() - start

        data = response.json()

        # Ollama provides internal timing in nanoseconds
        result = {
            "wall_time_s": wall_time,
            "total_duration_s": data.get("total_duration", 0) / 1e9,
            "load_duration_s": data.get("load_duration", 0) / 1e9,
            "prompt_eval_count": data.get("prompt_eval_count", 0),
            "prompt_eval_duration_s": data.get("prompt_eval_duration", 0) / 1e9,
            "eval_count": data.get("eval_count", 0),
            "eval_duration_s": data.get("eval_duration", 0) / 1e9,
        }

        # Calculate rates
        if result["eval_duration_s"] > 0:
            result["tokens_per_second"] = result["eval_count"] / result["eval_duration_s"]
        else:
            result["tokens_per_second"] = 0

        if result["prompt_eval_duration_s"] > 0:
            result["prompt_eval_rate"] = (
                result["prompt_eval_count"] / result["prompt_eval_duration_s"]
            )
        else:
            result["prompt_eval_rate"] = 0

        results.append(result)

        print(
            f"  Run {run + 1}/{num_runs}: "
            f"{result['tokens_per_second']:.1f} tok/s, "
            f"prompt eval {result['prompt_eval_rate']:.1f} tok/s, "
            f"{result['eval_count']} tokens"
        )

    # Aggregate statistics
    summary = {"model": model, "num_ctx": num_ctx, "num_runs": num_runs}
    for key in ["tokens_per_second", "prompt_eval_rate", "wall_time_s",
                "eval_count", "prompt_eval_count"]:
        values = [r[key] for r in results]
        summary[key] = {
            "mean": round(statistics.mean(values), 2),
            "median": round(statistics.median(values), 2),
            "stdev": round(statistics.stdev(values), 2) if len(values) > 1 else 0,
        }

    return summary


def compare_models(
    models: list[str],
    prompt: str,
    num_runs: int = 3,
    num_ctx: int = 4096,
) -> list[dict]:
    """Benchmark multiple models and produce a comparison table.

    Args:
        models: List of model names/tags to compare.
        prompt: The prompt to use for all benchmarks.
        num_runs: Number of runs per model.
        num_ctx: Context window size for all models.

    Returns:
        List of benchmark result dictionaries, one per model.
    """
    all_results = []
    for model in models:
        print(f"\nBenchmarking: {model}")
        result = benchmark_with_httpx(
            model=model,
            prompt=prompt,
            num_runs=num_runs,
            num_ctx=num_ctx,
        )
        all_results.append(result)

    # Print comparison table
    print(f"\n{'='*80}")
    print(f"MODEL COMPARISON (num_ctx={num_ctx}, {num_runs} runs each)")
    print(f"{'='*80}")
    print(f"{'Model':<35} {'Tok/s':>8} {'Prompt Eval':>12} {'Tokens':>8}")
    print(f"{'-'*63}")
    for r in all_results:
        print(
            f"{r['model']:<35} "
            f"{r['tokens_per_second']['mean']:>8.1f} "
            f"{r['prompt_eval_rate']['mean']:>12.1f} "
            f"{r['eval_count']['mean']:>8.0f}"
        )
    print(f"{'='*80}\n")

    return all_results
```

### Running a Full Benchmark Suite

```python
import json
from datetime import datetime


def run_full_benchmark(
    model: str,
    prompts: dict,
    num_runs: int = 3,
    num_ctx: int = 4096,
    output_file: str | None = None,
) -> dict:
    """Run a full benchmark suite against a model.

    Args:
        model: Model name/tag.
        prompts: Dictionary of benchmark prompts (see BENCHMARK_PROMPTS).
        num_runs: Runs per prompt.
        num_ctx: Context window size.
        output_file: Optional JSON file to save results.

    Returns:
        Complete benchmark results dictionary.
    """
    full_results = {
        "model": model,
        "timestamp": datetime.now().isoformat(),
        "num_ctx": num_ctx,
        "num_runs": num_runs,
        "benchmarks": {},
    }

    for name, config in prompts.items():
        print(f"\n--- {name} ({config['category']}) ---")
        result = benchmark_with_httpx(
            model=model,
            prompt=config["prompt"],
            num_runs=num_runs,
            num_ctx=num_ctx,
        )
        full_results["benchmarks"][name] = result

    # Summary
    all_tps = [
        r["tokens_per_second"]["mean"]
        for r in full_results["benchmarks"].values()
    ]
    full_results["overall_mean_tps"] = round(
        sum(all_tps) / len(all_tps), 2
    )

    if output_file:
        with open(output_file, "w") as f:
            json.dump(full_results, f, indent=2)
        print(f"\nResults saved to {output_file}")

    print(f"\nOverall mean tokens/sec: {full_results['overall_mean_tps']}")
    return full_results
```

## Hardware Matching Guide

### NVIDIA Jetson (Edge Deployment)

| Device | VRAM (Shared) | Recommended Models | Quantization |
|--------|--------------|-------------------|--------------|
| Jetson Nano (4GB) | 4 GB shared | Phi-3 mini 3.8B, Gemma 2B | Q4_K_M |
| Jetson Orin Nano (8GB) | 8 GB shared | Llama 3.2 3B, Phi-3 mini 3.8B | Q4_K_M - Q5_K_M |
| Jetson Orin NX (16GB) | 16 GB shared | Llama 3.1 8B, Mistral 7B | Q4_K_M - Q5_K_M |
| Jetson AGX Orin (32/64GB) | 32-64 GB shared | Llama 3.1 8B, Codestral 22B | Q5_K_M - Q8_0 |

**Jetson Notes:**
- Memory is shared between CPU and GPU; leave 2-4 GB for the OS and other processes
- Use `tegrastats` to monitor memory usage instead of `nvidia-smi`
- Expect 30-60% of desktop GPU performance due to memory bandwidth limitations
- JetPack must be installed; Ollama ARM builds work on Jetson

### Consumer GPUs

| GPU | VRAM | Recommended Models | Quantization |
|-----|------|--------------------|--------------|
| RTX 3060 | 12 GB | 7B models | Q4_K_M - Q8_0 |
| RTX 3070 | 8 GB | 7B models | Q4_K_M - Q5_K_M |
| RTX 3080 | 10 GB | 7B models | Q4_K_M - Q8_0 |
| RTX 3090 | 24 GB | 7B-13B models | Q5_K_M - Q8_0 |
| RTX 4060 | 8 GB | 7B models | Q4_K_M - Q5_K_M |
| RTX 4070 | 12 GB | 7B models | Q4_K_M - Q8_0 |
| RTX 4080 | 16 GB | 7B-13B models | Q5_K_M - Q8_0 |
| RTX 4090 | 24 GB | 7B-34B models | Q5_K_M - FP16 (7B) |
| RTX 5090 | 32 GB | 7B-34B models | Q8_0 - FP16 (7B-13B) |

### Apple Silicon (Mac)

| Chip | Unified Memory | Recommended Models | Quantization |
|------|---------------|-------------------|--------------|
| M1 (8GB) | 8 GB | 7B models | Q4_K_M |
| M1 (16GB) | 16 GB | 7B-13B models | Q4_K_M - Q5_K_M |
| M1 Pro (16GB) | 16 GB | 7B-13B models | Q5_K_M |
| M1 Max (32GB) | 32 GB | 7B-34B models | Q5_K_M - Q8_0 |
| M2 (8GB) | 8 GB | 7B models | Q4_K_M |
| M2 Pro (16-32GB) | 16-32 GB | 7B-13B models | Q5_K_M - Q8_0 |
| M2 Max (32-96GB) | 32-96 GB | 7B-70B models | Q5_K_M - Q8_0 |
| M2 Ultra (64-192GB) | 64-192 GB | 7B-70B models | Q8_0 - FP16 |
| M3 (8-24GB) | 8-24 GB | 7B-13B models | Q4_K_M - Q5_K_M |
| M3 Pro (18-36GB) | 18-36 GB | 7B-34B models | Q5_K_M - Q8_0 |
| M3 Max (36-128GB) | 36-128 GB | 7B-70B models | Q5_K_M - FP16 |
| M4 (16-32GB) | 16-32 GB | 7B-13B models | Q5_K_M - Q8_0 |
| M4 Pro (24-48GB) | 24-48 GB | 7B-34B models | Q5_K_M - Q8_0 |
| M4 Max (36-128GB) | 36-128 GB | 7B-70B models | Q8_0 - FP16 |

**Mac Notes:**
- Unified memory is shared with the OS; leave 4-8 GB free for the system
- Metal GPU acceleration is used by default; very efficient on Apple Silicon
- Memory bandwidth is excellent on Max/Ultra chips (400-800 GB/s)
- M-series Macs often outperform similarly-speced NVIDIA GPUs in tokens/sec for quantized models due to memory bandwidth advantage

### CPU-Only Systems

| RAM | Recommended Models | Expected Performance |
|-----|--------------------|---------------------|
| 8 GB | Phi-3 mini 3.8B Q4_K_M | 2-5 tok/s |
| 16 GB | 7B models Q4_K_M | 1-4 tok/s |
| 32 GB | 7B-13B models Q4_K_M | 1-3 tok/s |
| 64 GB | 13B-34B models Q4_K_M | 0.5-2 tok/s |

**CPU-Only Notes:**
- Performance scales with memory bandwidth and core count
- AVX2/AVX-512 instruction support significantly impacts performance
- Set `OLLAMA_NUM_PARALLEL=1` to avoid memory contention
- Consider embedding models for RAG; they are fast even on CPU

## Performance Comparison Tables

### 7B Models Comparison (RTX 4070 12GB, Q5_K_M, 4K ctx)

| Model | Tok/s | TTFT (ms) | Quality (code) | Quality (chat) |
|-------|-------|-----------|---------------|----------------|
| Llama 3.1 8B Instruct | 45-55 | 200-400 | Very good | Very good |
| Mistral 7B Instruct v0.3 | 50-60 | 180-350 | Good | Very good |
| Qwen 2.5 7B Instruct | 45-55 | 200-400 | Very good | Good |
| Gemma 2 9B Instruct | 35-45 | 250-450 | Good | Very good |
| DeepSeek Coder V2 Lite | 40-50 | 220-400 | Excellent | Fair |
| Phi-3 Medium 14B | 25-35 | 350-600 | Good | Good |
| CodeLlama 7B Instruct | 50-60 | 180-350 | Very good | Fair |

### Quantization Speed Impact (Llama 3.1 8B, RTX 4070, 4K ctx)

| Quantization | Model Size | Tok/s | TTFT (ms) | Relative Quality |
|-------------|-----------|-------|-----------|-----------------|
| Q4_K_M | 4.7 GB | 55-65 | 150-300 | 92% |
| Q5_K_M | 5.3 GB | 45-55 | 200-400 | 96% |
| Q6_K | 6.1 GB | 38-48 | 250-450 | 98% |
| Q8_0 | 8.0 GB | 30-40 | 300-500 | 99% |
| FP16 | 15.3 GB | N/A (OOM) | N/A | 100% |

### Embedding Model Throughput (RTX 4070)

| Model | Dimensions | Docs/sec (avg 200 tokens) | Quality (MTEB) |
|-------|-----------|--------------------------|----------------|
| nomic-embed-text | 768 | 300-500 | Good |
| mxbai-embed-large | 1024 | 200-350 | Very good |
| all-minilm | 384 | 800-1200 | Acceptable |
| snowflake-arctic-embed | 1024 | 200-350 | Very good |

## Automated Hardware Detection Script

```python
import subprocess
import platform
import os


def detect_hardware() -> dict:
    """Detect available hardware for Ollama model selection.

    Returns:
        Dictionary describing available compute resources.
    """
    hw = {
        "platform": platform.system(),
        "arch": platform.machine(),
        "cpu_count": os.cpu_count(),
        "gpus": [],
        "recommendation": "",
    }

    # Try NVIDIA GPU detection
    try:
        result = subprocess.run(
            [
                "nvidia-smi",
                "--query-gpu=name,memory.total,memory.free,driver_version",
                "--format=csv,noheader,nounits",
            ],
            capture_output=True,
            text=True,
            check=True,
        )
        for line in result.stdout.strip().split("\n"):
            parts = [p.strip() for p in line.split(",")]
            if len(parts) >= 4:
                hw["gpus"].append({
                    "type": "nvidia",
                    "name": parts[0],
                    "total_mb": int(parts[1]),
                    "free_mb": int(parts[2]),
                    "free_gb": round(int(parts[2]) / 1024, 1),
                    "driver": parts[3],
                })
    except (FileNotFoundError, subprocess.CalledProcessError):
        pass

    # Try Jetson detection
    if not hw["gpus"] and os.path.exists("/etc/nv_tegra_release"):
        try:
            with open("/proc/meminfo") as f:
                for line in f:
                    if line.startswith("MemTotal:"):
                        total_kb = int(line.split()[1])
                        total_gb = round(total_kb / (1024 * 1024), 1)
                        hw["gpus"].append({
                            "type": "jetson",
                            "name": "NVIDIA Jetson (shared memory)",
                            "total_gb": total_gb,
                            "note": "Shared CPU/GPU memory. Reserve 2-4 GB for OS.",
                        })
                        break
        except OSError:
            pass

    # macOS Metal detection
    if hw["platform"] == "Darwin":
        try:
            result = subprocess.run(
                ["sysctl", "-n", "hw.memsize"],
                capture_output=True,
                text=True,
                check=True,
            )
            total_bytes = int(result.stdout.strip())
            total_gb = round(total_bytes / (1024 ** 3), 1)
            hw["gpus"].append({
                "type": "apple_silicon",
                "name": f"Apple Silicon ({platform.machine()})",
                "unified_memory_gb": total_gb,
                "note": "Unified memory. Reserve 4-8 GB for macOS.",
            })
        except (FileNotFoundError, subprocess.CalledProcessError):
            pass

    # Generate recommendation
    if not hw["gpus"]:
        hw["recommendation"] = (
            "CPU-only detected. Use small models (3-7B) at Q4_K_M. "
            "Expect 1-5 tok/s."
        )
    else:
        gpu = hw["gpus"][0]
        if gpu["type"] == "nvidia":
            free_gb = gpu["free_gb"]
            if free_gb >= 20:
                hw["recommendation"] = f"{free_gb} GB free VRAM. Can run 13B+ models at Q8_0."
            elif free_gb >= 10:
                hw["recommendation"] = f"{free_gb} GB free VRAM. Ideal for 7B at Q8_0 or 13B at Q4_K_M."
            elif free_gb >= 6:
                hw["recommendation"] = f"{free_gb} GB free VRAM. Good for 7B at Q4_K_M-Q5_K_M."
            else:
                hw["recommendation"] = f"{free_gb} GB free VRAM. Use small models (3B) at Q4_K_M."
        elif gpu["type"] == "apple_silicon":
            mem_gb = gpu["unified_memory_gb"]
            usable = mem_gb - 6  # Reserve for OS
            hw["recommendation"] = (
                f"{mem_gb} GB unified memory (~{usable:.0f} GB usable). "
                f"Apple Silicon is efficient with quantized models."
            )
        elif gpu["type"] == "jetson":
            total_gb = gpu["total_gb"]
            usable = total_gb - 3
            hw["recommendation"] = (
                f"{total_gb} GB shared memory (~{usable:.0f} GB usable). "
                f"Use edge-optimized models at Q4_K_M."
            )

    return hw


if __name__ == "__main__":
    hw = detect_hardware()
    print(f"Platform: {hw['platform']} ({hw['arch']})")
    print(f"CPU cores: {hw['cpu_count']}")
    for gpu in hw["gpus"]:
        print(f"GPU: {gpu['name']}")
        if "free_gb" in gpu:
            print(f"  Free VRAM: {gpu['free_gb']} GB")
        if "unified_memory_gb" in gpu:
            print(f"  Unified Memory: {gpu['unified_memory_gb']} GB")
    print(f"\nRecommendation: {hw['recommendation']}")
```
