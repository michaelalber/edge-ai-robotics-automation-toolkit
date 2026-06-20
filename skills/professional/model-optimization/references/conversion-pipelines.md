# Model Conversion Pipelines

## Overview

Edge deployment requires converting models from training frameworks into optimized inference formats. This reference covers every major conversion pipeline, with emphasis on the three most common paths: PyTorch to TensorRT (Jetson), TensorFlow to TFLite (Raspberry Pi), and PyTorch to ONNX (portable).

**Conversion Map:**

```
                    +------------+
                    |  PyTorch   |
                    +-----+------+
                          | torch.onnx.export()
                          v
+------------+      +------------+      +------------+
| TensorFlow |----->|    ONNX    |<-----| Keras/JAX  |
+-----+------+      +-----+------+      +------------+
      |                    |
      | tf.lite            | trtexec / onnx2tf / ort
      | converter          |
      v                    v
+------------+      +------------+      +------------+
|   TFLite   |      | TensorRT   |      |  OpenVINO  |
| (RPi/CPU)  |      | (Jetson)   |      | (Intel)    |
+------------+      +------------+      +------------+
```

---

## Pipeline 1: PyTorch to ONNX to TensorRT (Jetson)

This is the primary conversion path for deploying PyTorch models on NVIDIA Jetson devices.

### Step 1: Export PyTorch to ONNX

```python
import torch
import torchvision.models as models

# Load trained model and switch to inference mode
model = models.mobilenet_v2(weights=models.MobileNet_V2_Weights.DEFAULT)
model.train(False)  # Switch to inference mode

# Create dummy input matching expected inference input
dummy_input = torch.randn(1, 3, 224, 224)

# Export to ONNX
torch.onnx.export(
    model,
    dummy_input,
    "mobilenetv2.onnx",
    opset_version=17,                     # Use highest supported opset
    input_names=["input"],
    output_names=["output"],
    dynamic_axes={                         # Optional: enable dynamic batch
        "input": {0: "batch_size"},
        "output": {0: "batch_size"},
    },
)

print("Exported to mobilenetv2.onnx")
```

**Export tips:**
- Use `opset_version=17` or the highest supported by your TensorRT version
- Set `dynamic_axes` only if you need variable batch sizes at runtime
- For static shapes (recommended for edge), omit `dynamic_axes` entirely
- Always switch the model to inference mode before export to disable dropout and batch norm training behavior

### Step 2: Validate and Simplify ONNX

```python
import onnx
from onnxsim import simplify

# Validate structure
model = onnx.load("mobilenetv2.onnx")
onnx.checker.check_model(model)
print("ONNX model is structurally valid")

# Simplify (fuses ops, removes redundant nodes, constant-folds)
model_simplified, check = simplify(model)
assert check, "Simplified model failed validation"

onnx.save(model_simplified, "mobilenetv2_simplified.onnx")
print("Simplified model saved")
```

**Always simplify before TensorRT conversion.** Simplification:
- Fuses constant expressions
- Removes identity operations
- Merges consecutive reshapes
- Typically reduces conversion failures by 30-50%

### Step 3: Validate ONNX Output Correctness

```python
import onnxruntime as ort
import numpy as np
import torch

# Load original PyTorch model
pytorch_model = models.mobilenet_v2(weights=models.MobileNet_V2_Weights.DEFAULT)
pytorch_model.train(False)  # Inference mode

# Load ONNX model
ort_session = ort.InferenceSession("mobilenetv2_simplified.onnx")

# Create test input
test_input = np.random.randn(1, 3, 224, 224).astype(np.float32)

# Run both models
with torch.no_grad():
    pytorch_output = pytorch_model(torch.from_numpy(test_input)).numpy()

onnx_output = ort_session.run(None, {"input": test_input})[0]

# Compare outputs
max_diff = np.max(np.abs(pytorch_output - onnx_output))
print(f"Maximum output difference: {max_diff:.8f}")
assert max_diff < 1e-5, f"Output mismatch: {max_diff}"
print("ONNX output matches PyTorch output")
```

