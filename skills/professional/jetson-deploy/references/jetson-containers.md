# Jetson Containers Reference

## Overview

The `jetson-containers` project (dustynv/jetson-containers) provides a modular system for building Docker containers optimized for NVIDIA Jetson devices. It handles the complexity of matching CUDA, TensorRT, cuDNN, and framework versions to specific JetPack/L4T releases.

**Repository**: https://github.com/dusty-nv/jetson-containers

This reference covers setup, usage, container composition, device access, and production deployment patterns for Jetson Orin Nano.

---

## Setup and Installation

### Prerequisites

Verify Docker and nvidia runtime are available on the Jetson:

```bash
# Check Docker is installed
docker --version

# Verify nvidia runtime is available
docker info | grep -i runtime
# Should show: Runtimes: nvidia runc

# If nvidia runtime is not default, set it
sudo nano /etc/docker/daemon.json
```

Configure Docker to use nvidia as default runtime:

```json
{
    "runtimes": {
        "nvidia": {
            "path": "nvidia-container-runtime",
            "runtimeArgs": []
        }
    },
    "default-runtime": "nvidia"
}
```

Restart Docker after changing configuration:

```bash
sudo systemctl restart docker
```

### Clone jetson-containers

```bash
git clone https://github.com/dusty-nv/jetson-containers
cd jetson-containers

# Install the container build tool
pip3 install -r requirements.txt
```

### Verify JetPack Detection

```bash
# The build system auto-detects JetPack version
python3 -c "from jetson_containers import L4T_VERSION; print(L4T_VERSION)"

# Should output something like: 36.3.0 (for JetPack 6.0)
```

---

## Base Images

### JetPack 6.x (L4T R36.x) Base Images

JetPack 6.x uses Ubuntu 22.04 as the base OS and ships with CUDA 12.x.

| Base Image | Contents | Use Case |
|-----------|----------|----------|
| `nvcr.io/nvidia/l4t-base:r36.3.0` | Minimal L4T with CUDA runtime | Lightweight deployments |
| `nvcr.io/nvidia/l4t-jetpack:r36.3.0` | Full JetPack (CUDA, cuDNN, TensorRT, OpenCV) | Development and prototyping |
| `nvcr.io/nvidia/l4t-tensorrt:r36.3.0` | CUDA + TensorRT | Production inference |
| `nvcr.io/nvidia/l4t-pytorch:r36.3.0` | CUDA + PyTorch + TorchVision | Training and export |
| `nvcr.io/nvidia/l4t-ml:r36.3.0` | Full ML stack (PyTorch, TF, TensorRT, ONNX) | Multi-framework development |

### JetPack 5.x (L4T R35.x) Base Images

JetPack 5.x uses Ubuntu 20.04 and ships with CUDA 11.x.

| Base Image | Contents | Use Case |
|-----------|----------|----------|
| `nvcr.io/nvidia/l4t-base:r35.4.1` | Minimal L4T with CUDA runtime | Lightweight deployments |
| `nvcr.io/nvidia/l4t-jetpack:r35.4.1` | Full JetPack | Development |
| `nvcr.io/nvidia/l4t-tensorrt:r35.4.1` | CUDA + TensorRT | Production inference |

### Selecting the Right Base Image

```
Decision Tree:

1. What JetPack version is installed?
   └─ cat /etc/nv_tegra_release
   └─ Maps to L4T version → determines base image tag

2. What do you need in the container?
   ├─ Only inference (TensorRT) → l4t-tensorrt
   ├─ PyTorch for export + TensorRT → l4t-pytorch + build TensorRT on top
   ├─ Full development stack → l4t-ml or l4t-jetpack
   └─ Minimal custom build → l4t-base

3. How much disk space is available?
   ├─ l4t-base: ~1 GB
   ├─ l4t-tensorrt: ~3 GB
   ├─ l4t-pytorch: ~6 GB
   └─ l4t-ml: ~10 GB
```

---

## Building Containers with jetson-containers

### Using the Build System

The `jetson-containers` build system uses a modular package system where you compose containers from building blocks:

