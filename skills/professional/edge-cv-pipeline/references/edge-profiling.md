# Edge Profiling

## Overview

Profiling on edge devices is fundamentally different from profiling on desktops.
Thermal throttling, shared memory buses, and limited RAM make measurement both
more important and more difficult. This reference provides every profiling pattern
you need for Jetson and Raspberry Pi deployments.

## Dependencies

```bash
# Core profiling
pip install numpy psutil

# Memory profiling
pip install memory-profiler

# Visualization (optional, for generating reports)
pip install matplotlib
```

---

## FPS Measurement

### Basic FPS Counter

```python
import time
from collections import deque


class FPSCounter:
    """Accurate FPS measurement with windowed averaging."""

    def __init__(self, window_size=60):
        self.timestamps = deque(maxlen=window_size)

    def tick(self):
        """Call once per frame."""
        self.timestamps.append(time.perf_counter())

    @property
    def fps(self):
        """Current FPS (windowed average)."""
        if len(self.timestamps) < 2:
            return 0.0
        elapsed = self.timestamps[-1] - self.timestamps[0]
        if elapsed <= 0:
            return 0.0
        return (len(self.timestamps) - 1) / elapsed

    @property
    def frame_time_ms(self):
        """Average time per frame in milliseconds."""
        if self.fps <= 0:
            return 0.0
        return 1000.0 / self.fps
```

### FPS with Min/Max/P95 Tracking

```python
import time
import numpy as np
from collections import deque


class DetailedFPSCounter:
    """FPS counter with percentile tracking for edge variability."""

    def __init__(self, window_size=300):
        self.frame_times = deque(maxlen=window_size)
        self.last_tick = None

    def tick(self):
        now = time.perf_counter()
        if self.last_tick is not None:
            dt = now - self.last_tick
            self.frame_times.append(dt)
        self.last_tick = now

    def report(self):
        """Return detailed FPS statistics."""
        if len(self.frame_times) < 2:
            return {"fps_mean": 0, "status": "insufficient data"}

        times = np.array(self.frame_times)
        fps_values = 1.0 / times

        return {
            "fps_mean": float(np.mean(fps_values)),
            "fps_min": float(np.min(fps_values)),
            "fps_max": float(np.max(fps_values)),
            "fps_p5": float(np.percentile(fps_values, 5)),
            "fps_p95": float(np.percentile(fps_values, 95)),
            "frame_time_mean_ms": float(np.mean(times) * 1000),
            "frame_time_p95_ms": float(np.percentile(times, 95) * 1000),
            "frame_time_p99_ms": float(np.percentile(times, 99) * 1000),
            "frame_count": len(self.frame_times),
            "jitter_ms": float(np.std(times) * 1000),
        }
```

---

## Per-Stage Latency Profiling

### Stage Timer

This is the most important profiling tool for edge CV. Measure each pipeline
stage independently to identify the bottleneck.

