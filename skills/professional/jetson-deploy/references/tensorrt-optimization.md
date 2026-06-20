# TensorRT Optimization Reference

## Overview

TensorRT is NVIDIA's SDK for high-performance deep learning inference. On Jetson Orin Nano, TensorRT is the primary path to production-grade inference performance. It performs layer fusion, precision calibration, kernel auto-tuning, and memory optimization specific to the target GPU architecture.

This reference covers the complete workflow from ONNX model to optimized TensorRT engine, with emphasis on Jetson Orin Nano deployment.

---

## ONNX to TensorRT Conversion Workflow

### High-Level Pipeline

```
┌──────────────┐    ┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│   Training   │───>│  ONNX Export  │───>│  TensorRT    │───>│  Deploy      │
│  Framework   │    │  (.onnx)      │    │  Engine      │    │  (.engine)   │
│  (PyTorch,   │    │              │    │  Build       │    │              │
│   TF, etc.)  │    │              │    │              │    │              │
└──────────────┘    └──────────────┘    └──────────────┘    └──────────────┘
                          │                    │
                          v                    v
                    ┌──────────────┐    ┌──────────────┐
                    │  Validate    │    │  Benchmark   │
                    │  & Simplify  │    │  & Profile   │
                    └──────────────┘    └──────────────┘
```

### Step 1: Export to ONNX

Export the trained model to ONNX format. This must be done in the training environment (not necessarily on the Jetson).

**PyTorch Export:**

```python
import torch
import torchvision.models as models

# Load your trained model
model = models.resnet50(pretrained=True)
model.set_mode_eval()

# Create dummy input matching your model's expected input
dummy_input = torch.randn(1, 3, 224, 224)

# Export to ONNX
torch.onnx.export(
    model,
    dummy_input,
    "resnet50.onnx",
    opset_version=17,           # Use highest supported opset
    input_names=["input"],
    output_names=["output"],
    dynamic_axes={               # Optional: enable dynamic batching
        "input": {0: "batch_size"},
        "output": {0: "batch_size"}
    }
)

print("Exported to resnet50.onnx")
```

**YOLOv8 Export (using ultralytics):**

```python
from ultralytics import YOLO

model = YOLO("yolov8n.pt")

# Export to ONNX with specific input size
model.export(
    format="onnx",
    imgsz=640,
    opset=17,
    simplify=True,
    dynamic=False,       # Static shape for best TensorRT performance
    half=False           # Export in FP32; TensorRT handles precision
)
```

### Step 2: Validate and Simplify ONNX

Always validate and simplify the ONNX model before TensorRT conversion:

```python
import onnx
from onnxsim import simplify

# Load and validate
model = onnx.load("resnet50.onnx")
onnx.checker.check_model(model)
print(f"ONNX model is valid")
print(f"Opset version: {model.opset_import[0].version}")
print(f"Input shape: {model.graph.input[0].type.tensor_type.shape}")

# Simplify (fuses ops, removes redundant nodes)
model_simplified, check = simplify(model)
assert check, "Simplified ONNX model could not be validated"

onnx.save(model_simplified, "resnet50_simplified.onnx")
print("Simplified model saved")
```

Inspect model structure:

```python
import onnx

model = onnx.load("resnet50_simplified.onnx")

# Print all inputs
for inp in model.graph.input:
    shape = [d.dim_value for d in inp.type.tensor_type.shape.dim]
    print(f"Input: {inp.name}, Shape: {shape}")

# Print all outputs
for out in model.graph.output:
    shape = [d.dim_value for d in out.type.tensor_type.shape.dim]
    print(f"Output: {out.name}, Shape: {shape}")

# Count operations
from collections import Counter
op_counts = Counter(node.op_type for node in model.graph.node)
for op, count in op_counts.most_common():
    print(f"  {op}: {count}")
```

### Step 3: Convert to TensorRT Engine

There are two approaches: `trtexec` command-line tool and the TensorRT Python API.

---

## trtexec Command-Line Conversion

### Basic FP16 Conversion

```bash
# Convert ONNX to TensorRT engine with FP16 precision
trtexec \
    --onnx=resnet50_simplified.onnx \
    --saveEngine=resnet50_fp16.engine \
    --fp16 \
    --memPoolSize=workspace:2048MiB \
    --verbose
```

### FP32 Baseline

```bash
# FP32 for accuracy baseline (slower, more memory)
trtexec \
    --onnx=resnet50_simplified.onnx \
    --saveEngine=resnet50_fp32.engine \
    --memPoolSize=workspace:2048MiB
```

### INT8 with Calibration Cache

```bash
# INT8 requires a calibration cache (generated via Python API)
trtexec \
    --onnx=resnet50_simplified.onnx \
    --saveEngine=resnet50_int8.engine \
    --int8 \
    --calib=calibration.cache \
    --memPoolSize=workspace:2048MiB
```