```bash
# Build a container with TensorRT and OpenCV
jetson-containers build --name my-inference tensorrt opencv

# Build with PyTorch and TorchVision
jetson-containers build --name my-training pytorch torchvision

# Build with a specific combination
jetson-containers build --name my-app tensorrt opencv numpy pillow

# List available packages
jetson-containers list
```

### Package Composition

Packages can be stacked. The build system resolves dependencies automatically:

```bash
# TensorRT alone pulls in CUDA runtime
jetson-containers build tensorrt
# Resolves: l4t-base → cuda-runtime → tensorrt

# PyTorch pulls in CUDA, cuDNN, and build tools
jetson-containers build pytorch
# Resolves: l4t-base → cuda → cudnn → pytorch

# You can layer application packages on top
jetson-containers build tensorrt opencv pycuda
# Resolves: l4t-base → cuda-runtime → tensorrt → opencv → pycuda
```

### Custom Dockerfiles

For full control, write a custom Dockerfile using Jetson base images:

```dockerfile
# Use JetPack 6.0 TensorRT base
FROM nvcr.io/nvidia/l4t-tensorrt:r36.3.0

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3-pip \
    python3-dev \
    libopencv-dev \
    && rm -rf /var/lib/apt/lists/*

# Install Python packages
# Pin versions to avoid breaking JetPack system packages
RUN pip3 install --no-cache-dir \
    numpy==1.24.4 \
    pillow==10.0.0 \
    pycuda==2024.1 \
    onnx==1.14.1

# Copy application code
COPY app/ /app/
COPY models/ /models/

WORKDIR /app

# Set environment for TensorRT
ENV LD_LIBRARY_PATH=/usr/lib/aarch64-linux-gnu:${LD_LIBRARY_PATH}

CMD ["python3", "inference.py"]
```

Build the custom Dockerfile:

```bash
docker build -t my-jetson-app:latest -f Dockerfile .
```

### Multi-Stage Builds for Smaller Images

Use multi-stage builds to separate build dependencies from runtime:

```dockerfile
# Stage 1: Build stage (includes build tools)
FROM nvcr.io/nvidia/l4t-jetpack:r36.3.0 AS builder

RUN apt-get update && apt-get install -y \
    python3-pip \
    build-essential \
    cmake

# Build any custom extensions
COPY src/ /src/
RUN cd /src && pip3 install --prefix=/install .

# Stage 2: Runtime stage (minimal)
FROM nvcr.io/nvidia/l4t-tensorrt:r36.3.0

# Copy only the built artifacts
COPY --from=builder /install /usr/local

# Copy application
COPY app/ /app/
COPY models/ /models/

WORKDIR /app
CMD ["python3", "inference.py"]
```

---

## Running Containers

### Basic GPU Container Execution

```bash
# Run with nvidia runtime and GPU access
docker run --rm \
    --runtime nvidia \
    --gpus all \
    my-jetson-app:latest

# Interactive shell in container
docker run -it --rm \
    --runtime nvidia \
    --gpus all \
    my-jetson-app:latest \
    /bin/bash
```

### Using jetson-containers run

The `jetson-containers` tool provides a convenient `run` command that sets up common flags:

```bash
# Run a pre-built container
jetson-containers run $(jetson-containers build tensorrt opencv)

# Run with additional volume mounts
jetson-containers run \
    --volume /path/to/models:/models \
    --volume /path/to/data:/data \
    $(jetson-containers build tensorrt)
```

---

## Volume Mounts

### Model and Data Directories

Always mount models and data as volumes rather than baking them into the image. This allows updating models without rebuilding:

```bash
docker run --rm \
    --runtime nvidia \
    --gpus all \
    -v /home/user/models:/models:ro \
    -v /home/user/data:/data:ro \
    -v /home/user/output:/output \
    my-jetson-app:latest
```

### Device Access

Mount device files for camera, GPIO, and sensor access:

