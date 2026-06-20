# Capture and Publish Patterns

## Overview

Camera capture and result publishing are the bookends of every edge CV pipeline.
This reference covers every pattern for getting frames in and results out on
Jetson and Raspberry Pi hardware.

## Dependencies

```bash
# Core capture and publish
pip install opencv-python-headless numpy paho-mqtt requests

# Raspberry Pi camera (RPi only)
pip install picamera2

# WebSocket publishing
pip install websockets

# GStreamer (Jetson -- installed with JetPack)
# sudo apt-get install gstreamer1.0-tools gstreamer1.0-plugins-good
```

---

## Camera Capture Patterns

### OpenCV VideoCapture (USB Camera)

The simplest capture method. Works on all platforms.

```python
import cv2

def capture_usb_camera(device_index=0, width=640, height=480, fps=30):
    """Open USB camera with specified resolution and FPS."""
    cap = cv2.VideoCapture(device_index)

    if not cap.isOpened():
        raise RuntimeError(f"Cannot open camera at index {device_index}")

    cap.set(cv2.CAP_PROP_FRAME_WIDTH, width)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, height)
    cap.set(cv2.CAP_PROP_FPS, fps)

    # Verify actual settings (camera may not support requested values)
    actual_w = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    actual_h = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    actual_fps = cap.get(cv2.CAP_PROP_FPS)
    print(f"Camera opened: {actual_w}x{actual_h} @ {actual_fps} fps")

    return cap


def capture_loop(cap, process_fn, max_frames=None):
    """Main capture loop with frame processing callback."""
    frame_count = 0
    while True:
        ret, frame = cap.read()
        if not ret:
            print("Camera read failed")
            break

        process_fn(frame, frame_count)
        frame_count += 1

        if max_frames and frame_count >= max_frames:
            break

    cap.release()
```

### OpenCV with Device Path (Linux)

USB device indices can change on reboot. Use device paths for reliability.

```python
import cv2
import glob

def find_camera_device(preferred="/dev/video0"):
    """Find available camera device path."""
    devices = sorted(glob.glob("/dev/video*"))
    if preferred in devices:
        return preferred
    if devices:
        return devices[0]
    raise RuntimeError("No video devices found")


def capture_by_path(device_path="/dev/video0", width=640, height=480):
    """Open camera by device path instead of index."""
    cap = cv2.VideoCapture(device_path, cv2.CAP_V4L2)

    if not cap.isOpened():
        raise RuntimeError(f"Cannot open camera at {device_path}")

    cap.set(cv2.CAP_PROP_FRAME_WIDTH, width)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, height)

    # Set MJPEG format for higher FPS on USB cameras
    cap.set(cv2.CAP_PROP_FOURCC, cv2.VideoWriter_fourcc(*"MJPG"))

    return cap
```

### GStreamer Pipeline (Jetson CSI Camera)

Jetson CSI cameras require GStreamer pipelines through `nvarguscamerasrc`.

```python
import cv2

def gstreamer_pipeline_jetson(
    sensor_id=0,
    capture_width=1920,
    capture_height=1080,
    display_width=640,
    display_height=480,
    framerate=30,
    flip_method=0,
):
    """Build GStreamer pipeline string for Jetson CSI camera."""
    return (
        f"nvarguscamerasrc sensor-id={sensor_id} ! "
        f"video/x-raw(memory:NVMM), "
        f"width=(int){capture_width}, height=(int){capture_height}, "
        f"framerate=(fraction){framerate}/1 ! "
        f"nvvidconv flip-method={flip_method} ! "
        f"video/x-raw, width=(int){display_width}, height=(int){display_height}, "
        f"format=(string)BGRx ! "
        f"videoconvert ! "
        f"video/x-raw, format=(string)BGR ! "
        f"appsink drop=1"
    )


def capture_jetson_csi(sensor_id=0, width=640, height=480, fps=30):
    """Open Jetson CSI camera via GStreamer."""
    pipeline = gstreamer_pipeline_jetson(
        sensor_id=sensor_id,
        display_width=width,
        display_height=height,
        framerate=fps,
    )
    cap = cv2.VideoCapture(pipeline, cv2.CAP_GSTREAMER)

    if not cap.isOpened():
        raise RuntimeError("Failed to open Jetson CSI camera via GStreamer")

    print(f"Jetson CSI camera opened: {width}x{height} @ {fps} fps")
    return cap
```