### Dynamic Shapes

```bash
# Enable dynamic batch size (1 to 16)
trtexec \
    --onnx=model.onnx \
    --saveEngine=model_dynamic.engine \
    --fp16 \
    --minShapes=input:1x3x224x224 \
    --optShapes=input:4x3x224x224 \
    --maxShapes=input:16x3x224x224 \
    --memPoolSize=workspace:2048MiB
```

### Benchmarking with trtexec

```bash
# Benchmark an existing engine
trtexec \
    --loadEngine=resnet50_fp16.engine \
    --iterations=1000 \
    --avgRuns=100 \
    --warmUp=5000 \
    --duration=60

# Output includes:
# - Throughput (qps)
# - Host/GPU latency (mean, min, max, median, percentiles)
# - GPU compute time
# - Memory usage
```

### trtexec Quick Reference

| Flag | Purpose | Example |
|------|---------|---------|
| `--onnx` | Input ONNX model | `--onnx=model.onnx` |
| `--saveEngine` | Output engine file | `--saveEngine=model.engine` |
| `--loadEngine` | Load existing engine for benchmarking | `--loadEngine=model.engine` |
| `--fp16` | Enable FP16 precision | `--fp16` |
| `--int8` | Enable INT8 precision | `--int8` |
| `--best` | Try all precisions, pick fastest | `--best` |
| `--memPoolSize` | Set workspace memory | `--memPoolSize=workspace:1024MiB` |
| `--minShapes` | Minimum dynamic shape | `--minShapes=input:1x3x224x224` |
| `--optShapes` | Optimal dynamic shape | `--optShapes=input:4x3x224x224` |
| `--maxShapes` | Maximum dynamic shape | `--maxShapes=input:16x3x224x224` |
| `--iterations` | Number of inference iterations | `--iterations=1000` |
| `--warmUp` | Warm-up time in ms | `--warmUp=5000` |
| `--verbose` | Detailed build/run output | `--verbose` |
| `--calib` | Calibration cache for INT8 | `--calib=calib.cache` |

---

## TensorRT Python API

### Basic Engine Build

```python
import tensorrt as trt
import os

def build_engine_from_onnx(
    onnx_path: str,
    engine_path: str,
    fp16: bool = True,
    int8: bool = False,
    max_workspace_mb: int = 2048,
    max_batch_size: int = 1,
    calibrator=None
):
    """Build a TensorRT engine from an ONNX model.

    Args:
        onnx_path: Path to the ONNX model file.
        engine_path: Path to save the built engine.
        fp16: Enable FP16 precision.
        int8: Enable INT8 precision (requires calibrator).
        max_workspace_mb: Maximum workspace size in MB.
        max_batch_size: Maximum batch size for implicit batch mode.
        calibrator: INT8 calibrator instance (required if int8=True).

    Returns:
        True if engine was built successfully, False otherwise.
    """
    logger = trt.Logger(trt.Logger.INFO)

    # Create builder and network
    builder = trt.Builder(logger)
    network_flags = 1 << int(trt.NetworkDefinitionCreationFlag.EXPLICIT_BATCH)
    network = builder.create_network(network_flags)

    # Parse ONNX model
    parser = trt.OnnxParser(network, logger)
    with open(onnx_path, "rb") as f:
        if not parser.parse(f.read()):
            for i in range(parser.num_errors):
                print(f"ONNX Parse Error: {parser.get_error(i)}")
            return False

    # Print network info
    print(f"Network inputs: {network.num_inputs}")
    for i in range(network.num_inputs):
        inp = network.get_input(i)
        print(f"  Input {i}: {inp.name}, shape={inp.shape}, dtype={inp.dtype}")

    print(f"Network outputs: {network.num_outputs}")
    for i in range(network.num_outputs):
        out = network.get_output(i)
        print(f"  Output {i}: {out.name}, shape={out.shape}, dtype={out.dtype}")

    # Configure builder
    config = builder.create_builder_config()
    config.set_memory_pool_limit(
        trt.MemoryPoolType.WORKSPACE,
        max_workspace_mb * (1 << 20)  # Convert MB to bytes
    )

    # Set precision
    if fp16 and builder.platform_has_fast_fp16:
        config.set_flag(trt.BuilderFlag.FP16)
        print("FP16 precision enabled")

    if int8 and builder.platform_has_fast_int8:
        config.set_flag(trt.BuilderFlag.INT8)
        if calibrator is not None:
            config.int8_calibrator = calibrator
        print("INT8 precision enabled")

    # Build the engine
    print("Building TensorRT engine (this may take several minutes)...")
    serialized_engine = builder.build_serialized_network(network, config)
    if serialized_engine is None:
        print("ERROR: Failed to build engine")
        return False

    # Save engine to file
    with open(engine_path, "wb") as f:
        f.write(serialized_engine)

    engine_size_mb = os.path.getsize(engine_path) / (1024 * 1024)
    print(f"Engine saved to {engine_path} ({engine_size_mb:.1f} MB)")
    return True


# Usage
if __name__ == "__main__":
    build_engine_from_onnx(
        onnx_path="resnet50_simplified.onnx",
        engine_path="resnet50_fp16.engine",
        fp16=True,
        max_workspace_mb=2048
    )
```

