# Model Conversion for Edge Deployment

## Overview

Edge devices require optimized model formats. This reference covers every conversion
path you will encounter when deploying computer vision models to Jetson, Raspberry Pi,
and Intel edge hardware.

**Conversion Map:**

```
                    ┌───────────┐
                    │  PyTorch   │
                    └─────┬─────┘
                          │ torch.onnx.export()
                          ▼
┌───────────┐      ┌───────────┐      ┌───────────┐
│ TensorFlow │─────>│   ONNX    │<─────│  Keras    │
└─────┬─────┘      └─────┬─────┘      └───────────┘
      │                   │
      │ tf.lite           │ onnx2tf / onnxruntime
      │ converter         │
      ▼                   ▼
┌───────────┐      ┌───────────┐      ┌───────────┐
│  TFLite   │      │ TensorRT  │      │ OpenVINO  │
│ (RPi/CPU) │      │ (Jetson)  │      │ (Intel)   │
└───────────┘      └───────────┘      └───────────┘
```

## Dependencies

```bash
# Core conversion tools
pip install tensorflow tflite-runtime onnx onnxruntime onnx-simplifier tf2onnx

# For PyTorch models
pip install torch torchvision

# For TensorRT (Jetson only -- install from JetPack SDK)
# sudo apt-get install tensorrt python3-libnvinfer

# For OpenVINO (Intel only)
pip install openvino-dev
```

---

## TensorFlow to TFLite

### Basic Conversion (No Quantization)

```python
import tensorflow as tf

# Load a SavedModel or Keras model
model = tf.keras.applications.MobileNetV2(
    input_shape=(224, 224, 3),
    weights="imagenet",
    include_top=True
)

# Convert to TFLite
converter = tf.lite.TFLiteConverter.from_keras_model(model)
tflite_model = converter.convert()

# Save
with open("mobilenetv2_float32.tflite", "wb") as f:
    f.write(tflite_model)

print(f"Model size: {len(tflite_model) / 1024 / 1024:.1f} MB")
```

### Dynamic Range Quantization

Reduces model size by ~4x with minimal accuracy loss. Weights are quantized to
INT8 at save time; activations remain float32 at runtime.

```python
import tensorflow as tf

model = tf.keras.applications.MobileNetV2(
    input_shape=(224, 224, 3),
    weights="imagenet"
)

converter = tf.lite.TFLiteConverter.from_keras_model(model)
converter.optimizations = [tf.lite.Optimize.DEFAULT]

tflite_model = converter.convert()

with open("mobilenetv2_dynamic_range.tflite", "wb") as f:
    f.write(tflite_model)

print(f"Model size: {len(tflite_model) / 1024 / 1024:.1f} MB")
# Expect ~3.5 MB vs ~14 MB for float32
```

### Float16 Quantization

Reduces model size by ~2x. Good balance of size and accuracy. Supported by
XNNPACK delegate on Raspberry Pi.

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

with open("mobilenetv2_float16.tflite", "wb") as f:
    f.write(tflite_model)

print(f"Model size: {len(tflite_model) / 1024 / 1024:.1f} MB")
# Expect ~7 MB vs ~14 MB for float32
```

### Full INT8 Quantization (Post-Training)

Maximum compression (~4x) and fastest inference on CPU. Requires a representative
dataset for calibration.

```python
import tensorflow as tf
import numpy as np

model = tf.keras.applications.MobileNetV2(
    input_shape=(224, 224, 3),
    weights="imagenet"
)

def representative_dataset():
    """Yield ~100-500 representative samples for calibration."""
    for _ in range(200):
        # Use actual data from your domain for best results
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

print(f"Model size: {len(tflite_model) / 1024 / 1024:.1f} MB")
# Expect ~3.5 MB, with uint8 input/output
```

**Important**: When using INT8 quantization, your preprocessing must produce `uint8`
input (0-255 range), NOT float32 (0.0-1.0). Mismatched input scaling is the number
one cause of garbage outputs with quantized models.

### Full INT8 with Real Calibration Data

```python
import tensorflow as tf
import numpy as np
import cv2
import glob

model = tf.keras.applications.MobileNetV2(
    input_shape=(224, 224, 3),
    weights="imagenet"
)

