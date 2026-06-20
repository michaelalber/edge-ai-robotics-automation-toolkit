---
name: jetson-deploy
audience: professional
description: >
  Deploy and optimize applications on Jetson Orin Nano with TensorRT. Use when
  setting up Jetson environments, converting models to TensorRT, managing power
  modes, and containerizing edge AI applications. Do NOT use when the target hardware
  is not a Jetson device; Do NOT use when deploying to Raspberry Pi — use
  edge-cv-pipeline and sensor-integration instead.
---

# Jetson Orin Nano Deployment & TensorRT Optimization

> "The future of AI is at the edge. Every robot, every camera, every sensor will have AI processing locally."
> — Dustin Franklin, NVIDIA Jetson AI Developer

## Core Philosophy

This skill orchestrates the full lifecycle of deploying AI applications to NVIDIA Jetson Orin Nano devices. Every decision is constrained by **thermal limits, power budgets, and memory ceilings** that do not exist in cloud or desktop environments.

**Non-Negotiable Constraints:**
1. **Power budget is law** — The Orin Nano runs at 7W, 15W, or MAXN. Every model, every pipeline, every container must fit within the active power envelope. Ignoring this causes thermal throttling, silent performance degradation, or hardware shutdown.
2. **TensorRT for production inference** — Raw PyTorch or ONNX Runtime is acceptable for prototyping. Production inference MUST use TensorRT-optimized engines. The performance gap is 2-10x; skipping this step is not optional.
3. **Profile on the actual device** — Desktop GPU benchmarks are meaningless. A model that runs at 60 FPS on an RTX 4090 may run at 3 FPS on an Orin Nano. Always benchmark on target hardware.
4. **JetPack version determines everything** — CUDA version, TensorRT version, cuDNN version, and supported container base images all flow from the JetPack release. Verify JetPack version before any other step.
5. **Containers are mandatory for reproducibility** — Use `jetson-containers` from dustynv to build reproducible deployment environments. Bare-metal installs create fragile, unreproducible setups.

## Domain Principles Table

| Principle | Description | Priority |
|-----------|-------------|----------|
| **Power Mode Awareness** | Select and validate power mode before benchmarking or deploying; results are meaningless without a fixed power profile | Critical |
| **TensorRT First** | Convert all inference models to TensorRT engines before deployment; never ship raw ONNX or PyTorch models to production | Critical |
| **JetPack Compatibility** | Verify JetPack version, L4T version, and CUDA version before installing any package or building any container | Critical |
| **Container Reproducibility** | Use jetson-containers for all deployments; pin base images to specific L4T versions; never rely on bare-metal installs | High |
| **Thermal Management** | Profile thermal behavior under sustained load; set power mode and fan policy before benchmarking; monitor with tegrastats | High |
| **Memory Budget Discipline** | The Orin Nano has 8GB unified memory shared between CPU and GPU; account for OS overhead (~1.5GB), display server, and framework footprint | High |
| **On-Device Validation** | Never trust desktop or cloud benchmarks; always validate latency, throughput, and accuracy on the target Jetson device | High |
| **Precision-Accuracy Tradeoff** | FP16 is the default for Orin Nano; INT8 requires calibration data and accuracy validation; never assume precision reduction is lossless | Medium |
| **Incremental Deployment** | Deploy one component at a time; validate each stage before adding the next pipeline element | Medium |
| **Telemetry from Day One** | Instrument with tegrastats and jtop from the first deployment; do not wait for production to add monitoring | Medium |

## Knowledge Base Lookups