```python
import time
from collections import defaultdict
import numpy as np


class StageProfiler:
    """Profile individual pipeline stages with statistical aggregation."""

    def __init__(self):
        self.timings = defaultdict(list)
        self._current_stage = None
        self._stage_start = None

    def start(self, stage_name):
        """Mark the start of a pipeline stage."""
        self._current_stage = stage_name
        self._stage_start = time.perf_counter_ns()

    def stop(self):
        """Mark the end of the current stage and record duration."""
        if self._current_stage is None:
            return
        elapsed_ns = time.perf_counter_ns() - self._stage_start
        elapsed_ms = elapsed_ns / 1_000_000
        self.timings[self._current_stage].append(elapsed_ms)
        self._current_stage = None

    def report(self):
        """Generate profiling report for all stages."""
        results = {}
        total_mean = 0

        for stage, times in self.timings.items():
            arr = np.array(times)
            stage_mean = float(np.mean(arr))
            total_mean += stage_mean
            results[stage] = {
                "mean_ms": stage_mean,
                "median_ms": float(np.median(arr)),
                "p95_ms": float(np.percentile(arr, 95)),
                "p99_ms": float(np.percentile(arr, 99)),
                "min_ms": float(np.min(arr)),
                "max_ms": float(np.max(arr)),
                "std_ms": float(np.std(arr)),
                "count": len(times),
            }

        results["_total"] = {
            "mean_ms": total_mean,
            "max_fps": 1000.0 / total_mean if total_mean > 0 else 0,
        }

        return results

    def print_report(self):
        """Print a formatted profiling report."""
        report = self.report()

        print("\n" + "=" * 65)
        print("PIPELINE PROFILING REPORT")
        print("=" * 65)
        print(f"{'Stage':<15} {'Mean':>8} {'P95':>8} {'P99':>8} {'Count':>7}")
        print("-" * 65)

        for stage in self.timings:
            r = report[stage]
            print(
                f"{stage:<15} "
                f"{r['mean_ms']:>7.1f}ms "
                f"{r['p95_ms']:>7.1f}ms "
                f"{r['p99_ms']:>7.1f}ms "
                f"{r['count']:>7d}"
            )

        total = report["_total"]
        print("-" * 65)
        print(f"{'TOTAL':<15} {total['mean_ms']:>7.1f}ms")
        print(f"{'MAX FPS':<15} {total['max_fps']:>7.1f}")
        print("=" * 65)


# Usage in pipeline loop
profiler = StageProfiler()

# for frame in frames:
#     profiler.start("capture")
#     frame = capture.read()
#     profiler.stop()
#
#     profiler.start("preprocess")
#     input_data = preprocess(frame)
#     profiler.stop()
#
#     profiler.start("infer")
#     outputs = infer(interpreter, input_data)
#     profiler.stop()
#
#     profiler.start("postprocess")
#     detections = postprocess(outputs)
#     profiler.stop()
#
#     profiler.start("publish")
#     publisher.publish(detections)
#     profiler.stop()
#
# profiler.print_report()
```

### Context Manager Timer

```python
import time
from contextlib import contextmanager


@contextmanager
def stage_timer(label, results_dict=None):
    """Context manager for timing a pipeline stage."""
    start = time.perf_counter_ns()
    yield
    elapsed_ms = (time.perf_counter_ns() - start) / 1_000_000

    if results_dict is not None:
        if label not in results_dict:
            results_dict[label] = []
        results_dict[label].append(elapsed_ms)
    else:
        print(f"[{label}] {elapsed_ms:.2f}ms")


# Usage
timings = {}

# with stage_timer("capture", timings):
#     frame = capture.read()
# with stage_timer("preprocess", timings):
#     input_data = preprocess(frame)
# with stage_timer("infer", timings):
#     outputs = infer(interpreter, input_data)
```

---

## Memory Profiling

### RAM Usage Monitoring

```python
import psutil
import os


class MemoryMonitor:
    """Monitor process and system memory usage."""

    def __init__(self):
        self.process = psutil.Process(os.getpid())
        self.peak_rss = 0

    def snapshot(self):
        """Take a memory snapshot."""
        mem = self.process.memory_info()
        self.peak_rss = max(self.peak_rss, mem.rss)

        sys_mem = psutil.virtual_memory()

        return {
            "process_rss_mb": mem.rss / 1024 / 1024,
            "process_vms_mb": mem.vms / 1024 / 1024,
            "process_peak_rss_mb": self.peak_rss / 1024 / 1024,
            "system_total_mb": sys_mem.total / 1024 / 1024,
            "system_available_mb": sys_mem.available / 1024 / 1024,
            "system_percent_used": sys_mem.percent,
        }

    def print_snapshot(self, label=""):
        """Print current memory state."""
        snap = self.snapshot()
        prefix = f"[{label}] " if label else ""
        print(
            f"{prefix}"
            f"RSS: {snap['process_rss_mb']:.1f}MB "
            f"(peak: {snap['process_peak_rss_mb']:.1f}MB) | "
            f"System: {snap['system_percent_used']:.0f}% used "
            f"({snap['system_available_mb']:.0f}MB free)"
        )


# Usage: measure memory at each pipeline stage
memory = MemoryMonitor()
# memory.print_snapshot("before model load")
# interpreter = load_model(...)
# memory.print_snapshot("after model load")
# frame = capture.read()
# memory.print_snapshot("after first frame")
```

### Model Memory Footprint