### GStreamer Pipeline (RTSP / IP Camera)

```python
import cv2

def gstreamer_pipeline_rtsp(
    rtsp_url,
    display_width=640,
    display_height=480,
    latency=200,
):
    """Build GStreamer pipeline for RTSP IP camera stream."""
    return (
        f"rtspsrc location={rtsp_url} latency={latency} ! "
        f"rtph264depay ! h264parse ! nvv4l2decoder ! "
        f"nvvidconv ! "
        f"video/x-raw, width=(int){display_width}, height=(int){display_height}, "
        f"format=(string)BGRx ! "
        f"videoconvert ! "
        f"video/x-raw, format=(string)BGR ! "
        f"appsink drop=1"
    )


def capture_rtsp(rtsp_url, width=640, height=480):
    """Open RTSP stream. Works on Jetson with hardware decode."""
    pipeline = gstreamer_pipeline_rtsp(rtsp_url, width, height)
    cap = cv2.VideoCapture(pipeline, cv2.CAP_GSTREAMER)

    if not cap.isOpened():
        # Fallback to OpenCV RTSP (software decode)
        print("GStreamer failed, falling back to OpenCV RTSP")
        cap = cv2.VideoCapture(rtsp_url)

    if not cap.isOpened():
        raise RuntimeError(f"Cannot open RTSP stream: {rtsp_url}")

    return cap
```

### picamera2 (Raspberry Pi CSI Camera)

```python
from picamera2 import Picamera2
import numpy as np

def capture_picamera2(width=640, height=480, format="RGB888"):
    """Open Raspberry Pi CSI camera using picamera2."""
    picam2 = Picamera2()

    config = picam2.create_preview_configuration(
        main={"size": (width, height), "format": format},
    )
    picam2.configure(config)
    picam2.start()

    return picam2


def picamera2_capture_loop(picam2, process_fn, max_frames=None):
    """Capture loop using picamera2."""
    frame_count = 0
    try:
        while True:
            # Returns numpy array in configured format
            frame = picam2.capture_array()
            process_fn(frame, frame_count)
            frame_count += 1

            if max_frames and frame_count >= max_frames:
                break
    finally:
        picam2.stop()


# picamera2 with manual exposure control
def configure_picamera2_manual(picam2, exposure_us=10000, gain=1.0):
    """Lock exposure and gain for consistent inference inputs."""
    from libcamera import controls

    picam2.set_controls({
        "ExposureTime": exposure_us,
        "AnalogueGain": gain,
        "AwbEnable": False,       # Disable auto white balance
        "AeEnable": False,        # Disable auto exposure
    })
```

---

## Threaded Capture Patterns

### Basic Threaded Capture

Decouples camera I/O from processing to prevent frame stalls.