| Query | When to Call |
|-------|--------------|
| `search_knowledge("TensorRT FP16 INT8 quantization Jetson")` | During CONVERT/OPTIMIZE — selecting precision and quantization strategy |
| `search_knowledge("Jetson JetPack CUDA cuDNN compatibility")` | During SETUP — verifying version compatibility before any installation |
| `search_knowledge("Docker container NVIDIA GPU runtime")` | During CONTAINERIZE — configuring nvidia-docker runtime |
| `search_knowledge("TensorRT ONNX model conversion trtexec")` | During CONVERT — converting ONNX models to TensorRT engines |
| `search_knowledge("Jetson power mode thermal monitoring tegrastats")` | During BENCHMARK — measuring thermal behavior and power draw |
| `search_code_examples("TensorRT Python inference engine")` | Before writing inference code — find TensorRT Python API patterns |
| `search_code_examples("Docker Compose systemd service autostart")` | During DEPLOY — configuring auto-start and restart policies |

Search `edge_ai` and `robotics` collections for Jetson and TensorRT guidance. Search `automation` for containerization and fleet deployment context.

## Workflow

The deployment lifecycle flows: **SETUP → CONTAINERIZE → CONVERT → OPTIMIZE → BENCHMARK → DEPLOY**. Iterate between OPTIMIZE and BENCHMARK until performance targets and thermal stability are met.

### Pre-Flight Checklist

Verify before beginning any deployment step:

- [ ] JetPack version confirmed (`cat /etc/nv_tegra_release`)
- [ ] L4T version matches expected (`dpkg -l nvidia-l4t-core`)
- [ ] CUDA version confirmed (`nvcc --version`)
- [ ] TensorRT version confirmed (`dpkg -l tensorrt`)
- [ ] Available disk space > 10GB (`df -h`)
- [ ] Docker runtime is nvidia (`docker info | grep -i runtime`)
- [ ] Power mode is set (`sudo nvpmodel -q`)
- [ ] Fan mode is set (`sudo jetson_clocks --show`)
- [ ] Network access for container pulls (if needed)
- [ ] Model files are accessible on device

If ANY item is unchecked — STOP. Resolve before proceeding.

### Step 1: SETUP

Confirm the Jetson device is properly configured for deployment.

1. `cat /etc/nv_tegra_release` — confirm L4T version
2. `sudo nvpmodel -q` — check current power mode
3. `sudo nvpmodel -m <MODE>` — set target power mode (0=MAXN, 1=15W, 2=7W for Orin Nano)
4. `sudo jetson_clocks` — lock clock frequencies for consistent benchmarking
5. `sudo pip3 install jetson-stats` — install jtop
6. `docker run --rm --runtime nvidia --gpus all nvidia/cuda:12.2.0-base-ubuntu22.04 nvidia-smi` — verify Docker nvidia runtime

**Exit Criteria:** JetPack version documented, power mode confirmed, Docker nvidia runtime functional, jtop installed and running.

### Step 2: CONTAINERIZE

Build a reproducible container environment using jetson-containers.

1. `git clone https://github.com/dusty-nv/jetson-containers`
2. Select the appropriate base image for the JetPack version
3. Define container requirements (TensorRT, OpenCV, model framework)
4. Build using `jetson-containers build` or `docker build`
5. `python3 -c "import tensorrt; print(tensorrt.__version__)"` — verify GPU access inside container
6. Mount model directory and data directory as volumes

**Exit Criteria:** Container runs with `--runtime nvidia`, GPU accessible inside container, model files accessible via volume mount.

### Step 3: CONVERT

Convert model from training format to TensorRT engine.

1. Export model to ONNX format (if not already)
2. `python3 -c "import onnx; model = onnx.load('model.onnx'); onnx.checker.check_model(model)"` — validate ONNX
3. Convert ONNX to TensorRT using `trtexec` or Python API; specify FP16 precision (default for Orin Nano)
4. Handle dynamic shapes if needed
5. Verify engine loads and produces output on sample input

**Exit Criteria:** `.engine` or `.trt` file created, loads without errors, output shape matches expected dimensions.

### Step 4: OPTIMIZE

Tune the TensorRT engine and pipeline for target performance.