### Running Inference with a TensorRT Engine

```python
import tensorrt as trt
import pycuda.driver as cuda
import pycuda.autoinit
import numpy as np


class TensorRTInference:
    """Run inference using a TensorRT engine.

    This class handles engine loading, memory allocation, and inference
    execution. It supports both synchronous and asynchronous execution.
    """

    def __init__(self, engine_path: str):
        self.logger = trt.Logger(trt.Logger.WARNING)
        self.runtime = trt.Runtime(self.logger)

        # Load engine
        with open(engine_path, "rb") as f:
            engine_data = f.read()
        self.engine = self.runtime.deserialize_cuda_engine(engine_data)
        if self.engine is None:
            raise RuntimeError(f"Failed to load engine from {engine_path}")

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
            size = trt.volume(shape)
            host_mem = cuda.pagelocked_empty(size, dtype)
            device_mem = cuda.mem_alloc(host_mem.nbytes)

            self.bindings.append(int(device_mem))
            self.context.set_tensor_address(name, int(device_mem))

            if self.engine.get_tensor_mode(name) == trt.TensorIOMode.INPUT:
                self.inputs.append({
                    "name": name,
                    "host": host_mem,
                    "device": device_mem,
                    "shape": shape,
                    "dtype": dtype
                })
            else:
                self.outputs.append({
                    "name": name,
                    "host": host_mem,
                    "device": device_mem,
                    "shape": shape,
                    "dtype": dtype
                })

        print(f"Engine loaded: {len(self.inputs)} inputs, {len(self.outputs)} outputs")

    def infer(self, input_data: np.ndarray) -> list:
        """Run synchronous inference.

        Args:
            input_data: Numpy array matching the engine input shape and dtype.

        Returns:
            List of numpy arrays, one per engine output.
        """
        # Copy input to host buffer
        np.copyto(self.inputs[0]["host"], input_data.ravel())

        # Transfer input to device
        for inp in self.inputs:
            cuda.memcpy_htod_async(inp["device"], inp["host"], self.stream)

        # Run inference
        self.context.execute_async_v3(stream_handle=self.stream.handle)

        # Transfer output from device
        for out in self.outputs:
            cuda.memcpy_dtoh_async(out["host"], out["device"], self.stream)

        # Synchronize
        self.stream.synchronize()

        # Return outputs reshaped
        results = []
        for out in self.outputs:
            result = out["host"].reshape(out["shape"])
            results.append(result.copy())

        return results

    def __del__(self):
        """Clean up CUDA resources."""
        del self.context
        del self.engine
        del self.runtime


# Usage
if __name__ == "__main__":
    engine = TensorRTInference("resnet50_fp16.engine")

    # Create sample input (batch=1, channels=3, height=224, width=224)
    input_data = np.random.randn(1, 3, 224, 224).astype(np.float32)

    # Run inference
    outputs = engine.infer(input_data)
    print(f"Output shape: {outputs[0].shape}")
    print(f"Top-5 predictions: {np.argsort(outputs[0][0])[-5:][::-1]}")
```

---

## Precision Modes

### FP32 (Full Precision)

- Maximum accuracy, slowest inference
- Use as accuracy baseline
- Does NOT leverage Orin Nano tensor cores efficiently
- Memory: full model weights in 32-bit float

```bash
trtexec --onnx=model.onnx --saveEngine=model_fp32.engine
```

### FP16 (Half Precision)

- Default recommendation for Orin Nano
- Leverages hardware FP16 tensor cores
- Typically < 0.1% accuracy loss for most models
- Approximately 2x faster than FP32, approximately 50% less memory for weights

```bash
trtexec --onnx=model.onnx --saveEngine=model_fp16.engine --fp16
```

### INT8 (Quantized)

- Maximum performance, requires calibration
- Approximately 2-4x faster than FP16 on supported layers
- Accuracy loss varies by model (0.5-3% typical, can be more)
- Requires representative calibration dataset (500-1000 images)
- Not all layers support INT8; TensorRT falls back to FP16/FP32

**INT8 Calibration with Python API:**

