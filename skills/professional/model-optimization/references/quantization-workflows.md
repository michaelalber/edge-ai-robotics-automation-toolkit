# Quantization Workflows

## Overview

Quantization reduces the numerical precision of model weights and activations to achieve smaller model size, faster inference, and lower memory usage. This reference covers every quantization strategy relevant to edge deployment, from simple post-training quantization to full quantization-aware training.

**Quantization Precision Hierarchy:**

```
FP32 (32-bit float)   -- Baseline, maximum accuracy, largest/slowest
  |
FP16 (16-bit float)   -- ~2x compression, negligible accuracy loss for most models
  |
INT8 (8-bit integer)  -- ~4x compression, 0.5-3% accuracy loss typical, requires calibration
  |
INT4 (4-bit integer)  -- ~8x compression, significant accuracy loss, experimental for edge
```

---

## Post-Training Quantization (PTQ)

PTQ quantizes a trained model without any retraining. It is the fastest path to a quantized model but may have higher accuracy loss than QAT for aggressive quantization.

### Dynamic Range Quantization

Weights are quantized to INT8 at save time; activations remain float32 at runtime. This is the simplest form of quantization and requires no calibration data.

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

**When to use**: Quick size reduction with minimal effort. Good first step before trying full INT8.

**Accuracy impact**: Minimal (typically < 0.5% degradation). Weights are INT8, but compute happens in float32.

### Float16 Quantization

Weights are stored in float16; activations use float16 when hardware supports it (XNNPACK delegate on ARM, GPU delegates).

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

**When to use**: Raspberry Pi with XNNPACK delegate, or any ARM device where float16 is hardware-accelerated.

**Accuracy impact**: Negligible for most models (< 0.1%). Float16 has enough dynamic range for typical vision models.

### Full INT8 Post-Training Quantization

Both weights and activations are quantized to INT8. Requires a representative calibration dataset to determine the quantization ranges for each tensor.

```python
import tensorflow as tf
import numpy as np
import cv2
import glob

model = tf.keras.applications.MobileNetV2(
    input_shape=(224, 224, 3),
    weights="imagenet"
)

def representative_dataset(image_dir, input_size=(224, 224), count=300):
    """Load real images for calibration.

    The calibration dataset MUST be representative of actual inference data.
    Using random noise or training augmentations will produce poor quantization.
    """
    image_paths = sorted(glob.glob(f"{image_dir}/*.jpg"))[:count]
    if len(image_paths) < 100:
        raise ValueError(
            f"Only {len(image_paths)} calibration images found. "
            "Need at least 100, recommend 300-500."
        )
    for path in image_paths:
        img = cv2.imread(path)
        img = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
        img = cv2.resize(img, input_size)
        img = img.astype(np.float32) / 255.0
        yield [np.expand_dims(img, axis=0)]

converter = tf.lite.TFLiteConverter.from_keras_model(model)
converter.optimizations = [tf.lite.Optimize.DEFAULT]
converter.representative_dataset = lambda: representative_dataset(
    "/path/to/calibration/images"
)
converter.target_spec.supported_ops = [tf.lite.OpsSet.TFLITE_BUILTINS_INT8]
converter.inference_input_type = tf.uint8
converter.inference_output_type = tf.uint8

tflite_model = converter.convert()
with open("mobilenetv2_int8.tflite", "wb") as f:
    f.write(tflite_model)
```

**Critical**: When using full INT8 quantization, the input dtype changes to `uint8` (0-255). Your preprocessing pipeline MUST match:

```python
# CORRECT for INT8 TFLite model
input_data = image.astype(np.uint8)  # 0-255 range, uint8 dtype

# WRONG for INT8 TFLite model
input_data = image.astype(np.float32) / 255.0  # This produces garbage outputs
```

### TensorRT INT8 Calibration

TensorRT uses a calibration process to determine per-tensor quantization scales. This happens during engine build.

