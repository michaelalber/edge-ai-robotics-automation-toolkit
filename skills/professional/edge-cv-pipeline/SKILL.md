---
name: edge-cv-pipeline
audience: professional
description: >
  Build OpenCV + TFLite computer vision pipelines for Jetson and Raspberry Pi.
  Use when deploying real-time inference on edge devices with camera capture, model
  optimization, and result publishing. Do NOT use when the inference pipeline runs
  on cloud infrastructure; Do NOT use when the target hardware is a general-purpose
  server rather than an edge device.
---

# Edge CV Pipeline Builder

> "In computer vision, the best algorithm is useless if it can't run in real-time on the hardware you have."
> -- Pete Warden, TinyML

## Core Philosophy

This skill builds end-to-end computer vision pipelines for edge devices. The pipeline spans camera capture, preprocessing, inference, postprocessing, and result publishing. **Every decision is constrained by the target hardware.**

**Non-Negotiable Constraints:**
1. **Profile before optimizing** -- measure actual latency on the target device before changing anything.
2. **Match resolution to model input** -- never capture at 1080p when the model expects 320x320.
3. **Handle frame drops gracefully** -- edge devices will drop frames under load; the pipeline must degrade without crashing.
4. **Separate capture from inference** -- camera I/O and model inference run at different rates; decouple them with a queue.
5. **Test on the target device** -- x86 profiling numbers are meaningless for ARM/GPU inference.

## Domain Principles Table

| Principle | Description | Priority |
|-----------|-------------|----------|
| **Latency Budget** | Allocate a per-stage ms budget (capture, preprocess, infer, postprocess, publish) and enforce it | Critical |
| **Resolution Matching** | Capture resolution matches model input dimensions; resize only when unavoidable | Critical |
| **Model Size Awareness** | Track model file size, RAM footprint, and inference time as first-class constraints | Critical |
| **Frame Pipeline Isolation** | Capture, inference, and publish threads operate independently with bounded queues | High |
| **Thermal Headroom** | Design for 80% of peak throughput; sustained workloads throttle on edge devices | High |
| **Graceful Degradation** | Skip frames, reduce resolution, or switch models rather than crash or hang | High |
| **Format Portability** | Prefer ONNX as interchange; convert to device-specific formats at deploy time | Medium |
| **Reproducible Capture** | Lock exposure, white balance, and gain for consistent inference inputs across runs | Medium |
| **Observable Pipeline** | Expose FPS, latency, temperature, and memory metrics at all times | Medium |
| **Power Efficiency** | Minimize unnecessary wakeups; sleep between inference cycles for battery deployments | Low |

## Knowledge Base Lookups

| Query | When to Call |
|-------|--------------|
| `search_knowledge("OpenCV camera capture threading queue")` | During CAPTURE — building thread-safe frame capture loops |
| `search_knowledge("TFLite inference Raspberry Pi XNNPACK delegate")` | During INFER — configuring TFLite delegates on ARM hardware |
| `search_knowledge("image preprocessing normalization resize")` | During PREPROCESS — correct normalization for the model |
| `search_knowledge("MQTT publish subscribe IoT Python")` | During PUBLISH — setting up result publishing |
| `search_knowledge("edge inference latency profiling benchmarking")` | During any stage — profiling and optimizing pipeline latency |
| `search_code_examples("TFLite interpreter Python inference")` | Before writing inference code |
| `search_code_examples("OpenCV VideoCapture threading Python")` | Before writing capture code |

Search `edge_ai` and `robotics` collections for CV pipeline patterns; `python` for threading and async.

## Workflow

The pipeline flows linearly: **CAPTURE → PREPROCESS → INFER → POSTPROCESS → PUBLISH**, with each stage running in its own thread connected by bounded queues.

### Pre-Flight Checklist

- [ ] Target device identified (Jetson Orin Nano / RPi 5 / RPi 4)
- [ ] Camera module confirmed (CSI / USB / IP stream)
- [ ] Model format selected (TFLite / ONNX / TensorRT)
- [ ] Model input dimensions known (e.g., 320x320x3)
- [ ] FPS target defined (e.g., 15 fps for detection)
- [ ] Output destination defined (MQTT / HTTP / file / display)
- [ ] Power source confirmed (wall / battery / PoE)

### Model Format by Device

| Device | Recommended Format |
|--------|--------------------|
| Jetson (INT8 needed) | TensorRT via `trtexec` or `torch2trt` |
| Jetson (FP16 default) | TensorRT FP16 |
| RPi + Coral TPU | TFLite + Edge TPU delegate |
| RPi (no TPU) | TFLite + XNNPACK delegate (ARM NEON) |
| Intel device | OpenVINO IR |
| Other / portable | ONNX Runtime |

### Step-by-Step Workflow