```python
import cv2
import time
from threading import Thread, Event
from queue import Queue


class ThreadedCapture:
    """Threaded camera capture with bounded queue and drop policy."""

    def __init__(self, source, queue_size=2):
        self.source = source
        self.cap = cv2.VideoCapture(source)
        if not self.cap.isOpened():
            raise RuntimeError(f"Cannot open camera: {source}")

        self.queue = Queue(maxsize=queue_size)
        self.stopped = Event()
        self.frame_count = 0

    def start(self):
        """Start the capture thread."""
        thread = Thread(target=self._capture_loop, daemon=True)
        thread.start()
        return self

    def _capture_loop(self):
        """Continuously read frames into the queue."""
        while not self.stopped.is_set():
            ret, frame = self.cap.read()
            if not ret:
                print("Camera read failed in capture thread")
                self.stopped.set()
                break

            # Drop oldest frame if queue is full (non-blocking)
            if self.queue.full():
                try:
                    self.queue.get_nowait()
                except Exception:
                    pass

            self.queue.put(frame)
            self.frame_count += 1

    def read(self, timeout=5.0):
        """Get the latest frame. Blocks up to timeout seconds."""
        if self.stopped.is_set():
            raise RuntimeError("Capture thread has stopped")
        return self.queue.get(timeout=timeout)

    def is_alive(self):
        """Check if capture is still running."""
        return not self.stopped.is_set()

    def stop(self):
        """Stop capture and release resources."""
        self.stopped.set()
        self.cap.release()


# Usage
capture = ThreadedCapture("/dev/video0", queue_size=2).start()
try:
    while capture.is_alive():
        frame = capture.read()
        # process frame...
finally:
    capture.stop()
```

### Double-Buffered Capture

For scenarios where you need the absolute latest frame (no queue delay).

```python
import cv2
import numpy as np
from threading import Thread, Lock, Event


class DoubleBufferedCapture:
    """Always provides the most recent frame, no queuing."""

    def __init__(self, source, width=640, height=480):
        self.cap = cv2.VideoCapture(source)
        if not self.cap.isOpened():
            raise RuntimeError(f"Cannot open camera: {source}")

        self.cap.set(cv2.CAP_PROP_FRAME_WIDTH, width)
        self.cap.set(cv2.CAP_PROP_FRAME_HEIGHT, height)

        self.frame = None
        self.lock = Lock()
        self.stopped = Event()
        self.new_frame = Event()

    def start(self):
        Thread(target=self._reader, daemon=True).start()
        return self

    def _reader(self):
        while not self.stopped.is_set():
            ret, frame = self.cap.read()
            if not ret:
                self.stopped.set()
                break
            with self.lock:
                self.frame = frame
            self.new_frame.set()

    def read(self, timeout=5.0):
        """Get the most recent frame."""
        if not self.new_frame.wait(timeout=timeout):
            raise TimeoutError("No new frame within timeout")
        self.new_frame.clear()
        with self.lock:
            return self.frame.copy()

    def stop(self):
        self.stopped.set()
        self.cap.release()
```

### Frame Skip Capture

Process every Nth frame to reduce inference load while maintaining capture rate.

```python
import cv2
from threading import Thread, Event
from queue import Queue


class FrameSkipCapture:
    """Capture all frames but only enqueue every Nth for processing."""

    def __init__(self, source, process_every_n=3, queue_size=2):
        self.cap = cv2.VideoCapture(source)
        if not self.cap.isOpened():
            raise RuntimeError(f"Cannot open: {source}")

        self.process_every_n = process_every_n
        self.queue = Queue(maxsize=queue_size)
        self.stopped = Event()
        self.total_captured = 0
        self.total_enqueued = 0

    def start(self):
        Thread(target=self._reader, daemon=True).start()
        return self

    def _reader(self):
        count = 0
        while not self.stopped.is_set():
            ret, frame = self.cap.read()
            if not ret:
                self.stopped.set()
                break

            self.total_captured += 1
            count += 1

            if count >= self.process_every_n:
                count = 0
                if not self.queue.full():
                    self.queue.put(frame)
                    self.total_enqueued += 1

    def read(self, timeout=5.0):
        return self.queue.get(timeout=timeout)

    def stats(self):
        return {
            "captured": self.total_captured,
            "enqueued": self.total_enqueued,
            "skip_ratio": f"1/{self.process_every_n}",
        }

    def stop(self):
        self.stopped.set()
        self.cap.release()
```

---

## Resolution and FPS Configuration

### Query Supported Resolutions