```python
import tensorrt as trt
import pycuda.driver as cuda
import pycuda.autoinit
import numpy as np
import os
from glob import glob


class ImageCalibrator(trt.IInt8EntropyCalibrator2):
    """INT8 calibrator using representative images.

    Feeds batches of preprocessed images to TensorRT to compute
    quantization scale factors for each tensor in the network.
    """

    def __init__(
        self,
        calibration_dir: str,
        cache_file: str,
        batch_size: int = 8,
        input_shape: tuple = (3, 224, 224),
        preprocess_fn=None
    ):
        super().__init__()
        self.cache_file = cache_file
        self.batch_size = batch_size
        self.input_shape = input_shape
        self.preprocess_fn = preprocess_fn or self._default_preprocess

        # Load calibration image paths
        self.image_paths = sorted(glob(os.path.join(calibration_dir, "*.jpg")))
        self.image_paths += sorted(glob(os.path.join(calibration_dir, "*.png")))
        print(f"Calibration images: {len(self.image_paths)}")

        self.current_index = 0
        self.batch_allocation = cuda.mem_alloc(
            batch_size * int(np.prod(input_shape)) * np.dtype(np.float32).itemsize
        )

    def _default_preprocess(self, image_path: str) -> np.ndarray:
        """Default preprocessing: resize, normalize to 0-1 range, CHW format."""
        from PIL import Image
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
            img = self.preprocess_fn(self.image_paths[idx])
            batch.append(img)

        if len(batch) == 0:
            return None

        # Pad batch if needed
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
        print(f"Calibration cache written to {self.cache_file}")


# Build INT8 engine with calibration
def build_int8_engine(
    onnx_path: str,
    engine_path: str,
    calibration_dir: str,
    cache_file: str = "calibration.cache"
):
    """Build a TensorRT INT8 engine with calibration.

    Args:
        onnx_path: Path to the ONNX model.
        engine_path: Path to save the TensorRT engine.
        calibration_dir: Directory containing calibration images.
        cache_file: Path to save or load calibration cache.
    """
    calibrator = ImageCalibrator(
        calibration_dir=calibration_dir,
        cache_file=cache_file,
        batch_size=8,
        input_shape=(3, 224, 224)
    )

    logger = trt.Logger(trt.Logger.INFO)
    builder = trt.Builder(logger)
    network_flags = 1 << int(trt.NetworkDefinitionCreationFlag.EXPLICIT_BATCH)
    network = builder.create_network(network_flags)

    parser = trt.OnnxParser(network, logger)
    with open(onnx_path, "rb") as f:
        parser.parse(f.read())

    config = builder.create_builder_config()
    config.set_memory_pool_limit(
        trt.MemoryPoolType.WORKSPACE,
        2048 * (1 << 20)
    )
    config.set_flag(trt.BuilderFlag.INT8)
    config.set_flag(trt.BuilderFlag.FP16)  # Fallback for unsupported layers
    config.int8_calibrator = calibrator

    print("Building INT8 engine (this may take 10-30 minutes)...")
    serialized_engine = builder.build_serialized_network(network, config)

    with open(engine_path, "wb") as f:
        f.write(serialized_engine)

    print(f"INT8 engine saved to {engine_path}")
```

### Precision Selection Guide

```
Decision Tree for Precision:

1. Is this a prototype or experiment?
   -- Yes: Use FP32 (accuracy baseline, no conversion complexity)

2. Is this for production on Jetson Orin Nano?
   -- Yes: Start with FP16

3. Does FP16 meet latency requirements?
   -- Yes: Ship FP16 (done)
   -- No:  Try INT8

4. Is INT8 accuracy acceptable?
   -- Yes: Ship INT8
   -- No:  Use mixed precision or try a smaller model

5. Is the calibration dataset representative?
   -- Must be: 500-1000 images covering the full input distribution
```

---

## Dynamic Batching and Shapes

### When to Use Dynamic Shapes

- Varying batch sizes at inference time
- Variable input resolutions (e.g., different video streams)
- Multi-model serving where inputs differ per request

### Configuring Dynamic Shapes

```python
import tensorrt as trt

def build_dynamic_engine(onnx_path: str, engine_path: str):
    """Build engine with dynamic batch size and input resolution."""
    logger = trt.Logger(trt.Logger.INFO)
    builder = trt.Builder(logger)
    network_flags = 1 << int(trt.NetworkDefinitionCreationFlag.EXPLICIT_BATCH)
    network = builder.create_network(network_flags)

    parser = trt.OnnxParser(network, logger)
    with open(onnx_path, "rb") as f:
        parser.parse(f.read())

    config = builder.create_builder_config()
    config.set_memory_pool_limit(
        trt.MemoryPoolType.WORKSPACE, 2048 * (1 << 20)
    )
    config.set_flag(trt.BuilderFlag.FP16)

    # Create optimization profile for dynamic shapes
    profile = builder.create_optimization_profile()

    # Define min, optimal, and max shapes for input tensor
    # Format: (batch, channels, height, width)
    profile.set_shape(
        "input",
        min=(1, 3, 224, 224),      # Minimum shape
        opt=(4, 3, 640, 640),      # Optimal shape (most common)
        max=(16, 3, 1280, 1280)    # Maximum shape
    )

    config.add_optimization_profile(profile)

    print("Building dynamic shape engine...")
    serialized_engine = builder.build_serialized_network(network, config)

    with open(engine_path, "wb") as f:
        f.write(serialized_engine)

    print(f"Dynamic engine saved to {engine_path}")
```