```python
import os
import numpy as np
import tflite_runtime.interpreter as tflite


def measure_model_footprint(model_path):
    """Measure TFLite model file size and runtime memory."""
    # File size
    file_size_mb = os.path.getsize(model_path) / 1024 / 1024

    # Load and measure runtime allocation
    import psutil
    process = psutil.Process(os.getpid())
    mem_before = process.memory_info().rss

    interpreter = tflite.Interpreter(model_path=model_path, num_threads=4)
    interpreter.allocate_tensors()

    mem_after = process.memory_info().rss
    runtime_mb = (mem_after - mem_before) / 1024 / 1024

    # Input/output tensor sizes
    input_details = interpreter.get_input_details()
    output_details = interpreter.get_output_details()

    input_sizes = []
    for inp in input_details:
        size = np.prod(inp["shape"]) * np.dtype(inp["dtype"]).itemsize
        input_sizes.append(size / 1024)

    output_sizes = []
    for out in output_details:
        size = np.prod(out["shape"]) * np.dtype(out["dtype"]).itemsize
        output_sizes.append(size / 1024)

    return {
        "file_size_mb": file_size_mb,
        "runtime_memory_mb": runtime_mb,
        "input_tensor_sizes_kb": input_sizes,
        "output_tensor_sizes_kb": output_sizes,
        "num_threads": 4,
    }


# Usage
# footprint = measure_model_footprint("model.tflite")
# print(f"File: {footprint['file_size_mb']:.1f}MB")
# print(f"Runtime: {footprint['runtime_memory_mb']:.1f}MB")
```

---

## Thermal Monitoring

### Read Temperature (Cross-Platform)

```python
import subprocess
import glob


def read_temperature_linux():
    """Read CPU temperature from thermal zones (works on RPi and Jetson)."""
    thermal_zones = glob.glob("/sys/class/thermal/thermal_zone*/temp")
    temps = {}
    for zone_path in thermal_zones:
        zone_name = zone_path.split("/")[-2]
        try:
            with open(zone_path, "r") as f:
                temp_milli = int(f.read().strip())
                temps[zone_name] = temp_milli / 1000.0  # Convert to Celsius
        except (IOError, ValueError):
            continue
    return temps


def read_temperature_rpi():
    """Read Raspberry Pi GPU/CPU temperature via vcgencmd."""
    try:
        result = subprocess.run(
            ["vcgencmd", "measure_temp"],
            capture_output=True, text=True, timeout=2
        )
        # Output: "temp=52.6'C"
        temp_str = result.stdout.strip().replace("temp=", "").replace("'C", "")
        return float(temp_str)
    except (subprocess.TimeoutExpired, ValueError, FileNotFoundError):
        return None


def read_throttle_status_rpi():
    """Check if Raspberry Pi is currently throttling."""
    try:
        result = subprocess.run(
            ["vcgencmd", "get_throttled"],
            capture_output=True, text=True, timeout=2
        )
        # Output: "throttled=0x50000" -- nonzero means throttling has occurred
        hex_str = result.stdout.strip().split("=")[1]
        flags = int(hex_str, 16)

        return {
            "raw": hex_str,
            "currently_under_voltage": bool(flags & 0x1),
            "currently_throttled": bool(flags & 0x2),
            "currently_soft_temp_limit": bool(flags & 0x8),
            "under_voltage_occurred": bool(flags & 0x10000),
            "throttled_occurred": bool(flags & 0x20000),
            "soft_temp_limit_occurred": bool(flags & 0x80000),
        }
    except (subprocess.TimeoutExpired, ValueError, FileNotFoundError):
        return None
```

### Jetson Thermal and Power Monitoring