```python
import cv2
import subprocess


def query_v4l2_formats(device="/dev/video0"):
    """Query supported formats via v4l2-ctl (Linux only)."""
    result = subprocess.run(
        ["v4l2-ctl", "--device", device, "--list-formats-ext"],
        capture_output=True, text=True
    )
    print(result.stdout)
    return result.stdout


def test_resolution(device, width, height, fps=30):
    """Test if a specific resolution is supported."""
    cap = cv2.VideoCapture(device)
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, width)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, height)
    cap.set(cv2.CAP_PROP_FPS, fps)

    actual_w = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    actual_h = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    actual_fps = cap.get(cv2.CAP_PROP_FPS)

    supported = (actual_w == width and actual_h == height)
    cap.release()

    return {
        "requested": f"{width}x{height}@{fps}",
        "actual": f"{actual_w}x{actual_h}@{actual_fps}",
        "supported": supported,
    }


# Common edge-friendly resolutions to test
EDGE_RESOLUTIONS = [
    (320, 240),   # QVGA -- fast, low detail
    (640, 480),   # VGA -- balanced
    (1280, 720),  # HD -- high detail, slower
    (1920, 1080), # FHD -- only if needed for annotation overlay
]
```

### Lock Camera Settings for Consistency

```python
import cv2

def lock_camera_settings(cap):
    """Disable auto-exposure, auto-WB for consistent frames."""
    # Disable auto exposure (V4L2)
    cap.set(cv2.CAP_PROP_AUTO_EXPOSURE, 1)  # 1 = manual, 3 = auto
    cap.set(cv2.CAP_PROP_EXPOSURE, -6)       # Adjust for your lighting

    # Disable auto white balance
    cap.set(cv2.CAP_PROP_AUTO_WB, 0)
    cap.set(cv2.CAP_PROP_WB_TEMPERATURE, 4500)

    # Set fixed gain
    cap.set(cv2.CAP_PROP_GAIN, 0)

    # Verify
    print(f"Exposure: {cap.get(cv2.CAP_PROP_EXPOSURE)}")
    print(f"Auto exposure: {cap.get(cv2.CAP_PROP_AUTO_EXPOSURE)}")
    print(f"WB temp: {cap.get(cv2.CAP_PROP_WB_TEMPERATURE)}")
```

---

## Result Publishing Patterns

### MQTT Publishing

Lightweight, low-latency, ideal for edge-to-cloud or edge-to-edge communication.

```python
import json
import time
import paho.mqtt.client as mqtt


class MQTTPublisher:
    """Publish detection results over MQTT."""

    def __init__(self, broker="localhost", port=1883, topic="cv/detections",
                 client_id="edge-cv-pipeline", qos=0):
        self.topic = topic
        self.qos = qos

        self.client = mqtt.Client(client_id=client_id)
        self.client.on_connect = self._on_connect
        self.client.on_disconnect = self._on_disconnect
        self.connected = False

        self.client.connect_async(broker, port)
        self.client.loop_start()

    def _on_connect(self, client, userdata, flags, rc):
        if rc == 0:
            self.connected = True
            print(f"MQTT connected to broker")
        else:
            print(f"MQTT connection failed: rc={rc}")

    def _on_disconnect(self, client, userdata, rc):
        self.connected = False
        print(f"MQTT disconnected: rc={rc}")

    def publish_detections(self, detections, frame_id=None, timestamp=None):
        """Publish detection results as JSON."""
        payload = {
            "frame_id": frame_id,
            "timestamp": timestamp or time.time(),
            "detection_count": len(detections),
            "detections": detections,
        }
        self.client.publish(
            self.topic,
            json.dumps(payload),
            qos=self.qos,
        )

    def publish_heartbeat(self, fps, latency_ms, temperature_c=None):
        """Publish pipeline health metrics."""
        payload = {
            "type": "heartbeat",
            "timestamp": time.time(),
            "fps": fps,
            "latency_ms": latency_ms,
            "temperature_c": temperature_c,
        }
        self.client.publish(
            f"{self.topic}/health",
            json.dumps(payload),
            qos=0,
        )

    def stop(self):
        self.client.loop_stop()
        self.client.disconnect()


# Usage
publisher = MQTTPublisher(broker="192.168.1.100", topic="robot/vision")
publisher.publish_detections([
    {"class_id": 1, "confidence": 0.92, "bbox": [100, 50, 300, 250]},
])
```