```python
import tensorrt as trt
import pycuda.driver as cuda
import pycuda.autoinit
import numpy as np
import os
from glob import glob
from PIL import Image


class ImageCalibrator(trt.IInt8EntropyCalibrator2):
    """INT8 calibrator for TensorRT engine builds.

    Feeds batches of preprocessed images to TensorRT during engine build
    to compute optimal INT8 quantization scales.
    """

    def __init__(self, calibration_dir, cache_file, batch_size=8,
                 input_shape=(3, 224, 224)):
        super().__init__()
        self.cache_file = cache_file
        self.batch_size = batch_size
        self.input_shape = input_shape

        self.image_paths = sorted(glob(os.path.join(calibration_dir, "*.jpg")))
        self.image_paths += sorted(glob(os.path.join(calibration_dir, "*.png")))
        print(f"Calibration dataset: {len(self.image_paths)} images")

        if len(self.image_paths) < 100:
            raise ValueError("Need at least 100 calibration images, recommend 500+")

        self.current_index = 0
        self.batch_allocation = cuda.mem_alloc(
            batch_size * int(np.prod(input_shape)) * 4  # float32
        )

    def _preprocess(self, image_path):
        img = Image.open(image_path).convert("RGB")
        img = img.resize((self.input_shape[2], self.input_shape[1]))
        arr = np.array(img, dtype=np.float32) / 255.0
        arr = arr.transpose(2, 0, 1)  # HWC to CHW
        return arr

    def get_batch_size(self):
        return self.batch_size

    def get_batch(self, names):
        if self.current_index >= len(self.image_paths):
            return None

        batch = []
        for i in range(self.batch_size):
            idx = self.current_index + i
            if idx >= len(self.image_paths):
                break
            batch.append(self._preprocess(self.image_paths[idx]))

        if not batch:
            return None

        while len(batch) < self.batch_size:
            batch.append(batch[-1])

        batch_array = np.stack(batch).astype(np.float32)
        cuda.memcpy_htod(self.batch_allocation, batch_array.tobytes())
        self.current_index += self.batch_size
        return [int(self.batch_allocation)]

    def read_calibration_cache(self):
        if os.path.exists(self.cache_file):
            with open(self.cache_file, "rb") as f:
                return f.read()
        return None

    def write_calibration_cache(self, cache):
        with open(self.cache_file, "wb") as f:
            f.write(cache)
```

---

## Calibration Dataset Requirements

The calibration dataset directly determines the quality of INT8 quantization. Poor calibration data produces poor quantization.

### Requirements

| Requirement | Minimum | Recommended | Notes |
|-------------|---------|-------------|-------|
| **Sample Count** | 100 | 500-1000 | More samples = more stable quantization ranges |
| **Class Coverage** | All classes | Balanced across classes | Underrepresented classes may lose accuracy |
| **Domain Match** | Same domain | Subset of validation set | Use real data, never synthetic |
| **Preprocessing** | Same as inference | Identical pipeline | Mismatched preprocessing invalidates calibration |
| **No Augmentation** | No augmentations | Clean samples only | Augmentations distort activation ranges |

### Common Calibration Mistakes

```
WRONG: Using random noise as calibration data
  --> Activation ranges will not match real data, causing clipping

WRONG: Using only one class for calibration
  --> Quantization optimized for one class, other classes degrade

WRONG: Using training augmentations (flip, crop, color jitter)
  --> Activation ranges include augmented extremes, wastes dynamic range

WRONG: Using 10 images for calibration
  --> Insufficient to capture the full activation distribution

RIGHT: Using 500+ clean, unaugmented images from the validation set,
       balanced across classes, preprocessed identically to inference
```

---

## Quantization-Aware Training (QAT)

QAT inserts fake quantization nodes into the training graph so the model learns to compensate for quantization error during training. This produces better accuracy than PTQ for aggressive quantization.

### TensorFlow QAT