```python
import subprocess
import re


def parse_tegrastats_line(line):
    """Parse a single line of tegrastats output."""
    stats = {}

    # RAM: 2345/7620MB
    ram_match = re.search(r"RAM (\d+)/(\d+)MB", line)
    if ram_match:
        stats["ram_used_mb"] = int(ram_match.group(1))
        stats["ram_total_mb"] = int(ram_match.group(2))

    # CPU [45%@1420,30%@1420,50%@1420,25%@1420]
    cpu_match = re.search(r"CPU \[([\d%@,]+)\]", line)
    if cpu_match:
        cpu_loads = re.findall(r"(\d+)%", cpu_match.group(1))
        stats["cpu_loads_percent"] = [int(c) for c in cpu_loads]
        stats["cpu_avg_percent"] = sum(stats["cpu_loads_percent"]) / len(
            stats["cpu_loads_percent"]
        )

    # GR3D_FREQ 76%
    gpu_match = re.search(r"GR3D_FREQ (\d+)%", line)
    if gpu_match:
        stats["gpu_percent"] = int(gpu_match.group(1))

    # Temperature fields like CPU@45C GPU@42C
    temp_matches = re.findall(r"(\w+)@([\d.]+)C", line)
    if temp_matches:
        stats["temperatures"] = {name: float(val) for name, val in temp_matches}

    # Power: VDD_CPU_GPU_CV 2500mW VDD_SOC 1200mW
    power_matches = re.findall(r"(VDD_\w+)\s+(\d+)mW", line)
    if power_matches:
        stats["power_mw"] = {name: int(val) for name, val in power_matches}
        stats["total_power_mw"] = sum(stats["power_mw"].values())

    return stats


def read_tegrastats_snapshot():
    """Read a single snapshot from tegrastats."""
    try:
        result = subprocess.run(
            ["tegrastats", "--interval", "1000"],
            capture_output=True, text=True, timeout=3
        )
        lines = result.stdout.strip().split("\n")
        if lines:
            return parse_tegrastats_line(lines[0])
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return None
    return None
```

### Continuous Thermal Monitor

```python
import time
import threading
from collections import deque


class ThermalMonitor:
    """Background thermal monitoring with alert thresholds."""

    def __init__(self, warn_temp=75.0, critical_temp=82.0, interval=5.0):
        self.warn_temp = warn_temp
        self.critical_temp = critical_temp
        self.interval = interval
        self.history = deque(maxlen=100)
        self.stopped = False
        self.is_throttling = False

    def start(self):
        thread = threading.Thread(target=self._monitor_loop, daemon=True)
        thread.start()
        return self

    def _monitor_loop(self):
        while not self.stopped:
            temps = read_temperature_linux()
            if temps:
                max_temp = max(temps.values())
                self.history.append({
                    "timestamp": time.time(),
                    "max_temp_c": max_temp,
                    "all_temps": temps,
                })

                if max_temp >= self.critical_temp:
                    self.is_throttling = True
                    print(
                        f"THERMAL CRITICAL: {max_temp:.1f}C "
                        f"(threshold: {self.critical_temp}C)"
                    )
                elif max_temp >= self.warn_temp:
                    print(
                        f"THERMAL WARNING: {max_temp:.1f}C "
                        f"(threshold: {self.warn_temp}C)"
                    )
                else:
                    self.is_throttling = False

            time.sleep(self.interval)

    def current_temp(self):
        """Get the most recent temperature reading."""
        if self.history:
            return self.history[-1]["max_temp_c"]
        return None

    def report(self):
        """Thermal summary over monitoring period."""
        if not self.history:
            return {"status": "no data"}

        temps = [h["max_temp_c"] for h in self.history]
        return {
            "current_c": temps[-1],
            "mean_c": sum(temps) / len(temps),
            "max_c": max(temps),
            "min_c": min(temps),
            "samples": len(temps),
            "is_throttling": self.is_throttling,
        }

    def stop(self):
        self.stopped = True
```

---

## Profiling Tools Reference

### Jetson Tools

```bash
# tegrastats -- real-time system metrics (CPU, GPU, RAM, power, temp)
sudo tegrastats --interval 1000

# jetson_clocks -- show or set clock frequencies
sudo jetson_clocks --show
sudo jetson_clocks          # Set max clocks (for benchmarking only)

# jtop -- interactive Jetson monitor (install: pip install jetson-stats)
jtop

# nvpmodel -- power mode control
sudo nvpmodel -q            # Query current mode
sudo nvpmodel -m 0          # MAXN (max performance)
sudo nvpmodel -m 1          # 15W (power-constrained)
```

### Raspberry Pi Tools

```bash
# CPU temperature
vcgencmd measure_temp

# Throttle status
vcgencmd get_throttled

# Clock frequencies
vcgencmd measure_clock arm

# Voltage
vcgencmd measure_volts core

# Memory split
vcgencmd get_mem arm && vcgencmd get_mem gpu

# htop for process monitoring
htop

# System memory
free -m
watch -n 1 free -m
```

### Python Profiling