### HTTP/REST Publishing

For sending results to a REST API endpoint.

```python
import json
import time
import requests
from threading import Thread
from queue import Queue


class HTTPPublisher:
    """Publish results via HTTP POST with async batching."""

    def __init__(self, endpoint_url, batch_size=5, timeout=2.0):
        self.endpoint_url = endpoint_url
        self.batch_size = batch_size
        self.timeout = timeout
        self.queue = Queue(maxsize=100)
        self.stopped = False

        Thread(target=self._sender_loop, daemon=True).start()

    def _sender_loop(self):
        """Batch and send results asynchronously."""
        batch = []
        while not self.stopped:
            try:
                item = self.queue.get(timeout=1.0)
                batch.append(item)

                if len(batch) >= self.batch_size:
                    self._send_batch(batch)
                    batch = []
            except Exception:
                # Timeout -- send partial batch if any
                if batch:
                    self._send_batch(batch)
                    batch = []

    def _send_batch(self, batch):
        """Send a batch of results via HTTP POST."""
        try:
            response = requests.post(
                self.endpoint_url,
                json={"results": batch},
                timeout=self.timeout,
            )
            if response.status_code != 200:
                print(f"HTTP publish failed: {response.status_code}")
        except requests.RequestException as e:
            print(f"HTTP publish error: {e}")

    def publish(self, detections, frame_id=None):
        """Queue results for async publishing."""
        payload = {
            "frame_id": frame_id,
            "timestamp": time.time(),
            "detections": detections,
        }
        if not self.queue.full():
            self.queue.put(payload)

    def stop(self):
        self.stopped = True
```

### WebSocket Publishing

For real-time streaming of results to a web dashboard.

```python
import json
import time
import asyncio
import websockets
from threading import Thread
from queue import Queue


class WebSocketPublisher:
    """Publish results via WebSocket for real-time dashboards."""

    def __init__(self, host="0.0.0.0", port=8765):
        self.host = host
        self.port = port
        self.clients = set()
        self.queue = Queue(maxsize=50)
        self.stopped = False

        Thread(target=self._run_server, daemon=True).start()

    def _run_server(self):
        """Run WebSocket server in background thread."""
        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)
        loop.run_until_complete(self._server())

    async def _server(self):
        async with websockets.serve(self._handler, self.host, self.port):
            print(f"WebSocket server on ws://{self.host}:{self.port}")
            while not self.stopped:
                await asyncio.sleep(0.01)
                try:
                    while not self.queue.empty():
                        msg = self.queue.get_nowait()
                        if self.clients:
                            await asyncio.gather(
                                *[client.send(msg) for client in self.clients],
                                return_exceptions=True,
                            )
                except Exception:
                    pass

    async def _handler(self, websocket, path):
        self.clients.add(websocket)
        try:
            async for _ in websocket:
                pass  # We only send, not receive
        finally:
            self.clients.discard(websocket)

    def publish(self, detections, frame_id=None):
        """Queue results for WebSocket broadcast."""
        payload = json.dumps({
            "frame_id": frame_id,
            "timestamp": time.time(),
            "detections": detections,
        })
        if not self.queue.full():
            self.queue.put(payload)

    def stop(self):
        self.stopped = True
```

### File Output Publishing

For logging results to disk. Useful for offline analysis and debugging.