### Step 4: Convert ONNX to TensorRT Engine

**Using trtexec (recommended for initial conversion):**

```bash
# FP16 conversion (default for Jetson)
trtexec \
    --onnx=mobilenetv2_simplified.onnx \
    --saveEngine=mobilenetv2_fp16.engine \
    --fp16 \
    --memPoolSize=workspace:2048MiB \
    --verbose

# INT8 conversion (requires calibration cache)
trtexec \
    --onnx=mobilenetv2_simplified.onnx \
    --saveEngine=mobilenetv2_int8.engine \
    --int8 \
    --fp16 \
    --calib=calibration.cache \
    --memPoolSize=workspace:2048MiB

# Verify the engine
trtexec \
    --loadEngine=mobilenetv2_fp16.engine \
    --iterations=100 \
    --warmUp=5000
```

**Using Python TensorRT API:**

```python
import tensorrt as trt

def build_engine(onnx_path, engine_path, fp16=True, int8=False,
                 workspace_mb=2048, calibrator=None):
    """Build a TensorRT engine from an ONNX model."""
    logger = trt.Logger(trt.Logger.INFO)
    builder = trt.Builder(logger)
    network_flags = 1 << int(trt.NetworkDefinitionCreationFlag.EXPLICIT_BATCH)
    network = builder.create_network(network_flags)

    parser = trt.OnnxParser(network, logger)
    with open(onnx_path, "rb") as f:
        if not parser.parse(f.read()):
            for i in range(parser.num_errors):
                print(f"Parse error: {parser.get_error(i)}")
            return False

    config = builder.create_builder_config()
    config.set_memory_pool_limit(
        trt.MemoryPoolType.WORKSPACE,
        workspace_mb * (1 << 20)
    )

    if fp16 and builder.platform_has_fast_fp16:
        config.set_flag(trt.BuilderFlag.FP16)

    if int8 and builder.platform_has_fast_int8:
        config.set_flag(trt.BuilderFlag.INT8)
        if calibrator:
            config.int8_calibrator = calibrator

    print("Building TensorRT engine...")
    serialized = builder.build_serialized_network(network, config)
    if serialized is None:
        print("ERROR: Engine build failed")
        return False

    with open(engine_path, "wb") as f:
        f.write(serialized)

    print(f"Engine saved to {engine_path}")
    return True
```

**Critical**: TensorRT engines are architecture-specific. An engine built on x86 will NOT run on ARM. Always build on the target device.

---

## Pipeline 2: TensorFlow/Keras to TFLite (Raspberry Pi)

This is the primary conversion path for deploying TensorFlow or Keras models on Raspberry Pi and other ARM CPU devices.

### From Keras Model

```python
import tensorflow as tf

model = tf.keras.applications.MobileNetV2(
    input_shape=(224, 224, 3),
    weights="imagenet",
    include_top=True
)

# Basic conversion (float32)
converter = tf.lite.TFLiteConverter.from_keras_model(model)
tflite_model = converter.convert()

with open("mobilenetv2_float32.tflite", "wb") as f:
    f.write(tflite_model)

print(f"Float32 model: {len(tflite_model) / 1024 / 1024:.1f} MB")
```

### From SavedModel Directory

```python
import tensorflow as tf

# Convert from SavedModel directory
converter = tf.lite.TFLiteConverter.from_saved_model("/path/to/saved_model")
converter.optimizations = [tf.lite.Optimize.DEFAULT]
converter.target_spec.supported_types = [tf.float16]

tflite_model = converter.convert()
with open("model_float16.tflite", "wb") as f:
    f.write(tflite_model)
```

### With Float16 Quantization