def representative_dataset_from_images(image_dir, input_size=(224, 224), count=200):
    """Load real images for calibration."""
    image_paths = glob.glob(f"{image_dir}/*.jpg")[:count]
    for path in image_paths:
        img = cv2.imread(path)
        img = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
        img = cv2.resize(img, input_size)
        img = img.astype(np.float32) / 255.0
        yield [np.expand_dims(img, axis=0)]

converter = tf.lite.TFLiteConverter.from_keras_model(model)
converter.optimizations = [tf.lite.Optimize.DEFAULT]
converter.representative_dataset = lambda: representative_dataset_from_images(
    "/path/to/calibration/images"
)
converter.target_spec.supported_ops = [tf.lite.OpsSet.TFLITE_BUILTINS_INT8]
converter.inference_input_type = tf.uint8
converter.inference_output_type = tf.uint8

tflite_model = converter.convert()
with open("mobilenetv2_int8_calibrated.tflite", "wb") as f:
    f.write(tflite_model)
```

### Converting a SavedModel Directory

```python
import tensorflow as tf

# From SavedModel directory (after tf.saved_model.save())
converter = tf.lite.TFLiteConverter.from_saved_model("/path/to/saved_model")
converter.optimizations = [tf.lite.Optimize.DEFAULT]

tflite_model = converter.convert()
with open("model_from_savedmodel.tflite", "wb") as f:
    f.write(tflite_model)
```

---

## PyTorch to ONNX

### Basic Export

```python
import torch
import torchvision

# Load pretrained model
model = torchvision.models.mobilenet_v2(pretrained=True)
model.eval()

# Create dummy input matching model expected input
dummy_input = torch.randn(1, 3, 224, 224)

# Export to ONNX
torch.onnx.export(
    model,
    dummy_input,
    "mobilenetv2.onnx",
    opset_version=13,
    input_names=["input"],
    output_names=["output"],
    dynamic_axes={
        "input": {0: "batch_size"},
        "output": {0: "batch_size"},
    },
)

print("ONNX export complete: mobilenetv2.onnx")
```

### Export Detection Model (YOLOv5-style)

```python
import torch

# Load YOLOv5 model
model = torch.hub.load("ultralytics/yolov5", "yolov5s", pretrained=True)
model.eval()

dummy_input = torch.randn(1, 3, 640, 640)

torch.onnx.export(
    model.model,
    dummy_input,
    "yolov5s.onnx",
    opset_version=13,
    input_names=["images"],
    output_names=["output"],
    dynamic_axes={
        "images": {0: "batch_size"},
        "output": {0: "batch_size"},
    },
)
```

### ONNX Simplification

Simplification removes redundant operations and constant-folds where possible.
Always run this before converting to TFLite or TensorRT.

```python
import onnx
from onnxsim import simplify

model = onnx.load("mobilenetv2.onnx")

# Simplify
model_simplified, check = simplify(model)
assert check, "Simplified ONNX model validation failed"

onnx.save(model_simplified, "mobilenetv2_simplified.onnx")
print("Simplified model saved")
```

### ONNX Validation

```python
import onnx
import onnxruntime as ort
import numpy as np

# Structural validation
model = onnx.load("mobilenetv2.onnx")
onnx.checker.check_model(model)
print("ONNX model structure is valid")

# Runtime validation
session = ort.InferenceSession("mobilenetv2.onnx")
input_name = session.get_inputs()[0].name
input_shape = session.get_inputs()[0].shape
print(f"Input: {input_name}, shape: {input_shape}")

# Test inference
dummy = np.random.randn(1, 3, 224, 224).astype(np.float32)
result = session.run(None, {input_name: dummy})
print(f"Output shape: {result[0].shape}")
```

---

## ONNX to TFLite

This is the primary path for PyTorch models targeting Raspberry Pi.

### Using onnx2tf

```bash
pip install onnx2tf tensorflow
```

```python
import onnx2tf
import tensorflow as tf

# Convert ONNX to TFLite via SavedModel intermediate
onnx2tf.convert(
    input_onnx_file_path="mobilenetv2_simplified.onnx",
    output_folder_path="converted_model",
    non_verbose=True,
)