```bash
# USB camera access
docker run --rm \
    --runtime nvidia \
    --gpus all \
    --device /dev/video0:/dev/video0 \
    my-jetson-app:latest

# Multiple cameras
docker run --rm \
    --runtime nvidia \
    --gpus all \
    --device /dev/video0:/dev/video0 \
    --device /dev/video1:/dev/video1 \
    my-jetson-app:latest

# GPIO access
docker run --rm \
    --runtime nvidia \
    --gpus all \
    -v /sys/class/gpio:/sys/class/gpio \
    --device /dev/gpiochip0:/dev/gpiochip0 \
    --device /dev/gpiochip1:/dev/gpiochip1 \
    my-jetson-app:latest

# I2C device access (e.g., for IMU sensors)
docker run --rm \
    --runtime nvidia \
    --gpus all \
    --device /dev/i2c-0:/dev/i2c-0 \
    --device /dev/i2c-1:/dev/i2c-1 \
    my-jetson-app:latest

# SPI device access
docker run --rm \
    --runtime nvidia \
    --gpus all \
    --device /dev/spidev0.0:/dev/spidev0.0 \
    my-jetson-app:latest

# CSI camera (requires full /dev and /tmp access)
docker run --rm \
    --runtime nvidia \
    --gpus all \
    --privileged \
    -v /tmp/argus_socket:/tmp/argus_socket \
    my-jetson-app:latest
```

### Display Access

For applications that need display output (visualization, debugging):

```bash
docker run --rm \
    --runtime nvidia \
    --gpus all \
    -e DISPLAY=$DISPLAY \
    -v /tmp/.X11-unix:/tmp/.X11-unix \
    my-jetson-app:latest
```

### Shared Memory for High-Throughput Pipelines

DeepStream and other video pipelines require increased shared memory:

```bash
docker run --rm \
    --runtime nvidia \
    --gpus all \
    --shm-size=1g \
    my-jetson-app:latest
```

---

## Common Container Recipes

### Recipe 1: TensorRT Inference Server

Minimal container for running TensorRT engines:

```dockerfile
FROM nvcr.io/nvidia/l4t-tensorrt:r36.3.0

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3-pip \
    && rm -rf /var/lib/apt/lists/*

RUN pip3 install --no-cache-dir \
    numpy==1.24.4 \
    pycuda==2024.1

COPY inference/ /app/
WORKDIR /app

CMD ["python3", "trt_inference.py"]
```

### Recipe 2: TensorRT + OpenCV Vision Pipeline

For computer vision applications that need preprocessing and visualization:

```dockerfile
FROM nvcr.io/nvidia/l4t-tensorrt:r36.3.0

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3-pip \
    python3-opencv \
    libopencv-dev \
    && rm -rf /var/lib/apt/lists/*

RUN pip3 install --no-cache-dir \
    numpy==1.24.4 \
    pycuda==2024.1 \
    pillow==10.0.0

COPY app/ /app/
COPY models/ /models/

WORKDIR /app
CMD ["python3", "vision_pipeline.py"]
```

### Recipe 3: PyTorch Export + TensorRT Conversion

For converting models on-device:

```dockerfile
FROM nvcr.io/nvidia/l4t-pytorch:r36.3.0

RUN pip3 install --no-cache-dir \
    onnx==1.14.1 \
    onnxsim==0.4.36 \
    onnxruntime-gpu

COPY export/ /app/export/
COPY models/ /models/

WORKDIR /app
CMD ["python3", "export/convert_to_trt.py"]
```

### Recipe 4: DeepStream Video Analytics

For multi-stream video analytics pipelines:

```dockerfile
FROM nvcr.io/nvidia/deepstream-l4t:7.0-triton-multiarch

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3-pip \
    python3-gi \
    gstreamer1.0-tools \
    && rm -rf /var/lib/apt/lists/*

RUN pip3 install --no-cache-dir \
    pyds

COPY deepstream_app/ /app/
COPY configs/ /configs/
COPY models/ /models/

WORKDIR /app
CMD ["python3", "deepstream_pipeline.py"]
```

### Recipe 5: Full Development Environment

For development and debugging on-device:

```dockerfile
FROM nvcr.io/nvidia/l4t-ml:r36.3.0

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3-pip \
    vim \
    htop \
    git \
    wget \
    && rm -rf /var/lib/apt/lists/*

RUN pip3 install --no-cache-dir \
    jupyterlab \
    matplotlib \
    seaborn \
    onnx \
    onnxsim

EXPOSE 8888

CMD ["jupyter", "lab", "--ip=0.0.0.0", "--port=8888", "--allow-root", "--no-browser"]
```