**Step 1: CAPTURE** — Acquire frames from the camera in a dedicated thread with a bounded queue.

```python
import cv2
from threading import Thread
from queue import Queue

class FrameCapture:
    def __init__(self, source, queue_size=2):
        self.cap = cv2.VideoCapture(source)
        self.queue = Queue(maxsize=queue_size)
        self.stopped = False

    def start(self):
        Thread(target=self._reader, daemon=True).start()
        return self

    def _reader(self):
        while not self.stopped:
            ret, frame = self.cap.read()
            if not ret:
                self.stopped = True
                break
            if not self.queue.full():
                self.queue.put(frame)
            # Drop frame if queue is full (graceful degradation)

    def read(self):
        return self.queue.get(timeout=5.0)

    def stop(self):
        self.stopped = True
        self.cap.release()
```

**Step 2: PREPROCESS** — Resize, normalize, format for model input.

```python
import numpy as np

def preprocess_frame(frame, input_size=(320, 320), normalize=True):
    resized = cv2.resize(frame, input_size, interpolation=cv2.INTER_LINEAR)
    if normalize:
        input_data = resized.astype(np.float32) / 255.0
    else:
        input_data = resized.astype(np.uint8)
    return np.expand_dims(input_data, axis=0)
```

**Step 3: INFER** — Run the model on the preprocessed frame.

```python
import tflite_runtime.interpreter as tflite

def load_tflite_model(model_path, num_threads=4):
    interpreter = tflite.Interpreter(model_path=model_path, num_threads=num_threads)
    interpreter.allocate_tensors()
    return interpreter

def infer(interpreter, input_data):
    input_details = interpreter.get_input_details()
    output_details = interpreter.get_output_details()
    interpreter.set_tensor(input_details[0]['index'], input_data)
    interpreter.invoke()
    return [interpreter.get_tensor(d['index']) for d in output_details]
```

**Step 4: POSTPROCESS** — Parse detections, apply NMS, threshold.

```python
def postprocess_detections(outputs, confidence_threshold=0.5,
                           input_size=(320, 320), original_size=(640, 480)):
    boxes, classes, scores = outputs[0][0], outputs[1][0], outputs[2][0]
    detections = []
    scale_x = original_size[0] / input_size[0]
    scale_y = original_size[1] / input_size[1]
    for i, score in enumerate(scores):
        if score < confidence_threshold:
            continue
        ymin, xmin, ymax, xmax = boxes[i]
        detections.append({
            "class_id": int(classes[i]),
            "confidence": float(score),
            "bbox": [int(xmin * input_size[0] * scale_x), int(ymin * input_size[1] * scale_y),
                     int(xmax * input_size[0] * scale_x), int(ymax * input_size[1] * scale_y)],
        })
    return detections
```

**Step 5: PUBLISH** — Send results to MQTT, HTTP, or display.

```python
import json, paho.mqtt.client as mqtt

class MQTTPublisher:
    def __init__(self, broker="localhost", port=1883, topic="cv/detections"):
        self.client = mqtt.Client()
        self.client.connect(broker, port)
        self.topic = topic
        self.client.loop_start()

    def publish(self, detections, frame_id=None):
        self.client.publish(self.topic, json.dumps({"frame_id": frame_id, "detections": detections}))

    def stop(self):
        self.client.loop_stop()
        self.client.disconnect()
```

## State Block

```
<edge-cv-state>
step: [CAPTURE | PREPROCESS | INFER | POSTPROCESS | PUBLISH]
target_device: [jetson-orin-nano | raspberry-pi-5 | raspberry-pi-4]
model_format: [tflite | onnx | tensorrt | openvino]
fps_target: [number]
latency_ms: [number or "unmeasured"]
last_action: [what was just done]
next_action: [what should happen next]
blockers: [any issues]
</edge-cv-state>
```

**Example:**

```
<edge-cv-state>
step: INFER
target_device: raspberry-pi-5
model_format: tflite
fps_target: 15
latency_ms: 45
last_action: Converted MobileNetV2 to TFLite with float16 quantization
next_action: Profile inference latency on RPi 5 with XNNPACK delegate
blockers: none
</edge-cv-state>
```

## Output Templates

```markdown
## Edge CV Pipeline: [Project Name]
**Device**: [device] | **Camera**: [type] at [resolution] @ [fps]
**Model**: [name] ([format], [size] MB, [width]x[height]x[channels])
**Publish**: [MQTT / HTTP / file / display]

| Stage | Budget (ms) | Measured (ms) | Status |
|-------|-------------|---------------|--------|
| Capture / Preprocess / Infer / Postprocess / Publish / Total | [n] | [n] | ok/over |
```

Full scaffold, profiling, and recommendation report templates: `references/edge-profiling.md`.

## AI Discipline Rules