```bash
# cProfile -- function-level profiling
python -m cProfile -s cumulative pipeline.py

# line_profiler -- line-by-line profiling
pip install line-profiler
kernprof -l -v pipeline.py

# memory_profiler -- per-line memory usage
pip install memory-profiler
python -m memory_profiler pipeline.py
```

---

## Performance Optimization Strategies

### Resolution Reduction

The fastest optimization. Reducing input resolution has a quadratic effect
on preprocessing and often a significant effect on inference.

```python
import time
import numpy as np
import tflite_runtime.interpreter as tflite


def benchmark_resolution(model_path, resolutions, num_frames=100):
    """Benchmark inference at different input resolutions."""
    results = []

    for width, height in resolutions:
        interpreter = tflite.Interpreter(model_path=model_path, num_threads=4)

        # Resize input tensor
        input_details = interpreter.get_input_details()
        interpreter.resize_tensor_input(
            input_details[0]["index"], [1, height, width, 3]
        )
        interpreter.allocate_tensors()

        input_data = np.random.rand(1, height, width, 3).astype(np.float32)

        # Warmup
        for _ in range(10):
            interpreter.set_tensor(input_details[0]["index"], input_data)
            interpreter.invoke()

        # Benchmark
        times = []
        for _ in range(num_frames):
            start = time.perf_counter_ns()
            interpreter.set_tensor(input_details[0]["index"], input_data)
            interpreter.invoke()
            elapsed_ms = (time.perf_counter_ns() - start) / 1_000_000
            times.append(elapsed_ms)

        arr = np.array(times)
        results.append({
            "resolution": f"{width}x{height}",
            "mean_ms": float(np.mean(arr)),
            "p95_ms": float(np.percentile(arr, 95)),
            "max_fps": 1000.0 / float(np.mean(arr)),
        })

    return results


# Usage:
# results = benchmark_resolution("model.tflite", [
#     (128, 128), (192, 192), (256, 256), (320, 320), (416, 416)
# ])
# for r in results:
#     print(f"{r['resolution']}: {r['mean_ms']:.1f}ms ({r['max_fps']:.0f} fps)")
```

### Thread Count Tuning

```python
import time
import numpy as np
import tflite_runtime.interpreter as tflite


def benchmark_thread_count(model_path, thread_counts=None, num_frames=100):
    """Find the optimal thread count for this model on this device."""
    if thread_counts is None:
        import os
        max_threads = os.cpu_count() or 4
        thread_counts = list(range(1, max_threads + 1))

    input_shape = None
    results = []

    for num_threads in thread_counts:
        interpreter = tflite.Interpreter(
            model_path=model_path, num_threads=num_threads
        )
        interpreter.allocate_tensors()

        input_details = interpreter.get_input_details()
        if input_shape is None:
            input_shape = input_details[0]["shape"]

        input_data = np.random.rand(*input_shape).astype(np.float32)

        # Warmup
        for _ in range(10):
            interpreter.set_tensor(input_details[0]["index"], input_data)
            interpreter.invoke()

        # Benchmark
        times = []
        for _ in range(num_frames):
            start = time.perf_counter_ns()
            interpreter.set_tensor(input_details[0]["index"], input_data)
            interpreter.invoke()
            elapsed_ms = (time.perf_counter_ns() - start) / 1_000_000
            times.append(elapsed_ms)

        arr = np.array(times)
        results.append({
            "threads": num_threads,
            "mean_ms": float(np.mean(arr)),
            "p95_ms": float(np.percentile(arr, 95)),
            "max_fps": 1000.0 / float(np.mean(arr)),
        })

    return results


# Usage:
# results = benchmark_thread_count("model.tflite")
# for r in results:
#     print(f"{r['threads']} threads: {r['mean_ms']:.1f}ms ({r['max_fps']:.0f} fps)")
```

### Delegate Benchmarking