```python
import json
import time
import csv
from pathlib import Path


class FilePublisher:
    """Write detection results to JSON Lines or CSV files."""

    def __init__(self, output_dir="./results", format="jsonl"):
        self.output_dir = Path(output_dir)
        self.output_dir.mkdir(parents=True, exist_ok=True)
        self.format = format

        timestamp = time.strftime("%Y%m%d_%H%M%S")
        if format == "jsonl":
            self.filepath = self.output_dir / f"detections_{timestamp}.jsonl"
            self.file = open(self.filepath, "a")
        elif format == "csv":
            self.filepath = self.output_dir / f"detections_{timestamp}.csv"
            self.file = open(self.filepath, "a", newline="")
            self.writer = csv.writer(self.file)
            self.writer.writerow([
                "timestamp", "frame_id", "class_id", "confidence",
                "x_min", "y_min", "x_max", "y_max"
            ])

    def publish(self, detections, frame_id=None):
        """Write detections to file."""
        timestamp = time.time()

        if self.format == "jsonl":
            record = {
                "timestamp": timestamp,
                "frame_id": frame_id,
                "detections": detections,
            }
            self.file.write(json.dumps(record) + "\n")
            self.file.flush()

        elif self.format == "csv":
            for det in detections:
                bbox = det.get("bbox", [0, 0, 0, 0])
                self.writer.writerow([
                    timestamp, frame_id, det["class_id"], det["confidence"],
                    bbox[0], bbox[1], bbox[2], bbox[3],
                ])
            self.file.flush()

    def stop(self):
        self.file.close()
        print(f"Results saved to: {self.filepath}")
```

---

## Annotation Overlays

### Bounding Box and Label Drawing

```python
import cv2
import numpy as np

# Class label colors (BGR format for OpenCV)
COLORS = [
    (0, 255, 0),    # green
    (0, 0, 255),    # red
    (255, 0, 0),    # blue
    (0, 255, 255),  # yellow
    (255, 0, 255),  # magenta
    (255, 255, 0),  # cyan
]


def draw_detections(frame, detections, class_names=None):
    """Draw bounding boxes and labels on frame."""
    for det in detections:
        class_id = det["class_id"]
        confidence = det["confidence"]
        x_min, y_min, x_max, y_max = det["bbox"]

        color = COLORS[class_id % len(COLORS)]

        # Bounding box
        cv2.rectangle(frame, (x_min, y_min), (x_max, y_max), color, 2)

        # Label background
        label = class_names[class_id] if class_names else f"Class {class_id}"
        label_text = f"{label}: {confidence:.2f}"
        (text_w, text_h), baseline = cv2.getTextSize(
            label_text, cv2.FONT_HERSHEY_SIMPLEX, 0.5, 1
        )
        cv2.rectangle(
            frame,
            (x_min, y_min - text_h - baseline - 4),
            (x_min + text_w, y_min),
            color,
            cv2.FILLED,
        )

        # Label text
        cv2.putText(
            frame, label_text,
            (x_min, y_min - baseline - 2),
            cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 0, 0), 1,
        )

    return frame
```

### FPS Counter Overlay

```python
import cv2
import time
from collections import deque


class FPSOverlay:
    """Calculate and draw FPS on frames."""

    def __init__(self, window_size=30):
        self.timestamps = deque(maxlen=window_size)

    def tick(self):
        """Record a frame timestamp."""
        self.timestamps.append(time.perf_counter())

    def fps(self):
        """Calculate current FPS from recent timestamps."""
        if len(self.timestamps) < 2:
            return 0.0
        elapsed = self.timestamps[-1] - self.timestamps[0]
        if elapsed == 0:
            return 0.0
        return (len(self.timestamps) - 1) / elapsed

    def draw(self, frame, position=(10, 30)):
        """Draw FPS counter on frame."""
        fps_text = f"FPS: {self.fps():.1f}"
        cv2.putText(
            frame, fps_text, position,
            cv2.FONT_HERSHEY_SIMPLEX, 0.8, (0, 255, 0), 2,
        )
        return frame


# Usage in pipeline loop
fps_counter = FPSOverlay()
# while True:
#     frame = capture.read()
#     detections = process(frame)
#     fps_counter.tick()
#     frame = draw_detections(frame, detections)
#     frame = fps_counter.draw(frame)
```