### Setting Dynamic Shapes at Runtime

```python
import tensorrt as trt
import pycuda.driver as cuda
import pycuda.autoinit
import numpy as np


def infer_dynamic(engine_path: str, input_data: np.ndarray):
    """Run inference with dynamic input shape."""
    logger = trt.Logger(trt.Logger.WARNING)
    runtime = trt.Runtime(logger)

    with open(engine_path, "rb") as f:
        engine = runtime.deserialize_cuda_engine(f.read())

    context = engine.create_execution_context()

    # Set the actual input shape for this inference
    input_name = engine.get_tensor_name(0)
    context.set_input_shape(input_name, input_data.shape)

    # Allocate buffers based on actual shape
    stream = cuda.Stream()

    # Input buffer
    d_input = cuda.mem_alloc(input_data.nbytes)
    cuda.memcpy_htod_async(d_input, input_data, stream)
    context.set_tensor_address(input_name, int(d_input))

    # Output buffer (shape depends on input)
    output_name = engine.get_tensor_name(1)
    output_shape = context.get_tensor_shape(output_name)
    output_dtype = trt.nptype(engine.get_tensor_dtype(output_name))
    h_output = cuda.pagelocked_empty(trt.volume(output_shape), output_dtype)
    d_output = cuda.mem_alloc(h_output.nbytes)
    context.set_tensor_address(output_name, int(d_output))

    # Execute
    context.execute_async_v3(stream_handle=stream.handle)
    cuda.memcpy_dtoh_async(h_output, d_output, stream)
    stream.synchronize()

    return h_output.reshape(output_shape)
```

---

## Layer Fusion and Optimization Strategies

### What TensorRT Optimizes Automatically

TensorRT performs these optimizations during engine build:

| Optimization | Description | Impact |
|-------------|-------------|--------|
| **Layer Fusion** | Combines Conv + BatchNorm + ReLU into single kernel | Reduces kernel launches, saves memory bandwidth |
| **Tensor Fusion** | Merges pointwise operations (add, multiply, activation) | Reduces memory traffic |
| **Kernel Auto-Tuning** | Tests multiple kernel implementations per layer | Selects fastest for target GPU |
| **Precision Calibration** | Determines optimal quantization scales per tensor | Minimizes accuracy loss in INT8 |
| **Memory Optimization** | Reuses memory buffers across non-overlapping tensors | Reduces peak memory usage |
| **Dead Layer Removal** | Eliminates layers with no path to output | Reduces computation |

### Manual Optimization with ONNX-GraphSurgeon

When TensorRT cannot handle certain ONNX patterns, use ONNX-GraphSurgeon to restructure the graph:

```python
import onnx_graphsurgeon as gs
import onnx
import numpy as np

# Load the ONNX model as a graph
graph = gs.import_onnx(onnx.load("model.onnx"))

# Example: Replace an unsupported custom op with a plugin
for node in graph.nodes:
    if node.op == "UnsupportedOp":
        # Replace with a TensorRT-compatible alternative
        node.op = "SupportedAlternative"
        print(f"Replaced node: {node.name}")

# Example: Fold constants
graph.fold_constants()

# Remove unused nodes
graph.cleanup()

# Topologically sort (required after modifications)
graph.toposort()

# Export modified graph
onnx.save(gs.export_onnx(graph), "model_modified.onnx")
```

### Optimization Tips for Specific Architectures

**Convolution-Heavy Models (ResNet, EfficientNet, MobileNet):**
- FP16 gives best performance/accuracy tradeoff
- Layer fusion handles Conv-BN-ReLU automatically
- Depthwise separable convolutions (MobileNet) benefit heavily from TensorRT

**Transformer Models (ViT, BERT):**
- Attention layers require explicit batch dimension handling
- Use `--fp16` for self-attention; INT8 often degrades attention quality
- Set large workspace: `--memPoolSize=workspace:4096MiB`
- Consider TensorRT's native attention plugin for better performance

**Detection Models (YOLO, SSD, EfficientDet):**
- NMS (Non-Maximum Suppression) layers may need custom handling
- For YOLOv8, use the Ultralytics export which includes TensorRT-compatible NMS
- Dynamic shape support is critical for multi-resolution input
- Anchor-free models (YOLOv8) convert more cleanly than anchor-based