```python
import time
import numpy as np
import tflite_runtime.interpreter as tflite


def benchmark_delegates(model_path, num_frames=100):
    """Compare inference speed across available delegates."""
    results = []

    # CPU baseline (no delegate)
    try:
        interpreter = tflite.Interpreter(model_path=model_path, num_threads=4)
        interpreter.allocate_tensors()
        mean_ms = _benchmark_interpreter(interpreter, num_frames)
        results.append({"delegate": "CPU (no delegate)", "mean_ms": mean_ms})
    except Exception as e:
        results.append({"delegate": "CPU", "error": str(e)})

    # XNNPACK delegate (optimized CPU, especially for float16)
    try:
        interpreter = tflite.Interpreter(
            model_path=model_path,
            num_threads=4,
            experimental_delegates=[tflite.load_delegate("libXNNPACK.so")],
        )
        interpreter.allocate_tensors()
        mean_ms = _benchmark_interpreter(interpreter, num_frames)
        results.append({"delegate": "XNNPACK", "mean_ms": mean_ms})
    except Exception as e:
        results.append({"delegate": "XNNPACK", "error": str(e)})

    # Edge TPU delegate (Coral USB/M.2)
    try:
        interpreter = tflite.Interpreter(
            model_path=model_path,
            experimental_delegates=[
                tflite.load_delegate("libedgetpu.so.1")
            ],
        )
        interpreter.allocate_tensors()
        mean_ms = _benchmark_interpreter(interpreter, num_frames)
        results.append({"delegate": "Edge TPU (Coral)", "mean_ms": mean_ms})
    except Exception as e:
        results.append({"delegate": "Edge TPU", "error": str(e)})

    return results


def _benchmark_interpreter(interpreter, num_frames):
    """Run benchmark on a loaded interpreter."""
    input_details = interpreter.get_input_details()
    input_shape = input_details[0]["shape"]
    input_dtype = input_details[0]["dtype"]

    if input_dtype == np.uint8:
        input_data = np.random.randint(0, 255, size=input_shape, dtype=np.uint8)
    else:
        input_data = np.random.rand(*input_shape).astype(np.float32)

    # Warmup
    for _ in range(10):
        interpreter.set_tensor(input_details[0]["index"], input_data)
        interpreter.invoke()

    # Benchmark
    times = []
    for _ in range(num_frames):
        start = time.perf_counter_ns()
        interpreter.set_tensor(input_details[0]["index"], input_data)
        interpreter.invoke()
        elapsed_ms = (time.perf_counter_ns() - start) / 1_000_000
        times.append(elapsed_ms)

    return float(np.mean(times))
```

---

## Complete Profiling Session

### Full Pipeline Benchmark Script