```python
import tensorflow as tf
import tensorflow_model_optimization as tfmot

# Load pretrained model
base_model = tf.keras.applications.MobileNetV2(
    input_shape=(224, 224, 3),
    weights="imagenet",
    include_top=True,
)

# Wrap model with quantization-aware training
qat_model = tfmot.quantization.keras.quantize_model(base_model)

qat_model.compile(
    optimizer=tf.keras.optimizers.Adam(learning_rate=1e-5),
    loss="categorical_crossentropy",
    metrics=["accuracy"],
)

# Fine-tune with QAT (typically 5-10 epochs with low learning rate)
# qat_model.fit(train_dataset, epochs=5, validation_data=val_dataset)

# Convert QAT model to TFLite INT8
converter = tf.lite.TFLiteConverter.from_keras_model(qat_model)
converter.optimizations = [tf.lite.Optimize.DEFAULT]

tflite_model = converter.convert()
with open("mobilenetv2_qat_int8.tflite", "wb") as f:
    f.write(tflite_model)
```

### PyTorch QAT

```python
import torch
import torch.quantization as quant

# Load pretrained model
model = torch.hub.load("pytorch/vision", "mobilenet_v2", pretrained=True)
model.train()

# Configure QAT
model.qconfig = quant.get_default_qat_qconfig("qnnpack")  # ARM-optimized
quant.prepare_qat(model, inplace=True)

# Fine-tune with QAT
# for epoch in range(num_epochs):
#     for images, targets in train_loader:
#         output = model(images)
#         loss = criterion(output, targets)
#         loss.backward()
#         optimizer.step()

# Convert to quantized model
model.set_mode_to_eval()
quantized_model = quant.convert(model, inplace=False)

# Export to ONNX for further conversion
dummy_input = torch.randn(1, 3, 224, 224)
torch.onnx.export(
    quantized_model, dummy_input, "mobilenetv2_qat.onnx", opset_version=13
)
```

### PTQ vs QAT Decision Guide

| Factor | Post-Training Quantization | Quantization-Aware Training |
|--------|---------------------------|----------------------------|
| **Time Required** | Minutes (no training) | Hours-days (fine-tuning) |
| **Training Data Needed** | Calibration only (500-1000 samples) | Full training dataset |
| **Accuracy Loss (INT8)** | 0.5-3% typical | < 0.5% typical |
| **Best For** | Large models, quick deployment | Accuracy-critical applications |
| **Complexity** | Low | Medium-high |
| **When to Choose** | First attempt at INT8 | When PTQ accuracy is unacceptable |

---

## Per-Layer Sensitivity Analysis

Not all layers respond equally to quantization. Some layers (especially the first and last layers, attention layers, and batch normalization) are more sensitive. Sensitivity analysis identifies which layers to keep at higher precision.

### Method

```python
import numpy as np


def per_layer_sensitivity(model, test_dataset, accuracy_fn,
                          baseline_accuracy, framework="tensorflow"):
    """Measure accuracy impact of quantizing each layer individually.

    For each layer:
    1. Quantize only that layer to INT8
    2. Keep all other layers at FP32
    3. Measure accuracy
    4. Record the accuracy delta

    Layers with the largest delta are the most sensitive and should
    be kept at FP16 or FP32 in a mixed-precision deployment.
    """
    results = []
    layers = get_quantizable_layers(model)

    for layer_name in layers:
        # Quantize only this layer
        quantized_model = quantize_single_layer(model, layer_name)
        accuracy = accuracy_fn(quantized_model, test_dataset)
        delta = baseline_accuracy - accuracy

        results.append({
            "layer": layer_name,
            "accuracy": accuracy,
            "delta": delta,
            "sensitive": delta > 0.005,  # 0.5% threshold
        })

        print(f"Layer {layer_name}: accuracy={accuracy:.4f}, "
              f"delta={delta:+.4f} {'** SENSITIVE **' if delta > 0.005 else ''}")

    # Sort by sensitivity (most sensitive first)
    results.sort(key=lambda x: x["delta"], reverse=True)
    return results
```

### Interpreting Results

```
Layer sensitivity report for MobileNetV2:

Layer                    | Accuracy | Delta   | Status
------------------------|----------|---------|--------
features.0.0            | 0.6980   | -0.0220 | SENSITIVE (first conv)
classifier.1            | 0.7050   | -0.0150 | SENSITIVE (final FC)
features.18.0           | 0.7120   | -0.0080 | SENSITIVE (last block)
features.1.conv.0.0     | 0.7190   | -0.0010 | OK
features.2.conv.1.0     | 0.7198   | -0.0002 | OK
...

Recommendation:
- Keep features.0.0, classifier.1, and features.18.0 at FP16
- Quantize all other layers to INT8
- Expected overall accuracy: ~0.716 (vs 0.720 baseline, 0.6% drop)
```