---

## Common Model Conversions

### YOLOv8 (Detection)

```python
from ultralytics import YOLO

# Export to ONNX
model = YOLO("yolov8n.pt")
model.export(format="onnx", imgsz=640, opset=17, simplify=True)

# Then on the Jetson:
# trtexec --onnx=yolov8n.onnx --saveEngine=yolov8n.engine --fp16
```

Or use the Ultralytics built-in TensorRT export (must run on Jetson):

```python
from ultralytics import YOLO

model = YOLO("yolov8n.pt")
model.export(format="engine", imgsz=640, half=True, device=0)
# Produces yolov8n.engine directly
```

### ResNet (Classification)

```python
import torch
import torchvision.models as models

model = models.resnet50(weights=models.ResNet50_Weights.DEFAULT)
model.set_mode_eval()

dummy = torch.randn(1, 3, 224, 224)
torch.onnx.export(
    model, dummy, "resnet50.onnx",
    opset_version=17,
    input_names=["input"],
    output_names=["output"]
)

# On Jetson:
# trtexec --onnx=resnet50.onnx --saveEngine=resnet50.engine --fp16
```

### EfficientNet (Classification)

```python
import torch
import torchvision.models as models

model = models.efficientnet_b0(weights=models.EfficientNet_B0_Weights.DEFAULT)
model.set_mode_eval()

dummy = torch.randn(1, 3, 224, 224)
torch.onnx.export(
    model, dummy, "efficientnet_b0.onnx",
    opset_version=17,
    input_names=["input"],
    output_names=["output"]
)
```

### MobileNetV3 (Lightweight Classification)

```python
import torch
import torchvision.models as models

model = models.mobilenet_v3_small(weights=models.MobileNet_V3_Small_Weights.DEFAULT)
model.set_mode_eval()

dummy = torch.randn(1, 3, 224, 224)
torch.onnx.export(
    model, dummy, "mobilenetv3_small.onnx",
    opset_version=17,
    input_names=["input"],
    output_names=["output"]
)

# MobileNetV3 benefits enormously from TensorRT on Orin Nano:
# FP32: ~15ms, FP16: ~4ms, INT8: ~2ms (approximate)
```

### Semantic Segmentation (DeepLabV3)

```python
import torch
import torchvision.models.segmentation as seg

model = seg.deeplabv3_resnet50(weights=seg.DeepLabV3_ResNet50_Weights.DEFAULT)
model.set_mode_eval()

dummy = torch.randn(1, 3, 512, 512)
torch.onnx.export(
    model, dummy, "deeplabv3.onnx",
    opset_version=17,
    input_names=["input"],
    output_names=["output"]
)
```

---

## Benchmarking and Profiling

### Benchmarking with trtexec

```bash
# Comprehensive benchmark
trtexec \
    --loadEngine=model.engine \
    --iterations=1000 \
    --warmUp=5000 \
    --duration=60 \
    --percentile=50,90,95,99 \
    --avgRuns=100 \
    --verbose 2>&1 | tee benchmark_results.txt
```

### Python Benchmarking Script