1. `trtexec --loadEngine=model.engine --iterations=100 --avgRuns=50` — profile baseline
2. Try INT8 quantization if FP16 does not meet latency target (requires calibration data and accuracy validation)
3. Experiment with workspace size: `--memPoolSize=workspace:1024MiB`
4. Optimize input preprocessing with GPU-accelerated resize and normalize
5. Add CUDA streams for async execution if the pipeline allows

**Exit Criteria:** Latency meets target at specified power mode, memory leaves headroom for OS and other processes, no thermal throttling under sustained load.

### Step 5: BENCHMARK

Produce reliable, reproducible performance measurements.

1. `sudo nvpmodel -m <MODE>` — set power mode explicitly
2. `sudo jetson_clocks` — lock clocks
3. Run 50+ warm-up iterations before measuring
4. Record latency (mean, P50, P95, P99) across 1000+ iterations
5. `tegrastats --interval 1000` — monitor GPU utilization, memory usage, temperature, power draw during benchmark
6. Validate accuracy against reference outputs

**Exit Criteria:** Benchmark results documented with power mode and clock state, latency distribution captured (not just mean), no throttling during measurement, accuracy validated against golden reference.

### Step 6: DEPLOY

Finalize the deployment for production operation.

1. Create Docker Compose or systemd service for auto-start
2. Configure restart policies for resilience
3. Set up logging and monitoring (tegrastats, jtop, application logs)
4. Configure watchdog for thermal protection
5. Validate end-to-end pipeline with production data
6. Document the deployment configuration

**Exit Criteria:** Application starts automatically on boot, restart policy handles crashes gracefully, monitoring active, end-to-end pipeline validated with real data.

## State Block

```
<jetson-deploy-state>
step: [SETUP | CONTAINERIZE | CONVERT | OPTIMIZE | BENCHMARK | DEPLOY]
jetpack_version: [e.g., "6.0", "5.1.2"]
power_mode: [MAXN | 15W | 7W]
inference_engine: [tensorrt | onnxruntime | tflite]
last_action: [what was just done]
next_action: [what should happen next]
blockers: [any issues]
</jetson-deploy-state>
```

**Example:** `step: CONVERT | jetpack_version: 6.0 | power_mode: 15W | last_action: Exported YOLOv8n to ONNX | next_action: Convert ONNX to TensorRT FP16 engine | blockers: none`

## Output Templates

```markdown
## Jetson Deployment Report: [Model Name]
**Device**: Jetson Orin Nano 8GB | **JetPack**: [N] | **Power Mode**: [mode]
**Precision**: [FP16/INT8] | **Mean Latency**: [ms] | **Throughput**: [fps]
**GPU Util**: [%] | **Memory**: [MB/8192 MB] | **Peak Temp**: [C] | **Power**: [W]
**Benchmark**: P50=[ms] P95=[ms] P99=[ms] over N=[iterations] | Accuracy: [mAP/acc]
**FP32 vs FP16 vs INT8**: [latency and accuracy comparison]
```

Full templates (Deployment Report, Benchmark Results with latency distribution and precision comparison): `references/edge-profiling.md`

## AI Discipline Rules

**Always verify JetPack version before any installation, container build, or model conversion.** Run `cat /etc/nv_tegra_release` and document the L4T version before proceeding. Mixing packages from different JetPack versions corrupts the system — there is no recovery short of reflashing the device.

**Never deploy raw ONNX or PyTorch models to production.** TensorRT engines deliver 2–10x better performance on Jetson. TensorRT engines are architecture-specific: an engine built on x86 will NOT run on ARM, and an engine built on one JetPack version may not run on another. Always build engines on the target Jetson device itself.

**Profile thermal behavior for at least 5 minutes of sustained load before declaring production-ready.** The Orin Nano thermal-throttles at approximately 85–90°C. Passive cooling is insufficient for sustained MAXN workloads. If temperatures exceed 80°C during benchmarking, adjust power mode, add cooling, or reduce model complexity.

**All production deployments must run inside containers with pinned L4T base images.** Never pip install on the Jetson host system — this creates version conflicts with JetPack system packages that break CUDA and TensorRT. Use `jetson-containers build` which handles JetPack compatibility automatically.