### Multi-Info HUD Overlay

```python
import cv2
import time


def draw_hud(frame, fps, latency_ms, detection_count, model_name,
             device_name, temperature_c=None):
    """Draw a comprehensive heads-up display on the frame."""
    h, w = frame.shape[:2]

    # Semi-transparent background bar
    overlay = frame.copy()
    cv2.rectangle(overlay, (0, 0), (w, 90), (0, 0, 0), cv2.FILLED)
    cv2.addWeighted(overlay, 0.6, frame, 0.4, 0, frame)

    # Line 1: FPS and latency
    line1 = f"FPS: {fps:.1f} | Latency: {latency_ms:.1f}ms"
    cv2.putText(frame, line1, (10, 25),
                cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 255, 0), 1)

    # Line 2: Model and device
    line2 = f"Model: {model_name} | Device: {device_name}"
    cv2.putText(frame, line2, (10, 50),
                cv2.FONT_HERSHEY_SIMPLEX, 0.6, (200, 200, 200), 1)

    # Line 3: Detections and temperature
    temp_str = f" | Temp: {temperature_c:.0f}C" if temperature_c else ""
    line3 = f"Detections: {detection_count}{temp_str}"
    cv2.putText(frame, line3, (10, 75),
                cv2.FONT_HERSHEY_SIMPLEX, 0.6, (200, 200, 200), 1)

    return frame
```

---

## Video Recording While Processing

### Record Annotated Output

```python
import cv2
import time


class VideoRecorder:
    """Record annotated frames to video file while pipeline runs."""

    def __init__(self, output_path, fps=15, resolution=(640, 480),
                 codec="XVID"):
        fourcc = cv2.VideoWriter_fourcc(*codec)
        self.writer = cv2.VideoWriter(
            output_path, fourcc, fps, resolution
        )
        self.frame_count = 0
        if not self.writer.isOpened():
            raise RuntimeError(f"Cannot open video writer: {output_path}")
        print(f"Recording to: {output_path}")

    def write(self, frame):
        """Write an annotated frame to the video file."""
        self.writer.write(frame)
        self.frame_count += 1

    def stop(self):
        self.writer.release()
        print(f"Recording stopped. {self.frame_count} frames written.")


# Usage: record annotated frames
# recorder = VideoRecorder("output.avi", fps=15, resolution=(640, 480))
# while running:
#     frame = capture.read()
#     detections = process(frame)
#     annotated = draw_detections(frame, detections)
#     recorder.write(annotated)
# recorder.stop()
```

### Record Raw + Process Separately

```python
import cv2
import time
from threading import Thread
from queue import Queue


class AsyncVideoRecorder:
    """Record raw frames asynchronously to avoid blocking pipeline."""

    def __init__(self, output_path, fps=30, resolution=(640, 480)):
        fourcc = cv2.VideoWriter_fourcc(*"XVID")
        self.writer = cv2.VideoWriter(output_path, fourcc, fps, resolution)
        self.queue = Queue(maxsize=60)  # Buffer 2 seconds at 30 fps
        self.stopped = False
        Thread(target=self._writer_loop, daemon=True).start()

    def _writer_loop(self):
        while not self.stopped:
            try:
                frame = self.queue.get(timeout=1.0)
                self.writer.write(frame)
            except Exception:
                continue

    def record(self, frame):
        """Non-blocking frame enqueue for recording."""
        if not self.queue.full():
            self.queue.put(frame)
        # Silently drop if buffer is full

    def stop(self):
        self.stopped = True
        # Flush remaining frames
        while not self.queue.empty():
            try:
                frame = self.queue.get_nowait()
                self.writer.write(frame)
            except Exception:
                break
        self.writer.release()
```