```python
import tensorrt as trt
import pycuda.driver as cuda
import pycuda.autoinit
import numpy as np
import time


def benchmark_engine(
    engine_path: str,
    input_shape: tuple,
    num_iterations: int = 1000,
    warmup_iterations: int = 50
):
    """Benchmark a TensorRT engine.

    Args:
        engine_path: Path to the TensorRT engine file.
        input_shape: Shape of the input tensor.
        num_iterations: Number of inference iterations to measure.
        warmup_iterations: Number of warmup iterations before measuring.

    Returns:
        Dictionary with latency statistics.
    """
    logger = trt.Logger(trt.Logger.WARNING)
    runtime = trt.Runtime(logger)

    with open(engine_path, "rb") as f:
        engine = runtime.deserialize_cuda_engine(f.read())

    context = engine.create_execution_context()
    stream = cuda.Stream()

    # Allocate input
    input_data = np.random.randn(*input_shape).astype(np.float32)
    d_input = cuda.mem_alloc(input_data.nbytes)
    input_name = engine.get_tensor_name(0)
    context.set_tensor_address(input_name, int(d_input))

    # Allocate output
    output_name = engine.get_tensor_name(1)
    output_shape = engine.get_tensor_shape(output_name)
    output_dtype = trt.nptype(engine.get_tensor_dtype(output_name))
    h_output = cuda.pagelocked_empty(trt.volume(output_shape), output_dtype)
    d_output = cuda.mem_alloc(h_output.nbytes)
    context.set_tensor_address(output_name, int(d_output))

    # Copy input to device
    cuda.memcpy_htod(d_input, input_data)

    # Warmup
    print(f"Warming up ({warmup_iterations} iterations)...")
    for _ in range(warmup_iterations):
        context.execute_async_v3(stream_handle=stream.handle)
    stream.synchronize()

    # Benchmark
    print(f"Benchmarking ({num_iterations} iterations)...")
    latencies = []
    for _ in range(num_iterations):
        start = time.perf_counter()
        context.execute_async_v3(stream_handle=stream.handle)
        stream.synchronize()
        end = time.perf_counter()
        latencies.append((end - start) * 1000)  # Convert to ms

    latencies = np.array(latencies)
    results = {
        "mean_ms": np.mean(latencies),
        "std_ms": np.std(latencies),
        "min_ms": np.min(latencies),
        "max_ms": np.max(latencies),
        "p50_ms": np.percentile(latencies, 50),
        "p90_ms": np.percentile(latencies, 90),
        "p95_ms": np.percentile(latencies, 95),
        "p99_ms": np.percentile(latencies, 99),
        "throughput_fps": 1000.0 / np.mean(latencies),
    }

    print(f"\nResults ({engine_path}):")
    print(f"  Mean:       {results['mean_ms']:.2f} ms")
    print(f"  Std:        {results['std_ms']:.2f} ms")
    print(f"  P50:        {results['p50_ms']:.2f} ms")
    print(f"  P95:        {results['p95_ms']:.2f} ms")
    print(f"  P99:        {results['p99_ms']:.2f} ms")
    print(f"  Min:        {results['min_ms']:.2f} ms")
    print(f"  Max:        {results['max_ms']:.2f} ms")
    print(f"  Throughput: {results['throughput_fps']:.1f} FPS")

    return results


if __name__ == "__main__":
    results = benchmark_engine(
        engine_path="resnet50_fp16.engine",
        input_shape=(1, 3, 224, 224),
        num_iterations=1000,
        warmup_iterations=50
    )
```

### Monitoring with tegrastats During Benchmark

```bash
# Start tegrastats logging in background
tegrastats --interval 1000 --logfile tegrastats.log &

# Run your benchmark
python3 benchmark.py

# Stop tegrastats
kill %1

# Parse tegrastats output
# Fields: RAM, SWAP, CPU usage per core, GPU%, GPU freq, temperatures, power
```

### Parsing tegrastats Output

```python
import re


def parse_tegrastats_line(line: str) -> dict:
    """Parse a single tegrastats output line into structured data.

    Args:
        line: A single line from tegrastats output.

    Returns:
        Dictionary with parsed metrics.
    """
    metrics = {}

    # RAM: 3456/7620MB
    ram_match = re.search(r"RAM (\d+)/(\d+)MB", line)
    if ram_match:
        metrics["ram_used_mb"] = int(ram_match.group(1))
        metrics["ram_total_mb"] = int(ram_match.group(2))

    # GR3D_FREQ: 76%
    gpu_match = re.search(r"GR3D_FREQ (\d+)%", line)
    if gpu_match:
        metrics["gpu_util_pct"] = int(gpu_match.group(1))

    # CPU temperatures
    temp_matches = re.findall(r"(\w+)@(\d+\.?\d*)C", line)
    for name, temp in temp_matches:
        metrics[f"temp_{name.lower()}_c"] = float(temp)

    # Power: VDD_IN 5432mW/5432mW
    power_matches = re.findall(r"(\w+) (\d+)mW/(\d+)mW", line)
    for name, current, average in power_matches:
        metrics[f"power_{name.lower()}_mw"] = int(current)
        metrics[f"power_{name.lower()}_avg_mw"] = int(average)

    return metrics
```

---

## Troubleshooting

### Unsupported ONNX Operations

```
Problem: "UnsupportedOperation" or "Layer not found" during engine build.

Root Cause: The ONNX model uses operations not supported by the installed
TensorRT version.

Diagnosis:
1. Check which op is unsupported (build log will name it)
2. Check TensorRT support matrix for your version

Solutions (in order of preference):
1. Simplify ONNX model: python3 -m onnxsim model.onnx model_sim.onnx
2. Use a lower opset version when exporting from PyTorch
3. Use ONNX-GraphSurgeon to replace the unsupported op
4. Write a TensorRT plugin for the custom op (advanced)
5. Fall back to ONNX Runtime for that specific model
```

### Accuracy Loss After Conversion