# The tool produces a SavedModel directory; now convert to TFLite
converter = tf.lite.TFLiteConverter.from_saved_model("converted_model")
converter.optimizations = [tf.lite.Optimize.DEFAULT]
converter.target_spec.supported_types = [tf.float16]

tflite_model = converter.convert()
with open("mobilenetv2_from_onnx.tflite", "wb") as f:
    f.write(tflite_model)
```

### Using tf2onnx (Reverse Direction: TF to ONNX)

```bash
pip install tf2onnx
```

```python
import subprocess

# Command-line conversion
subprocess.run([
    "python", "-m", "tf2onnx.convert",
    "--saved-model", "/path/to/saved_model",
    "--output", "model.onnx",
    "--opset", "13",
], check=True)
```

---

## ONNX to TensorRT (Jetson)

### Using trtexec (Recommended for Jetson)

```bash
# Float16 (default for Jetson -- best speed/accuracy tradeoff)
/usr/src/tensorrt/bin/trtexec \
    --onnx=mobilenetv2_simplified.onnx \
    --saveEngine=mobilenetv2_fp16.engine \
    --fp16 \
    --workspace=1024

# INT8 (requires calibration cache)
/usr/src/tensorrt/bin/trtexec \
    --onnx=mobilenetv2_simplified.onnx \
    --saveEngine=mobilenetv2_int8.engine \
    --int8 \
    --calib=calibration_cache.bin \
    --workspace=1024

# Verify the engine
/usr/src/tensorrt/bin/trtexec \
    --loadEngine=mobilenetv2_fp16.engine \
    --batch=1
```

### Using Python TensorRT API

```python
import tensorrt as trt
import numpy as np

TRT_LOGGER = trt.Logger(trt.Logger.WARNING)

def build_engine_from_onnx(onnx_path, engine_path, fp16=True, max_batch=1):
    """Build TensorRT engine from ONNX model."""
    builder = trt.Builder(TRT_LOGGER)
    network = builder.create_network(
        1 << int(trt.NetworkDefinitionCreationFlag.EXPLICIT_BATCH)
    )
    parser = trt.OnnxParser(network, TRT_LOGGER)

    # Parse ONNX model
    with open(onnx_path, "rb") as f:
        if not parser.parse(f.read()):
            for i in range(parser.num_errors):
                print(f"ONNX parse error: {parser.get_error(i)}")
            raise RuntimeError("Failed to parse ONNX model")

    # Configure builder
    config = builder.create_builder_config()
    config.set_memory_pool_limit(trt.MemoryPoolType.WORKSPACE, 1 << 30)  # 1GB

    if fp16 and builder.platform_has_fast_fp16:
        config.set_flag(trt.BuilderFlag.FP16)
        print("FP16 enabled")

    # Build engine
    serialized_engine = builder.build_serialized_network(network, config)
    if serialized_engine is None:
        raise RuntimeError("Failed to build TensorRT engine")

    # Save engine
    with open(engine_path, "wb") as f:
        f.write(serialized_engine)

    print(f"Engine saved: {engine_path}")
    return engine_path


# Usage
build_engine_from_onnx(
    "mobilenetv2_simplified.onnx",
    "mobilenetv2_fp16.engine",
    fp16=True,
)
```

### TensorRT Inference on Jetson

```python
import tensorrt as trt
import pycuda.driver as cuda
import pycuda.autoinit
import numpy as np

TRT_LOGGER = trt.Logger(trt.Logger.WARNING)