---

## Docker Compose for Multi-Container Deployments

### Basic Inference Service

```yaml
# docker-compose.yml
version: '3.8'

services:
  inference:
    image: my-jetson-inference:latest
    runtime: nvidia
    restart: unless-stopped
    volumes:
      - /home/user/models:/models:ro
      - /home/user/data:/data:ro
      - /home/user/output:/output
    devices:
      - /dev/video0:/dev/video0
    environment:
      - MODEL_PATH=/models/yolov8n.engine
      - INPUT_SOURCE=/dev/video0
      - CONFIDENCE_THRESHOLD=0.5
    deploy:
      resources:
        reservations:
          devices:
            - capabilities: [gpu]
```

### Multi-Service Pipeline

```yaml
# docker-compose.yml
version: '3.8'

services:
  # Camera capture and preprocessing
  capture:
    image: my-jetson-capture:latest
    runtime: nvidia
    restart: unless-stopped
    devices:
      - /dev/video0:/dev/video0
    volumes:
      - frame_buffer:/frames
    environment:
      - CAMERA_ID=0
      - FRAME_WIDTH=1920
      - FRAME_HEIGHT=1080
      - FPS=30

  # TensorRT inference
  inference:
    image: my-jetson-inference:latest
    runtime: nvidia
    restart: unless-stopped
    depends_on:
      - capture
    volumes:
      - /home/user/models:/models:ro
      - frame_buffer:/frames:ro
      - results:/results
    environment:
      - MODEL_PATH=/models/yolov8n.engine
      - INPUT_DIR=/frames
      - OUTPUT_DIR=/results
    deploy:
      resources:
        reservations:
          devices:
            - capabilities: [gpu]

  # Results processing and output
  postprocess:
    image: my-jetson-postprocess:latest
    restart: unless-stopped
    depends_on:
      - inference
    volumes:
      - results:/results:ro
      - /home/user/output:/output
    ports:
      - "8080:8080"
    environment:
      - RESULTS_DIR=/results
      - OUTPUT_DIR=/output

  # Monitoring
  monitoring:
    image: my-jetson-monitor:latest
    restart: unless-stopped
    volumes:
      - /run/jtop.sock:/run/jtop.sock:ro
    ports:
      - "9090:9090"
    environment:
      - METRICS_PORT=9090

volumes:
  frame_buffer:
    driver: local
    driver_opts:
      type: tmpfs
      device: tmpfs
      o: size=512m
  results:
    driver: local
    driver_opts:
      type: tmpfs
      device: tmpfs
      o: size=256m
```

### Starting and Managing Compose Services

```bash
# Start all services
docker compose up -d

# View logs
docker compose logs -f inference

# Stop all services
docker compose down

# Rebuild and restart a single service
docker compose build inference
docker compose up -d inference

# View resource usage
docker compose top
docker stats
```

---

## Container Management

### Image Cleanup

Jetson devices have limited disk space. Clean up regularly:

```bash
# Remove stopped containers
docker container prune -f

# Remove unused images
docker image prune -f

# Remove all unused data (containers, images, networks, cache)
docker system prune -f

# Check disk usage
docker system df
```

### Container Health Checks

Add health checks to production containers:

```dockerfile
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD python3 /app/healthcheck.py || exit 1
```

Health check script example:

```python
#!/usr/bin/env python3
"""healthcheck.py - Verify inference pipeline is operational."""
import sys
import numpy as np

def check_inference():
    """Run a dummy inference to verify the engine is loaded."""
    try:
        import tensorrt as trt
        # Verify TensorRT is functional
        logger = trt.Logger(trt.Logger.WARNING)
        runtime = trt.Runtime(logger)
        # Check that the engine file exists and is loadable
        with open("/models/model.engine", "rb") as f:
            engine_data = f.read()
        engine = runtime.deserialize_cuda_engine(engine_data)
        if engine is None:
            return False
        return True
    except Exception:
        return False

if __name__ == "__main__":
    if check_inference():
        sys.exit(0)
    else:
        sys.exit(1)
```