```python
import tensorflow as tf

model = tf.keras.applications.MobileNetV2(
    input_shape=(224, 224, 3),
    weights="imagenet"
)

converter = tf.lite.TFLiteConverter.from_keras_model(model)
converter.optimizations = [tf.lite.Optimize.DEFAULT]
converter.target_spec.supported_types = [tf.float16]

tflite_model = converter.convert()
with open("mobilenetv2_fp16.tflite", "wb") as f:
    f.write(tflite_model)

print(f"Float16 model: {len(tflite_model) / 1024 / 1024:.1f} MB")
# Expect ~7 MB vs ~14 MB for float32
```

### With Full INT8 Quantization

```python
import tensorflow as tf
import numpy as np

model = tf.keras.applications.MobileNetV2(
    input_shape=(224, 224, 3),
    weights="imagenet"
)

def representative_dataset():
    """Yield calibration samples. Use real data, not random noise."""
    for _ in range(300):
        # Replace with actual calibration images
        sample = np.random.rand(1, 224, 224, 3).astype(np.float32)
        yield [sample]

converter = tf.lite.TFLiteConverter.from_keras_model(model)
converter.optimizations = [tf.lite.Optimize.DEFAULT]
converter.representative_dataset = representative_dataset
converter.target_spec.supported_ops = [tf.lite.OpsSet.TFLITE_BUILTINS_INT8]
converter.inference_input_type = tf.uint8
converter.inference_output_type = tf.uint8

tflite_model = converter.convert()
with open("mobilenetv2_int8.tflite", "wb") as f:
    f.write(tflite_model)

print(f"INT8 model: {len(tflite_model) / 1024 / 1024:.1f} MB")
# Expect ~3.5 MB
```

### TFLite Inference Verification

```python
import numpy as np
import tflite_runtime.interpreter as tflite

def verify_tflite_model(model_path, test_input):
    """Load and run a TFLite model to verify it works."""
    interpreter = tflite.Interpreter(model_path=model_path, num_threads=4)
    interpreter.allocate_tensors()

    input_details = interpreter.get_input_details()[0]
    output_details = interpreter.get_output_details()[0]

    print(f"Input: shape={input_details['shape']}, dtype={input_details['dtype']}")
    print(f"Output: shape={output_details['shape']}, dtype={output_details['dtype']}")

    # Match input dtype
    if input_details['dtype'] == np.uint8:
        input_data = (test_input * 255).astype(np.uint8)
    else:
        input_data = test_input.astype(np.float32)

    interpreter.set_tensor(input_details['index'], input_data)
    interpreter.invoke()

    output = interpreter.get_tensor(output_details['index'])
    print(f"Output range: [{output.min():.4f}, {output.max():.4f}]")
    return output
```

---

## Pipeline 3: PyTorch to ONNX to TFLite (via onnx2tf)

This path is for deploying PyTorch models to Raspberry Pi or ARM CPU devices that do not support TensorRT.

### Step 1: Export to ONNX (same as Pipeline 1, Step 1)

### Step 2: Convert ONNX to TFLite via onnx2tf

```bash
pip install onnx2tf tensorflow
```

```python
import onnx2tf
import tensorflow as tf

# Convert ONNX to SavedModel (intermediate)
onnx2tf.convert(
    input_onnx_file_path="mobilenetv2_simplified.onnx",
    output_folder_path="converted_savedmodel",
    non_verbose=True,
)

# Convert SavedModel to TFLite with quantization
converter = tf.lite.TFLiteConverter.from_saved_model("converted_savedmodel")
converter.optimizations = [tf.lite.Optimize.DEFAULT]
converter.target_spec.supported_types = [tf.float16]

tflite_model = converter.convert()
with open("mobilenetv2_from_pytorch.tflite", "wb") as f:
    f.write(tflite_model)
```

**Common issues with onnx2tf:**
- Some PyTorch ops have no TensorFlow equivalent (custom ops, torchvision NMS)
- Channel ordering may differ (PyTorch: NCHW, TensorFlow: NHWC) -- onnx2tf handles this
- Dynamic shapes may need to be pinned to static values before conversion

---