## Common Anti-Patterns to Avoid

| Anti-Pattern | Why It's Wrong | Correct Approach |
|--------------|----------------|------------------|
| Benchmarking on desktop GPU | Results are meaningless for edge deployment; different architecture, memory, and power | Always benchmark on the target Jetson device |
| Skipping TensorRT conversion | 2-10x performance left on the table; latency targets will not be met | Convert all production models to TensorRT engines |
| Building engine on x86 | TensorRT engines are architecture-specific; x86 engines do not run on ARM | Build engines on the Jetson device itself |
| Ignoring power mode during benchmark | Results are not reproducible; different runs use different power profiles | Set power mode explicitly before every benchmark |
| Installing pip packages bare-metal | Creates version conflicts with JetPack system packages; breaks CUDA/TensorRT | Use containers; never pip install on the host system |
| Using FP32 without trying FP16 | Orin Nano has dedicated FP16 tensor cores; FP32 wastes half the compute capability | Default to FP16; only use FP32 if accuracy requires it |
| Deploying without thermal profiling | Device throttles or shuts down under sustained load in production | Run sustained load test with tegrastats for 10+ minutes |
| Hardcoding paths in containers | Breaks when deploying to different devices or updating models | Use volume mounts for models, data, and configuration |

## Error Recovery

**CUDA version mismatch** ("no kernel image is available" or "CUDA driver version insufficient"): Check JetPack version (`cat /etc/nv_tegra_release`) and CUDA version (`nvcc --version`). Reinstall the mismatched package for your specific JetPack/CUDA version. If using a container, verify the base image L4T tag matches the device. Migrate to containers if running bare-metal.

**Out of memory on model load** ("CUDA out of memory"): Check usage with `free -h` and `tegrastats`. Kill unnecessary processes (desktop environment uses ~800MB). Reduce TensorRT workspace: `--memPoolSize=workspace:512MiB`. Switch FP32→FP16 to halve weight memory. Reduce batch size to 1. Consider `sudo systemctl set-default multi-user.target` to disable the GUI (~800MB freed).

**Thermal throttling** (performance degrades after minutes, temperature >80°C): Lower power mode (`sudo nvpmodel -m 1`), add active cooling, or reduce model complexity. Poll tegrastats inside the application and throttle workload before the hardware does it for you. Re-benchmark at the sustainable power mode.

**Container build failures** (package conflicts or missing dependencies): Verify device JetPack version and confirm the Dockerfile FROM line uses the matching L4T tag (JetPack 6.x → L4T r36.x, JetPack 5.x → L4T r35.x). Use `jetson-containers build` which handles compatibility automatically. Pin all package versions explicitly in custom Dockerfiles.

**TensorRT engine build failures** ("Unsupported ONNX opset" or "Layer not supported"): Check TensorRT version (`dpkg -l tensorrt`) and ONNX opset (`python3 -c "import onnx; print(onnx.load('model.onnx').opset_import)"`). Try `python3 -m onnxsim model.onnx model_simplified.onnx`. Use ONNX-GraphSurgeon to replace unsupported operations. Try an older opset when exporting from PyTorch.

## Integration with Other Skills

- **edge-cv-pipeline** — After deploying a TensorRT engine, use `edge-cv-pipeline` to build the complete vision pipeline (camera capture, preprocessing, inference, postprocessing, output). Jetson deployment handles infrastructure; CV pipeline handles application logic.
- **sensor-integration** — When the Jetson deployment includes sensor inputs (GPIO, I2C, SPI, USB cameras, LiDAR), use `sensor-integration` for device configuration and data acquisition. Mount device files (`/dev/video0`, `/dev/i2c-*`, `/dev/spidev*`) into containers as needed.
- **picar-x-behavior** — When deploying to a PiCar-X robot platform with a Jetson compute module, the Jetson handles vision inference; PiCar-X behavior handles actuation and navigation.