---

## Networking

### Host Network Mode

For low-latency networking or when accessing local services:

```bash
docker run --rm \
    --runtime nvidia \
    --gpus all \
    --network host \
    my-jetson-app:latest
```

### Port Mapping

For services that expose APIs:

```bash
docker run --rm \
    --runtime nvidia \
    --gpus all \
    -p 8080:8080 \
    -p 8554:8554 \
    my-jetson-app:latest
```

---

## Systemd Integration

### Auto-Start Container on Boot

Create a systemd service for production deployments:

```ini
# /etc/systemd/system/jetson-inference.service
[Unit]
Description=Jetson Inference Service
Requires=docker.service
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=simple
Restart=always
RestartSec=10
ExecStartPre=-/usr/bin/docker stop jetson-inference
ExecStartPre=-/usr/bin/docker rm jetson-inference
ExecStart=/usr/bin/docker run \
    --name jetson-inference \
    --runtime nvidia \
    --gpus all \
    --device /dev/video0:/dev/video0 \
    -v /home/user/models:/models:ro \
    -v /home/user/output:/output \
    my-jetson-inference:latest
ExecStop=/usr/bin/docker stop jetson-inference

[Install]
WantedBy=multi-user.target
```

Enable and start the service:

```bash
sudo systemctl daemon-reload
sudo systemctl enable jetson-inference.service
sudo systemctl start jetson-inference.service

# Check status
sudo systemctl status jetson-inference.service

# View logs
journalctl -u jetson-inference.service -f
```

---

## Troubleshooting

### Container Cannot Access GPU

```
Problem: "nvidia-container-cli: initialization error"

Actions:
1. Verify nvidia runtime: docker info | grep -i runtime
2. Check daemon.json has nvidia runtime configured
3. Restart Docker: sudo systemctl restart docker
4. Verify NVIDIA drivers: nvidia-smi or tegrastats
5. Ensure JetPack is fully installed
```

### Base Image Pull Fails

```
Problem: "manifest for nvcr.io/nvidia/l4t-tensorrt:r36.3.0 not found"

Actions:
1. Check exact L4T version: cat /etc/nv_tegra_release
2. Browse available tags: https://catalog.ngc.nvidia.com
3. Use jetson-containers which auto-resolves correct versions
4. For offline environments, pre-pull images on a connected network
   and transfer via docker save / docker load
```

### Out of Disk Space

```
Problem: "no space left on device" during docker build

Actions:
1. Check disk usage: df -h
2. Clean Docker cache: docker system prune -f
3. Remove old images: docker image prune -a
4. Use multi-stage builds to reduce final image size
5. Consider adding external storage (NVMe SSD via M.2 slot)
6. Move Docker data directory to external storage:
   Edit /etc/docker/daemon.json:
   {"data-root": "/mnt/ssd/docker"}
```

### Package Version Conflicts

```
Problem: pip install breaks system TensorRT or CUDA packages

Actions:
1. NEVER pip install on the Jetson host system
2. Always use containers for Python package management
3. Inside containers, pin versions explicitly
4. Use --no-deps flag to prevent pulling incompatible transitive deps
5. Test package imports after installation:
   python3 -c "import tensorrt; print(tensorrt.__version__)"
```

---

## Best Practices Summary

```
CONTAINER BEST PRACTICES FOR JETSON
┌──────────────────────────────────────────────────────────────────┐
│ □ Pin base image to exact L4T version (e.g., r36.3.0)          │
│ □ Pin all pip package versions in Dockerfile                    │
│ □ Use multi-stage builds to minimize image size                 │
│ □ Mount models and data as volumes, not baked into image        │
│ □ Mount device files explicitly (not --privileged)              │
│ □ Set --runtime nvidia (or default runtime in daemon.json)      │
│ □ Include health checks in production containers                │
│ □ Use Docker Compose for multi-service deployments              │
│ □ Create systemd services for auto-start on boot                │
│ □ Clean up images regularly to preserve disk space              │
│ □ Never pip install on the host system                          │
│ □ Test GPU access inside container before deploying             │
└──────────────────────────────────────────────────────────────────┘
```