```python
"""
Full pipeline profiling script for edge devices.

Usage:
    python profile_pipeline.py --model model.tflite --source 0 --frames 300
"""

import argparse
import time
import json
import numpy as np
import cv2
import tflite_runtime.interpreter as tflite


def profile_pipeline(model_path, camera_source, num_frames, input_size):
    """Run a complete profiling session."""
    # -- Setup --
    cap = cv2.VideoCapture(camera_source)
    if not cap.isOpened():
        raise RuntimeError(f"Cannot open camera: {camera_source}")

    cap.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)

    interpreter = tflite.Interpreter(model_path=model_path, num_threads=4)
    interpreter.allocate_tensors()
    input_details = interpreter.get_input_details()
    output_details = interpreter.get_output_details()

    # -- Stage timing storage --
    timings = {
        "capture": [], "preprocess": [], "infer": [],
        "postprocess": [], "total": [],
    }

    print(f"Profiling {num_frames} frames...")

    # -- Warmup --
    for _ in range(10):
        ret, frame = cap.read()
        if ret:
            resized = cv2.resize(frame, input_size)
            inp = np.expand_dims(resized.astype(np.float32) / 255.0, axis=0)
            interpreter.set_tensor(input_details[0]["index"], inp)
            interpreter.invoke()

    # -- Benchmark --
    for i in range(num_frames):
        t_total_start = time.perf_counter_ns()

        # Capture
        t0 = time.perf_counter_ns()
        ret, frame = cap.read()
        if not ret:
            break
        t1 = time.perf_counter_ns()
        timings["capture"].append((t1 - t0) / 1_000_000)

        # Preprocess
        t0 = time.perf_counter_ns()
        resized = cv2.resize(frame, input_size)
        input_data = np.expand_dims(resized.astype(np.float32) / 255.0, axis=0)
        t1 = time.perf_counter_ns()
        timings["preprocess"].append((t1 - t0) / 1_000_000)

        # Infer
        t0 = time.perf_counter_ns()
        interpreter.set_tensor(input_details[0]["index"], input_data)
        interpreter.invoke()
        outputs = [
            interpreter.get_tensor(d["index"]) for d in output_details
        ]
        t1 = time.perf_counter_ns()
        timings["infer"].append((t1 - t0) / 1_000_000)

        # Postprocess (placeholder -- your logic here)
        t0 = time.perf_counter_ns()
        _ = outputs  # Replace with actual postprocessing
        t1 = time.perf_counter_ns()
        timings["postprocess"].append((t1 - t0) / 1_000_000)

        # Total
        t_total_end = time.perf_counter_ns()
        timings["total"].append((t_total_end - t_total_start) / 1_000_000)

        if (i + 1) % 50 == 0:
            current_fps = 1000.0 / np.mean(timings["total"][-50:])
            print(f"  Frame {i + 1}/{num_frames}: {current_fps:.1f} fps")

    cap.release()

    # -- Report --
    report = {}
    for stage, times in timings.items():
        arr = np.array(times)
        report[stage] = {
            "mean_ms": round(float(np.mean(arr)), 2),
            "median_ms": round(float(np.median(arr)), 2),
            "p95_ms": round(float(np.percentile(arr, 95)), 2),
            "p99_ms": round(float(np.percentile(arr, 99)), 2),
            "min_ms": round(float(np.min(arr)), 2),
            "max_ms": round(float(np.max(arr)), 2),
        }

    report["summary"] = {
        "frames_profiled": len(timings["total"]),
        "mean_fps": round(1000.0 / report["total"]["mean_ms"], 1),
        "p95_fps": round(1000.0 / report["total"]["p95_ms"], 1),
        "model": model_path,
        "input_size": f"{input_size[0]}x{input_size[1]}",
    }

    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Edge CV pipeline profiler")
    parser.add_argument("--model", required=True, help="Path to TFLite model")
    parser.add_argument("--source", default=0, help="Camera source")
    parser.add_argument("--frames", type=int, default=300, help="Frames to profile")
    parser.add_argument("--width", type=int, default=320, help="Model input width")
    parser.add_argument("--height", type=int, default=320, help="Model input height")
    args = parser.parse_args()

    try:
        source = int(args.source)
    except ValueError:
        source = args.source

    report = profile_pipeline(
        model_path=args.model,
        camera_source=source,
        num_frames=args.frames,
        input_size=(args.width, args.height),
    )

    print("\n" + json.dumps(report, indent=2))

    # Save report
    output_path = "profiling_report.json"
    with open(output_path, "w") as f:
        json.dumps(report, f, indent=2)
    print(f"\nReport saved to: {output_path}")
```

---

## Quick Reference: Performance Targets by Device

| Device | Model Type | Expected FPS | Inference (ms) | Notes |
|--------|-----------|-------------|----------------|-------|
| Jetson Orin Nano | MobileNetV2 (TensorRT FP16) | 60-120 | 8-16 | Use TensorRT |
| Jetson Orin Nano | YOLOv5s (TensorRT FP16) | 30-60 | 16-33 | Use TensorRT |
| RPi 5 | MobileNetV2 (TFLite INT8) | 15-25 | 40-65 | Use XNNPACK |
| RPi 5 | SSD MobileNet (TFLite INT8) | 8-15 | 65-120 | Use XNNPACK |
| RPi 4 | MobileNetV2 (TFLite INT8) | 8-12 | 80-120 | 4 threads max |
| RPi 4 | SSD MobileNet (TFLite INT8) | 4-8 | 120-250 | Consider Coral TPU |
| RPi 4 + Coral | SSD MobileNet (Edge TPU) | 30-60 | 16-33 | Requires INT8 model |

## Quick Reference: Common Bottlenecks

| Symptom | Likely Bottleneck | Diagnostic | Fix |
|---------|-------------------|------------|-----|
| Low FPS, high inference time | Model too large | Profile infer stage | Quantize, reduce resolution, smaller model |
| FPS drops after 5 min | Thermal throttling | Monitor temperature | Add cooling, reduce clock, skip frames |
| High capture latency | Camera buffer stall | Profile capture stage | Use threaded capture, reduce resolution |
| Memory grows over time | Frame buffer leak | Monitor RSS over time | Check queue bounds, release frames |
| Inconsistent frame times | GC pauses or contention | Check jitter/std | Pre-allocate arrays, pin memory |