**Always profile on target hardware.** x86/x64 development machine numbers are for debugging only. Profile with `time.perf_counter_ns()` per stage on the actual Jetson or RPi. Report P95 latency, not just mean — edge devices have variance from thermal throttling. Never claim a latency number without measuring it on the target.

**Never skip preprocessing validation.** Before running inference, assert that `input_data.shape` and `input_data.dtype` match `interpreter.get_input_details()`. Skipping this leads to silent wrong results — garbage detections that look plausible — or hard-to-debug segfaults in native inference backends.

**Handle camera disconnection gracefully.** Edge deployments lose camera connections due to loose CSI ribbons, USB power issues, or thermal shutdowns. Wrap `cap.read()` in a retry loop with exponential backoff. After `max_retries` failures, raise an exception and log the loss — do not silently drop to zero detections.

**Match capture resolution to model input.** Capturing at 1080p and resizing to 320x320 wastes 10x the pixels on a resize operation. Set `cap.set(cv2.CAP_PROP_FRAME_WIDTH, 320)` at initialization. The exception: when full-resolution frames are needed for annotation or multiple model scales — document the resize cost in the latency budget.

## Anti-Patterns Table

| Anti-Pattern | Why It Fails on Edge | Correct Approach |
|--------------|----------------------|------------------|
| Capturing at 1080p for a 320x320 model | Wastes 10x pixels in resize; burns CPU/memory | Set capture resolution to model input or nearest supported |
| Running inference on the main thread | Blocks frame capture, causes dropped frames | Separate capture and inference with threaded pipeline and queue |
| Loading model inside the frame loop | Model load takes 200ms–2s; kills FPS | Load model once at startup, reuse interpreter across frames |
| Using `cv2.imshow()` in headless deploy | X11 over SSH adds latency; crashes without display | Publish via MQTT/HTTP; use `imshow` only for local debugging |
| Ignoring thermal throttling | Jetson/RPi throttle at 80–85°C; FPS drops 30–50% | Profile under sustained load for 5+ minutes; design for throttled throughput |
| Hardcoding camera index `0` | Multi-camera setups or USB re-enumeration changes indices | Use device path (`/dev/video0`) or GStreamer pipeline string |
| No frame drop policy | Queue fills, memory exhausts, OOM kill | Use bounded queue with drop-oldest policy |
| Float32 model on RPi without delegate | RPi CPU is slow at float32; inference takes 500ms+ | Quantize to INT8 or use float16 with XNNPACK delegate |

## Error Recovery

**Camera fails to open**: Verify hardware connection. Check `/dev/video*` exists. For Jetson CSI, test `gst-launch-1.0 nvarguscamerasrc ! fakesink`. For RPi CSI, test `libcamera-hello --list-cameras`. Check permissions (`sudo usermod -aG video $USER`). Reboot if hot-plugged on CSI.

**Inference returns garbage**: Verify preprocessing matches training pipeline exactly (RGB vs BGR, normalize range 0–1 vs 0–255). Assert input tensor shape and dtype. Verify model file checksum. Print raw output tensor values before postprocessing. Check whether quantized model expects different input scaling.

**FPS below target**: Profile each stage to find the bottleneck. If capture is slow, reduce resolution or optimize GStreamer pipeline. If inference is slow, quantize the model, reduce input size, or enable the hardware delegate. If all stages are slow, the model is too large for this device.

**Out of memory**: Reduce frame queue `maxsize` to 1–2. Verify the model is not loaded multiple times. Use `uint8` instead of `float32` where possible. Reduce capture resolution. Monitor with `watch -n 1 free -m`. For Jetson, check `tegrastats` for GPU memory. For RPi, adjust GPU memory split in `/boot/config.txt`.

**Thermal throttling**: Monitor with `cat /sys/class/thermal/thermal_zone*/temp`. Add heatsink and fan. Reduce inference frequency (process every Nth frame). For Jetson, check `sudo jetson_clocks --show`. For RPi, check `vcgencmd measure_temp`.

## Integration with Other Skills

- **`jetson-deploy`** -- Containerize the CV pipeline with NVIDIA L4T base images, configure JetPack dependencies, and deploy with `jetson-containers` or Docker Compose. The pipeline code from this skill becomes the application layer inside the Jetson container.
- **`sensor-integration`** -- When the CV pipeline fuses camera data with other sensors (IMU, LIDAR, ultrasonic), use `sensor-integration` for multi-sensor synchronization via shared MQTT topics.
- **`picar-x-behavior`** -- For PiCar-X robotics projects, this skill provides the vision layer. The CV pipeline publishes detections that `picar-x-behavior` consumes for driving decisions.

Reference files: [Model Conversion](references/model-conversion.md) | [Capture and Publish Patterns](references/capture-publish-patterns.md) | [Edge Profiling](references/edge-profiling.md)