```
Problem: TensorRT engine produces different results than original model.

Diagnosis:
1. Compare FP32 TensorRT engine output vs. original framework output
   - If FP32 TensorRT matches: precision issue
   - If FP32 TensorRT differs: conversion issue

2. For precision issues (FP16/INT8):
   - Check per-layer output differences
   - Identify which layers have largest drift

Solutions:
1. FP16 accuracy loss:
   - Usually negligible (less than 0.1% for most models)
   - If significant, check for very large or very small values
   - Try mixed precision: mark sensitive layers as FP32

2. INT8 accuracy loss:
   - Verify calibration dataset is representative
   - Increase calibration dataset size (1000+ images)
   - Try different calibration algorithms:
     - IInt8EntropyCalibrator2 (default, usually best)
     - IInt8MinMaxCalibrator (conservative, less loss)
   - Mark sensitive layers as FP16 using layer precision API
```

### Out of Memory During Engine Build

```
Problem: "CUDA out of memory" during trtexec or Python API engine build.

Root Cause: Building engines requires significant temporary memory for
kernel auto-tuning, especially with large models.

Solutions:
1. Reduce workspace size: --memPoolSize=workspace:512MiB
2. Close all other GPU-using processes
3. Disable GUI: sudo systemctl set-default multi-user.target and reboot
4. Build with smaller batch size, then use dynamic batching at runtime
5. For very large models, build the engine on a system with more
   memory (e.g., AGX Orin or desktop GPU) with the
   --hardwareCompatibilityLevel flag, then transfer to Orin Nano
```

### Engine Not Portable Between Devices

```
Problem: Engine built on one Jetson fails to load on another.

Root Cause: TensorRT engines are specific to:
  - GPU architecture (SM version)
  - TensorRT version
  - CUDA version
  - cuDNN version

Solutions:
1. Build engine on the target device (recommended)
2. If building on a different device:
   - Same Jetson model + same JetPack version = compatible
   - Different Jetson model = NOT compatible (must rebuild)
   - Same model + different JetPack = NOT compatible (must rebuild)
3. Use ONNX as the portable format; build TensorRT engine at deploy time
4. Implement a first-run engine build in your deployment script:
   if not engine_exists:
       build_engine_from_onnx()  # One-time cost at first deployment
```

### Slow First Inference

```
Problem: First inference after loading engine takes much longer
than subsequent ones.

Root Cause: CUDA context initialization, memory allocation, and kernel
loading happen on first inference.

Solutions:
1. Always run warmup iterations before measuring:
   for _ in range(50):
       engine.infer(dummy_input)
2. Pre-warm the engine during application startup
3. Use a persistent service that stays loaded (Docker with restart policy)
4. Accept the one-time cost and document it as "cold start latency"
```

---

## Memory Management on Orin Nano

### Memory Budget

The Orin Nano 8GB has unified memory shared between CPU and GPU:

```
Total Memory: 8192 MB
  OS + Drivers:           ~800 MB
  Desktop (if running):   ~800 MB
  CUDA Runtime:           ~200 MB
  TensorRT Runtime:       ~100-300 MB
  Model Weights:          varies
  Input/Output Buffers:   varies
  Available for App:      ~5000-6000 MB (headless)
                          ~4000-5000 MB (with desktop)
```

### Reducing Memory Usage

```python
import tensorrt as trt

# 1. Use FP16 precision (halves weight memory)

# 2. Reduce workspace during build
config = builder.create_builder_config()
config.set_memory_pool_limit(
    trt.MemoryPoolType.WORKSPACE,
    512 * (1 << 20)  # 512 MB instead of default
)

# 3. Use static batch size (avoids allocating for max batch)

# 4. Share CUDA streams and contexts across models

# 5. Unload models when not in use
del context
del engine
import gc
gc.collect()

# 6. Monitor memory usage
import subprocess
result = subprocess.run(
    ["tegrastats", "--interval", "100"],
    capture_output=True, text=True, timeout=1
)
```

---

## Best Practices Summary

```
TENSORRT OPTIMIZATION CHECKLIST
┌──────────────────────────────────────────────────────────────────┐
│ [ ] Export model to ONNX with highest supported opset           │
│ [ ] Validate ONNX model with onnx.checker                      │
│ [ ] Simplify ONNX model with onnxsim                           │
│ [ ] Build engine ON the target Jetson device                    │
│ [ ] Start with FP16 precision (default for Orin Nano)           │
│ [ ] Benchmark with trtexec before writing custom inference code │
│ [ ] Run warmup iterations before measuring latency              │
│ [ ] Lock clocks and set power mode before benchmarking          │
│ [ ] Compare accuracy against FP32 baseline                      │
│ [ ] Monitor memory usage to ensure headroom                     │
│ [ ] Profile thermal behavior under sustained load               │
│ [ ] Try INT8 only if FP16 does not meet latency target          │
│ [ ] Use calibration dataset of 500-1000 representative images   │
│ [ ] Store ONNX as portable format; build engine at deploy time  │
│ [ ] Document precision, input shape, and TensorRT version       │
└──────────────────────────────────────────────────────────────────┘
```