class TensorRTInference:
    def __init__(self, engine_path):
        self.runtime = trt.Runtime(TRT_LOGGER)
        with open(engine_path, "rb") as f:
            self.engine = self.runtime.deserialize_cuda_engine(f.read())
        self.context = self.engine.create_execution_context()

        # Allocate buffers
        self.inputs = []
        self.outputs = []
        self.bindings = []
        self.stream = cuda.Stream()

        for i in range(self.engine.num_io_tensors):
            name = self.engine.get_tensor_name(i)
            shape = self.engine.get_tensor_shape(name)
            dtype = trt.nptype(self.engine.get_tensor_dtype(name))
            size = np.prod(shape)
            host_mem = cuda.pagelocked_empty(size, dtype)
            device_mem = cuda.mem_alloc(host_mem.nbytes)
            self.bindings.append(int(device_mem))

            if self.engine.get_tensor_mode(name) == trt.TensorIOMode.INPUT:
                self.inputs.append({
                    "host": host_mem, "device": device_mem, "shape": shape
                })
            else:
                self.outputs.append({
                    "host": host_mem, "device": device_mem, "shape": shape
                })

    def infer(self, input_data):
        """Run inference with input numpy array."""
        np.copyto(self.inputs[0]["host"], input_data.ravel())
        cuda.memcpy_htod_async(
            self.inputs[0]["device"], self.inputs[0]["host"], self.stream
        )

        for i, binding in enumerate(self.bindings):
            name = self.engine.get_tensor_name(i)
            self.context.set_tensor_address(name, binding)

        self.context.execute_async_v3(stream_handle=self.stream.handle)

        results = []
        for out in self.outputs:
            cuda.memcpy_dtoh_async(out["host"], out["device"], self.stream)
        self.stream.synchronize()

        for out in self.outputs:
            results.append(out["host"].reshape(out["shape"]))
        return results


# Usage
engine = TensorRTInference("mobilenetv2_fp16.engine")
input_data = np.random.rand(1, 3, 224, 224).astype(np.float32)
outputs = engine.infer(input_data)
print(f"Output shape: {outputs[0].shape}")
```

---

## OpenVINO Conversion (Intel)

### ONNX to OpenVINO IR

```python
from openvino.tools import mo
from openvino.runtime import Core

# Convert ONNX to OpenVINO IR format
ov_model = mo.convert_model(
    "mobilenetv2_simplified.onnx",
    compress_to_fp16=True,
)

# Save to IR files (.xml + .bin)
from openvino.runtime import serialize
serialize(ov_model, "mobilenetv2_ov.xml")
print("OpenVINO IR saved: mobilenetv2_ov.xml + mobilenetv2_ov.bin")
```

### OpenVINO Inference

```python
from openvino.runtime import Core
import numpy as np

core = Core()
model = core.read_model("mobilenetv2_ov.xml")
compiled = core.compile_model(model, "CPU")  # or "GPU", "MYRIAD" for NCS2

input_layer = compiled.input(0)
output_layer = compiled.output(0)

input_data = np.random.rand(1, 3, 224, 224).astype(np.float32)
result = compiled([input_data])

output = result[output_layer]
print(f"Output shape: {output.shape}")
```

### OpenVINO INT8 Quantization with NNCF

```python
import nncf
from openvino.runtime import Core
import numpy as np

core = Core()
model = core.read_model("mobilenetv2_ov.xml")

def transform_fn(data_item):
    """Preprocess calibration sample."""
    return np.expand_dims(data_item, axis=0).astype(np.float32)

# Calibration dataset (list of numpy arrays)
calibration_data = [
    np.random.rand(3, 224, 224).astype(np.float32) for _ in range(200)
]
calibration_dataset = nncf.Dataset(calibration_data, transform_fn)

quantized_model = nncf.quantize(model, calibration_dataset)

from openvino.runtime import serialize
serialize(quantized_model, "mobilenetv2_ov_int8.xml")
```

---

## Quantization-Aware Training (QAT)

### TensorFlow QAT

Post-training quantization is good; QAT is better when accuracy matters.

```python
import tensorflow as tf
import tensorflow_model_optimization as tfmot

# Load base model
base_model = tf.keras.applications.MobileNetV2(
    input_shape=(224, 224, 3),
    weights="imagenet",
    include_top=True,
)

# Apply quantization-aware training
quantize_model = tfmot.quantization.keras.quantize_model
qat_model = quantize_model(base_model)

qat_model.compile(
    optimizer=tf.keras.optimizers.Adam(learning_rate=1e-5),
    loss="categorical_crossentropy",
    metrics=["accuracy"],
)

# Fine-tune with QAT (use your actual training data)
# qat_model.fit(train_dataset, epochs=5, validation_data=val_dataset)

# Convert QAT model to TFLite
converter = tf.lite.TFLiteConverter.from_keras_model(qat_model)
converter.optimizations = [tf.lite.Optimize.DEFAULT]