---

## Complete Pipeline Example

Ties together capture, inference, annotation, publishing, and recording.

```python
import cv2
import time
import numpy as np
import tflite_runtime.interpreter as tflite


def run_pipeline(
    camera_source=0,
    model_path="model.tflite",
    mqtt_broker="localhost",
    mqtt_topic="cv/detections",
    input_size=(320, 320),
    confidence_threshold=0.5,
    target_fps=15,
):
    """Complete edge CV pipeline with all stages."""
    # -- Setup --
    capture = ThreadedCapture(camera_source, queue_size=2).start()

    interpreter = tflite.Interpreter(model_path=model_path, num_threads=4)
    interpreter.allocate_tensors()
    input_details = interpreter.get_input_details()
    output_details = interpreter.get_output_details()

    publisher = MQTTPublisher(broker=mqtt_broker, topic=mqtt_topic)
    fps_counter = FPSOverlay()
    frame_id = 0

    min_frame_time = 1.0 / target_fps

    print(f"Pipeline running: {model_path} -> {mqtt_topic}")

    try:
        while capture.is_alive():
            loop_start = time.perf_counter()

            # CAPTURE
            frame = capture.read()

            # PREPROCESS
            resized = cv2.resize(frame, input_size)
            input_data = np.expand_dims(
                resized.astype(np.float32) / 255.0, axis=0
            )

            # INFER
            interpreter.set_tensor(input_details[0]["index"], input_data)
            interpreter.invoke()
            outputs = [
                interpreter.get_tensor(d["index"]) for d in output_details
            ]

            # POSTPROCESS
            detections = postprocess_detections(
                outputs,
                confidence_threshold=confidence_threshold,
                input_size=input_size,
                original_size=(frame.shape[1], frame.shape[0]),
            )

            # PUBLISH
            publisher.publish_detections(detections, frame_id=frame_id)

            # Metrics
            fps_counter.tick()
            frame_id += 1

            # Rate limiting
            elapsed = time.perf_counter() - loop_start
            if elapsed < min_frame_time:
                time.sleep(min_frame_time - elapsed)

    except KeyboardInterrupt:
        print("Pipeline stopped by user")
    finally:
        capture.stop()
        publisher.stop()
        print(f"Processed {frame_id} frames, final FPS: {fps_counter.fps():.1f}")
```

---

## Quick Reference: Camera Source Strings

| Source | OpenCV String | Notes |
|--------|--------------|-------|
| USB camera (first) | `0` or `"/dev/video0"` | Use device path for stability |
| USB camera (second) | `1` or `"/dev/video2"` | Index may not match device number |
| Jetson CSI | GStreamer pipeline string | Use `nvarguscamerasrc` |
| RTSP IP camera | `"rtsp://user:pass@ip:554/stream"` | Or via GStreamer for HW decode |
| Video file | `"/path/to/video.mp4"` | Useful for testing and replay |
| Image sequence | `"/path/to/frames/%04d.jpg"` | Sequential numbered images |
| RPi CSI | Use `picamera2` library | OpenCV V4L2 works but picamera2 is better |

## Quick Reference: Publishing Protocols

| Protocol | Latency | Throughput | Best For |
|----------|---------|------------|----------|
| MQTT QoS 0 | ~1-5ms (LAN) | High | Real-time edge-to-edge |
| MQTT QoS 1 | ~5-20ms (LAN) | Medium | Guaranteed delivery |
| HTTP POST | ~10-50ms (LAN) | Medium | REST API integration |
| WebSocket | ~1-5ms (LAN) | High | Live web dashboards |
| File (JSONL) | ~0.1ms | Highest | Offline analysis, logging |
| File (CSV) | ~0.1ms | Highest | Spreadsheet analysis |