### TensorRT Mixed Precision

In TensorRT, you can mark specific layers to run at higher precision:

```python
import tensorrt as trt

def build_mixed_precision_engine(onnx_path, engine_path,
                                  sensitive_layers):
    """Build TensorRT engine with mixed INT8/FP16 precision.

    Args:
        onnx_path: Path to ONNX model.
        engine_path: Path to save engine.
        sensitive_layers: List of layer names to keep at FP16.
    """
    logger = trt.Logger(trt.Logger.INFO)
    builder = trt.Builder(logger)
    network_flags = 1 << int(trt.NetworkDefinitionCreationFlag.EXPLICIT_BATCH)
    network = builder.create_network(network_flags)

    parser = trt.OnnxParser(network, logger)
    with open(onnx_path, "rb") as f:
        parser.parse(f.read())

    config = builder.create_builder_config()
    config.set_flag(trt.BuilderFlag.INT8)
    config.set_flag(trt.BuilderFlag.FP16)

    # Mark sensitive layers for FP16 precision
    for i in range(network.num_layers):
        layer = network.get_layer(i)
        if layer.name in sensitive_layers:
            layer.precision = trt.DataType.HALF
            print(f"Layer '{layer.name}' pinned to FP16")

    serialized_engine = builder.build_serialized_network(network, config)
    with open(engine_path, "wb") as f:
        f.write(serialized_engine)
```

---

## Quantization Quick Reference

| Method | Size Reduction | Speed Improvement | Accuracy Impact | Calibration Required | Best For |
|--------|---------------|-------------------|-----------------|---------------------|----------|
| Dynamic Range (TFLite) | ~4x | Moderate | Minimal | No | Quick size reduction |
| Float16 (TFLite) | ~2x | Moderate (with XNNPACK) | Negligible | No | RPi with XNNPACK |
| Full INT8 PTQ (TFLite) | ~4x | Significant on CPU | 0.5-3% | Yes (200+ images) | RPi, Coral TPU |
| QAT INT8 (TFLite) | ~4x | Significant on CPU | < 0.5% | Full training set | Accuracy-critical |
| TensorRT FP16 | ~2x | Large (Jetson GPU) | Negligible | No | Jetson default |
| TensorRT INT8 | ~4x | Largest (Jetson GPU) | 0.5-2% | Yes (500+ images) | Jetson max speed |
| Mixed INT8/FP16 | ~3x | Large | < 1% | Yes (500+ images) | Sensitive models |
| ONNX RT Dynamic | ~3-4x | Moderate | Minimal | No | Portable CPU |

---

## Troubleshooting

### INT8 Model Accuracy Much Worse Than Expected

```
Problem: INT8 accuracy drops more than 3% compared to FP32.

Diagnosis:
1. Verify calibration data is from the correct domain (not random noise)
2. Check calibration dataset size (need 300+ representative samples)
3. Run per-layer sensitivity analysis to find problematic layers

Solutions (in order of preference):
1. Increase calibration dataset size and diversity
2. Use mixed precision: keep sensitive layers at FP16
3. Try a different calibration algorithm (MinMax vs Entropy)
4. Switch to QAT if PTQ cannot achieve acceptable accuracy
```

### Quantized Model Output Range Is Wrong

```
Problem: All outputs are near zero, or outputs are clipped to narrow range.

Root Cause: Activation quantization ranges do not match actual data distribution.

Diagnosis:
1. Compare raw output tensors between FP32 and INT8 models on same input
2. Check if calibration data preprocessing matches inference preprocessing
3. Check if activation ranges are being clipped too aggressively

Solutions:
1. Fix preprocessing mismatch between calibration and inference
2. Use MinMax calibrator instead of Entropy (less aggressive clipping)
3. Increase calibration dataset diversity
```