tflite_model = converter.convert()
with open("mobilenetv2_qat_int8.tflite", "wb") as f:
    f.write(tflite_model)
```

### PyTorch QAT

```python
import torch
import torchvision
from torch.quantization import get_default_qat_qconfig, prepare_qat, convert

# Load model
model = torchvision.models.mobilenet_v2(pretrained=True)
model.train()

# Fuse modules for quantization
model.fuse_model()

# Set QAT config
model.qconfig = get_default_qat_qconfig("fbgemm")
prepare_qat(model, inplace=True)

# Fine-tune with QAT
# for epoch in range(num_epochs):
#     for images, targets in train_loader:
#         output = model(images)
#         loss = criterion(output, targets)
#         loss.backward()
#         optimizer.step()

# Convert to quantized model
model.eval()
quantized_model = convert(model, inplace=False)

# Export to ONNX, then convert to TFLite
dummy_input = torch.randn(1, 3, 224, 224)
torch.onnx.export(
    quantized_model, dummy_input, "mobilenetv2_qat.onnx", opset_version=13
)
```

---

## Model Validation After Conversion

Always validate accuracy after conversion. A model that converts without errors
can still produce wrong results.

```python
import numpy as np
import cv2
import tflite_runtime.interpreter as tflite

def validate_tflite_model(model_path, test_images, expected_classes,
                          input_size=(224, 224)):
    """Compare TFLite model predictions against expected classes."""
    interpreter = tflite.Interpreter(model_path=model_path, num_threads=4)
    interpreter.allocate_tensors()

    input_details = interpreter.get_input_details()[0]
    output_details = interpreter.get_output_details()[0]

    correct = 0
    total = len(test_images)

    for img_path, expected_class in zip(test_images, expected_classes):
        img = cv2.imread(img_path)
        img = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
        img = cv2.resize(img, input_size)

        # Match input dtype
        if input_details["dtype"] == np.uint8:
            input_data = np.expand_dims(img.astype(np.uint8), axis=0)
        else:
            input_data = np.expand_dims(img.astype(np.float32) / 255.0, axis=0)

        interpreter.set_tensor(input_details["index"], input_data)
        interpreter.invoke()

        output = interpreter.get_tensor(output_details["index"])[0]
        predicted_class = np.argmax(output)

        if predicted_class == expected_class:
            correct += 1

    accuracy = correct / total * 100
    print(f"Accuracy: {accuracy:.1f}% ({correct}/{total})")
    return accuracy
```

---

## Quick Reference: Conversion Commands

| Source | Target | Tool | Command / Function |
|--------|--------|------|--------------------|
| Keras .h5 | TFLite | `tf.lite.TFLiteConverter` | `from_keras_model(model)` |
| SavedModel | TFLite | `tf.lite.TFLiteConverter` | `from_saved_model(path)` |
| PyTorch .pt | ONNX | `torch.onnx` | `torch.onnx.export(model, dummy, path)` |
| ONNX | TFLite | `onnx2tf` + `tf.lite` | Two-step: ONNX to SavedModel, then to TFLite |
| ONNX | TensorRT | `trtexec` | `trtexec --onnx=model.onnx --fp16` |
| ONNX | OpenVINO | `openvino.tools.mo` | `mo.convert_model(path)` |
| TensorFlow | ONNX | `tf2onnx` | `python -m tf2onnx.convert` |

## Quantization Quick Reference

| Method | Size Reduction | Speed Improvement | Accuracy Impact | Best For |
|--------|---------------|-------------------|-----------------|----------|
| Dynamic Range | ~4x | Moderate | Minimal | General deployment |
| Float16 | ~2x | Moderate (with delegate) | Negligible | RPi with XNNPACK |
| Full INT8 (PTQ) | ~4x | Significant | Small (1-3%) | RPi CPU, Coral TPU |
| Full INT8 (QAT) | ~4x | Significant | Minimal (<1%) | Accuracy-critical apps |
| TensorRT FP16 | ~2x | Large (Jetson GPU) | Negligible | Jetson default |
| TensorRT INT8 | ~4x | Largest | Small | Jetson max throughput |