## Pipeline 4: ONNX Runtime Optimization (Portable CPU)

For deployment scenarios where TensorRT and TFLite are not available, ONNX Runtime provides cross-platform optimized inference.

### Graph Optimization

```python
import onnxruntime as ort

# Configure session with graph optimizations
session_options = ort.SessionOptions()
session_options.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_ALL
session_options.optimized_model_filepath = "mobilenetv2_optimized.onnx"

# The optimized model is saved to disk
session = ort.InferenceSession(
    "mobilenetv2_simplified.onnx",
    sess_options=session_options,
    providers=["CPUExecutionProvider"]
)

print("Optimized model saved to mobilenetv2_optimized.onnx")
```

### ONNX Runtime Quantization

```python
from onnxruntime.quantization import quantize_dynamic, QuantType

# Dynamic quantization (no calibration required)
quantize_dynamic(
    model_input="mobilenetv2_simplified.onnx",
    model_output="mobilenetv2_ort_int8.onnx",
    weight_type=QuantType.QInt8
)

print("Dynamic quantized model saved")
```

### ONNX Runtime Static Quantization (with calibration)

```python
from onnxruntime.quantization import (
    quantize_static,
    CalibrationDataReader,
    QuantType,
    QuantFormat,
)
import numpy as np


class ImageDataReader(CalibrationDataReader):
    """Calibration data reader for ONNX Runtime static quantization."""

    def __init__(self, calibration_images, input_name="input"):
        self.data = iter([
            {input_name: img.astype(np.float32)}
            for img in calibration_images
        ])

    def get_next(self):
        return next(self.data, None)


# Prepare calibration data
calibration_images = [
    np.random.randn(1, 3, 224, 224).astype(np.float32)
    for _ in range(300)
]

reader = ImageDataReader(calibration_images)

quantize_static(
    model_input="mobilenetv2_simplified.onnx",
    model_output="mobilenetv2_ort_static_int8.onnx",
    calibration_data_reader=reader,
    quant_format=QuantFormat.QOperator,
    weight_type=QuantType.QInt8,
    activation_type=QuantType.QUInt8
)
```

---

## Dynamic Batching Configuration

### TensorRT Dynamic Batching

```bash
# Build engine with dynamic batch size
trtexec \
    --onnx=model.onnx \
    --saveEngine=model_dynamic.engine \
    --fp16 \
    --minShapes=input:1x3x224x224 \
    --optShapes=input:4x3x224x224 \
    --maxShapes=input:16x3x224x224 \
    --memPoolSize=workspace:2048MiB
```

```python
import tensorrt as trt

def build_dynamic_batch_engine(onnx_path, engine_path,
                                min_batch=1, opt_batch=4, max_batch=16,
                                input_shape=(3, 224, 224)):
    """Build a TensorRT engine with dynamic batch size."""
    logger = trt.Logger(trt.Logger.INFO)
    builder = trt.Builder(logger)
    network_flags = 1 << int(trt.NetworkDefinitionCreationFlag.EXPLICIT_BATCH)
    network = builder.create_network(network_flags)

    parser = trt.OnnxParser(network, logger)
    with open(onnx_path, "rb") as f:
        parser.parse(f.read())

    config = builder.create_builder_config()
    config.set_memory_pool_limit(trt.MemoryPoolType.WORKSPACE, 2048 * (1 << 20))
    config.set_flag(trt.BuilderFlag.FP16)

    # Create optimization profile for dynamic batch
    profile = builder.create_optimization_profile()
    c, h, w = input_shape
    profile.set_shape(
        "input",
        min=(min_batch, c, h, w),
        opt=(opt_batch, c, h, w),
        max=(max_batch, c, h, w),
    )
    config.add_optimization_profile(profile)

    serialized = builder.build_serialized_network(network, config)
    with open(engine_path, "wb") as f:
        f.write(serialized)

    print(f"Dynamic batch engine saved: batch={min_batch}-{max_batch}")
```

### When to Use Dynamic vs Static Batching

| Scenario | Batch Strategy | Rationale |
|----------|---------------|-----------|
| Single camera stream | Static batch=1 | Only one frame at a time |
| Multiple camera streams | Dynamic batch=N | Batch frames from N cameras |
| Variable-rate input | Dynamic batch | Accumulate frames, process in batches |
| Lowest possible latency | Static batch=1 | No waiting to fill a batch |
| Maximum throughput | Static batch=max | Full hardware utilization |
| Edge device (memory limited) | Static batch=1-2 | Minimize peak memory |

---

## Conversion Quick Reference

| Source | Target | Tool | Command / Function |
|--------|--------|------|--------------------|
| PyTorch .pt | ONNX | torch.onnx | `torch.onnx.export(model, dummy, path)` |
| ONNX | TensorRT | trtexec | `trtexec --onnx=m.onnx --fp16 --saveEngine=m.engine` |
| ONNX | TensorRT | Python API | `builder.build_serialized_network(network, config)` |
| Keras .h5 | TFLite | tf.lite | `TFLiteConverter.from_keras_model(model)` |
| SavedModel | TFLite | tf.lite | `TFLiteConverter.from_saved_model(path)` |
| ONNX | TFLite | onnx2tf + tf.lite | Two-step: ONNX to SavedModel, then to TFLite |
| ONNX | Optimized ONNX | onnxruntime | `SessionOptions.optimized_model_filepath` |
| ONNX | Quantized ONNX | onnxruntime.quant | `quantize_dynamic()` or `quantize_static()` |
| TensorFlow | ONNX | tf2onnx | `python -m tf2onnx.convert` |
| ONNX | OpenVINO IR | openvino.tools.mo | `mo.convert_model(path)` |

---

## Troubleshooting Conversions

### ONNX Export Fails with "Unsupported Operation"

```
Problem: torch.onnx.export raises RuntimeError about unsupported op.

Diagnosis:
1. Identify the unsupported operation from the error message
2. Check if a newer opset version supports it

Solutions (in order of preference):
1. Increase opset_version (try 17, then 13, then 11)
2. Replace the unsupported op with an ONNX-compatible alternative
3. Register a custom ONNX symbolic function for the op
4. Refactor the model to avoid the unsupported operation
```

### TFLite Conversion Produces Different Output

```
Problem: TFLite model output does not match TensorFlow model output.

Diagnosis:
1. Compare on same input with same preprocessing
2. Check input/output dtypes (float32 vs uint8)
3. Check for quantization-related range changes

Solutions:
1. Verify preprocessing matches expected input format
2. For INT8 models, ensure input is uint8 (0-255), not float32 (0.0-1.0)
3. Check output dequantization parameters if output is quantized
4. Run the FP32 TFLite model first to isolate quantization vs conversion issues
```

### TensorRT Engine Build OOM

```
Problem: Out of memory during TensorRT engine build on Jetson.

Diagnosis:
1. Engine build requires temporary memory for kernel auto-tuning
2. Large models with many layers test many kernel variants

Solutions:
1. Reduce workspace: --memPoolSize=workspace:512MiB
2. Close all other GPU-consuming processes
3. Disable desktop GUI: sudo systemctl set-default multi-user.target
4. Use a smaller batch size for the build
5. Build on a machine with more memory, then transfer (same arch only)
```

### ONNX to TFLite Channel Ordering Issues

```
Problem: TFLite model from PyTorch ONNX produces wrong spatial outputs.

Root Cause: PyTorch uses NCHW format, TensorFlow uses NHWC format.
onnx2tf handles this automatically, but sometimes fails on unusual ops.

Diagnosis:
1. Check input shape: should be [B, H, W, C] for TFLite
2. Check if transpose operations were correctly inserted

Solutions:
1. Use onnx2tf which handles NCHW-to-NHWC conversion
2. If manual, add explicit transpose before and after conversion
3. Verify spatial dimensions by running on a non-square input
```
