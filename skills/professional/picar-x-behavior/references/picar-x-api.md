# Picar-X Python API Reference

## Overview

The SunFounder Picar-X is a Raspberry Pi-based robot car kit with servo-controlled steering, DC motor drive, an ultrasonic distance sensor, a 3-channel grayscale sensor for line following, and a camera with pan/tilt servos. The primary Python library is `picarx` (from the `robot-hat` package), with `vilib` providing camera/vision utilities.

## Installation

```bash
# Install robot-hat (includes picarx)
cd ~/
git clone https://github.com/sunfounder/robot-hat.git
cd robot-hat
sudo python3 setup.py install

# Install picarx
cd ~/
git clone https://github.com/sunfounder/picar-x.git
cd picar-x
sudo python3 setup.py install

# Install vilib (camera/vision)
cd ~/
git clone https://github.com/sunfounder/vilib.git
cd vilib
sudo python3 install.py
```

## Hardware Layout and Pin Assignments

```
        ┌──────────────────────────┐
        │      Camera (Pan/Tilt)   │
        │         ┌─────┐          │
        │         │ CAM │          │
        │         └──┬──┘          │
        │      Pan: P0 | Tilt: P1  │
        ├──────────────────────────┤
        │   Ultrasonic Sensor      │
        │   Trig: D2  Echo: D3    │
        ├──────────────────────────┤
        │                          │
  ┌─────┤  Left Motor    Right Motor├─────┐
  │Wheel│  DIR1: D4      DIR2: D5 │Wheel│
  │     │  PWM: P12      PWM: P13 │     │
  └─────┤                          ├─────┘
        │   Steering Servo: P2     │
        ├──────────────────────────┤
        │   Grayscale Sensor Bar   │
        │   A0 (L)  A1 (M)  A2 (R)│
        └──────────────────────────┘
```

### Pin Summary

| Component | Pin(s) | Type |
|-----------|--------|------|
| Left Motor Direction | D4 | Digital |
| Right Motor Direction | D5 | Digital |
| Left Motor PWM | P12 | PWM |
| Right Motor PWM | P13 | PWM |
| Steering Servo | P2 | Servo (PWM) |
| Camera Pan Servo | P0 | Servo (PWM) |
| Camera Tilt Servo | P1 | Servo (PWM) |
| Ultrasonic Trig | D2 | Digital |
| Ultrasonic Echo | D3 | Digital |
| Grayscale Left | A0 | Analog |
| Grayscale Middle | A1 | Analog |
| Grayscale Right | A2 | Analog |

## Core API: Picarx Class

### Initialization

```python
from picarx import Picarx

# Create the Picar-X instance
# This initializes all servos, motors, and sensors
px = Picarx()
```

The constructor sets up:
- Steering servo centered at 0 degrees
- Camera pan/tilt servos centered at 0 degrees
- Motors stopped (speed 0)
- Ultrasonic sensor ready
- Grayscale sensor ready

### Motor Control

#### `forward(speed)`
Drive both motors forward at the given speed.

- **speed**: `int`, range 0-100. Percentage of maximum motor power.
- Motor direction is adjusted for steering angle automatically.

```python
# Drive forward at 30% speed
px.forward(30)

# Drive forward at minimum test speed
px.forward(10)
```

#### `backward(speed)`
Drive both motors in reverse at the given speed.

- **speed**: `int`, range 0-100.

```python
# Reverse slowly
px.backward(20)
```

#### `stop()`
Stop both motors immediately. Sets PWM to 0 on both channels.

```python
# Emergency stop
px.stop()
```

#### `set_motor_speed(motor, speed)`
Set speed for an individual motor. Rarely used directly -- prefer `forward()` / `backward()`.

- **motor**: `int`, 1 (left) or 2 (right)
- **speed**: `int`, -100 to 100 (negative = reverse)

```python
# Differential drive (advanced)
px.set_motor_speed(1, 30)   # Left motor forward 30%
px.set_motor_speed(2, 20)   # Right motor forward 20%
```

### Steering Control

#### `set_dir_servo_angle(angle)`
Set the steering servo angle.

- **angle**: `int` or `float`, range **-35 to +35** degrees.
  - Negative = turn left
  - 0 = straight
  - Positive = turn right
- Values outside the range are clamped by the library.

```python
# Turn left 20 degrees
px.set_dir_servo_angle(-20)

# Go straight
px.set_dir_servo_angle(0)

# Turn right 30 degrees
px.set_dir_servo_angle(30)
```

**Calibration Note:** The physical center may not be exactly 0. Use `set_dir_servo_angle(0)` and observe whether the robot drives straight. Adjust with the calibration procedure if needed.

### Camera Servo Control

#### `set_cam_pan_angle(angle)`
Set the camera's horizontal (pan) servo angle.

- **angle**: `int` or `float`, range **-35 to +35** degrees.
  - Negative = pan left
  - 0 = center
  - Positive = pan right

```python
# Look left
px.set_cam_pan_angle(-30)

# Look center
px.set_cam_pan_angle(0)

# Look right
px.set_cam_pan_angle(30)
```

#### `set_cam_tilt_angle(angle)`
Set the camera's vertical (tilt) servo angle.

- **angle**: `int` or `float`, range **-35 to +35** degrees.
  - Negative = tilt down
  - 0 = level
  - Positive = tilt up

```python
# Look down at floor (for line following camera)
px.set_cam_tilt_angle(-20)

# Look level
px.set_cam_tilt_angle(0)

# Look slightly up
px.set_cam_tilt_angle(15)
```

### Ultrasonic Sensor

#### `get_distance()`
Read the ultrasonic distance sensor. Returns distance to the nearest obstacle.

- **Returns**: `float`, distance in centimeters.
  - Valid range: approximately **2 to 400 cm**
  - Returns `-1` if no echo received (timeout) or sensor error
  - Returns `-2` in some implementations for out-of-range

```python
distance = px.get_distance()

if distance < 0:
    print("Sensor error or no echo")
elif distance < 25:
    print(f"Obstacle close: {distance:.1f} cm")
else:
    print(f"Clear: {distance:.1f} cm")
```

**Timing:** Each reading takes approximately 20-60ms depending on distance. At 20 Hz control loop, ultrasonic is the bottleneck.

**Filtering pattern:**

```python
import statistics

def get_filtered_distance(px, samples=3):
    """Take multiple readings and return the median to filter noise."""
    readings = []
    for _ in range(samples):
        d = px.get_distance()
        if d > 0:
            readings.append(d)
    if not readings:
        return -1  # All readings failed
    return statistics.median(readings)
```

### Grayscale Sensor

#### `get_grayscale_data()`
Read the 3-channel grayscale sensor bar. Used for line following.

- **Returns**: `list[int]` of 3 values `[left, middle, right]`
  - Each value range: **0 to 4095** (12-bit ADC)
  - Lower values = darker surface (line)
  - Higher values = lighter surface (background)

```python
left, middle, right = px.get_grayscale_data()
print(f"Grayscale L:{left} M:{middle} R:{right}")
```

#### `get_line_status()`
Higher-level line detection using grayscale thresholds.

- **Returns**: `list` of 3 values, each `0` or `1`
  - `0` = sensor is over the line (dark)
  - `1` = sensor is off the line (light)

```python
status = px.get_line_status()
# status examples:
# [0, 1, 1] -> line is under left sensor -> turn left
# [1, 0, 1] -> line is under middle sensor -> go straight
# [1, 1, 0] -> line is under right sensor -> turn right
# [0, 0, 0] -> all on line (wide line or perpendicular crossing)
# [1, 1, 1] -> no line detected -> lost the line
```

**Threshold configuration:**

```python
# Set the threshold for line detection
# Values below threshold = on line (dark), above = off line (light)
px.set_line_reference([1000, 1000, 1000])
```

### Full Subsystem Example

```python
from picarx import Picarx
import time

px = Picarx()

try:
    # Center everything
    px.set_dir_servo_angle(0)
    px.set_cam_pan_angle(0)
    px.set_cam_tilt_angle(0)
    time.sleep(0.5)

    # Check distance
    distance = px.get_distance()
    print(f"Distance: {distance:.1f} cm")

    # Check line sensor
    grayscale = px.get_grayscale_data()
    print(f"Grayscale: {grayscale}")

    # Drive forward slowly if clear
    if distance > 30:
        px.forward(15)
        time.sleep(2)

    # Stop
    px.stop()

finally:
    # Always stop on exit
    px.stop()
    px.set_dir_servo_angle(0)
```

## Camera API (vilib)

### Basic Camera Stream

```python
from vilib import Vilib

# Start the camera
Vilib.camera_start(vflip=False, hflip=False)

# Start the web stream (accessible at http://<pi-ip>:9000/mjpg)
Vilib.display(local=False, web=True)

# Capture a photo
Vilib.take_photo(photo_name="test", path="/home/pi/photos/")

# Stop the camera
Vilib.camera_close()
```

### Object Detection (vilib built-in)

```python
from vilib import Vilib

Vilib.camera_start()
Vilib.display(local=False, web=True)

# Color detection
Vilib.color_detect("red")  # Track red objects

# Read detection results
x = Vilib.detect_obj_parameter['color_x']  # X coordinate of detected object
y = Vilib.detect_obj_parameter['color_y']  # Y coordinate of detected object
w = Vilib.detect_obj_parameter['color_w']  # Width of bounding box
h = Vilib.detect_obj_parameter['color_h']  # Height of bounding box

if w > 0 and h > 0:
    print(f"Red object at ({x}, {y}), size {w}x{h}")
```

### Using picamera2 (Alternative)

For more control over the camera, use `picamera2` directly:

```python
from picamera2 import Picamera2
import cv2
import numpy as np

picam2 = Picamera2()
config = picam2.create_preview_configuration(
    main={"size": (640, 480), "format": "RGB888"}
)
picam2.configure(config)
picam2.start()

try:
    frame = picam2.capture_array()
    # frame is a numpy array (480, 640, 3) in RGB format

    # Convert to BGR for OpenCV
    bgr_frame = cv2.cvtColor(frame, cv2.COLOR_RGB2BGR)

    # Process frame with OpenCV
    gray = cv2.cvtColor(bgr_frame, cv2.COLOR_BGR2GRAY)
    # ... your processing pipeline ...

finally:
    picam2.stop()
```

## Calibration Procedures

### Steering Servo Calibration

The steering servo may not be mechanically centered at angle 0. To calibrate:

```python
from picarx import Picarx

px = Picarx()

# Set to nominal center
px.set_dir_servo_angle(0)

# Observe: does the robot drive straight?
# If it veers left, the offset is positive (needs + correction)
# If it veers right, the offset is negative

# Apply calibration offset
# This is saved to /opt/picar-x/config
px.dir_servo_calibrate(5)  # Adjust by +5 degrees

# Verify
px.set_dir_servo_angle(0)
# Robot should now drive straighter
```

### Camera Servo Calibration

```python
# Calibrate camera pan (horizontal center)
px.cam_pan_servo_calibrate(3)   # Offset of +3 degrees

# Calibrate camera tilt (vertical center)
px.cam_tilt_servo_calibrate(-2)  # Offset of -2 degrees
```

### Grayscale Sensor Calibration

```python
# Place robot on the track surface (not on the line)
# Read the background values
bg_values = px.get_grayscale_data()
print(f"Background: {bg_values}")  # e.g., [1500, 1500, 1400]

# Place robot with all sensors on the line
line_values = px.get_grayscale_data()
print(f"Line: {line_values}")  # e.g., [300, 280, 310]

# Set threshold midway
threshold = [(bg + ln) // 2 for bg, ln in zip(bg_values, line_values)]
px.set_line_reference(threshold)
print(f"Threshold: {threshold}")  # e.g., [900, 890, 855]
```

### Motor Direction Calibration

If a motor spins the wrong direction (wiring variation):

```python
# Calibrate motor direction
# motor: 1 (left) or 2 (right)
# direction: 1 (normal) or -1 (reversed)
px.motor_direction_calibrate(1, 1)   # Left motor normal
px.motor_direction_calibrate(2, -1)  # Right motor reversed
```

## Safety Wrapper Utilities

These are not part of the official library but are essential patterns for safe operation.

### Speed Limiter

```python
class SpeedLimiter:
    """Enforce a maximum speed regardless of what behaviors request."""

    def __init__(self, px, max_speed=30):
        self._px = px
        self._max_speed = max_speed

    @property
    def max_speed(self):
        return self._max_speed

    @max_speed.setter
    def max_speed(self, value):
        self._max_speed = max(0, min(100, value))

    def forward(self, speed):
        clamped = min(speed, self._max_speed)
        self._px.forward(clamped)

    def backward(self, speed):
        clamped = min(speed, self._max_speed)
        self._px.backward(clamped)

    def stop(self):
        self._px.stop()
```

### Watchdog Timer

```python
import threading
import time

class MotorWatchdog:
    """Stops motors if not refreshed within timeout period."""

    def __init__(self, px, timeout=1.5):
        self._px = px
        self._timeout = timeout
        self._last_refresh = time.time()
        self._running = False
        self._thread = None

    def start(self):
        self._running = True
        self._last_refresh = time.time()
        self._thread = threading.Thread(target=self._monitor, daemon=True)
        self._thread.start()

    def stop(self):
        self._running = False
        if self._thread:
            self._thread.join(timeout=2)

    def refresh(self):
        """Call this every control loop iteration to prevent timeout."""
        self._last_refresh = time.time()

    def _monitor(self):
        while self._running:
            elapsed = time.time() - self._last_refresh
            if elapsed > self._timeout:
                print(f"WATCHDOG: No refresh for {elapsed:.1f}s -- stopping motors!")
                self._px.stop()
            time.sleep(0.1)
```

### Safe Shutdown

```python
import signal
import sys

def setup_safe_shutdown(px):
    """Register signal handlers to stop robot on exit."""

    def shutdown_handler(signum, frame):
        print("\nShutting down safely...")
        px.stop()
        px.set_dir_servo_angle(0)
        px.set_cam_pan_angle(0)
        px.set_cam_tilt_angle(0)
        sys.exit(0)

    signal.signal(signal.SIGINT, shutdown_handler)
    signal.signal(signal.SIGTERM, shutdown_handler)
```

## Common Patterns

### Timed Drive

```python
def drive_for_duration(px, speed, duration, direction="forward"):
    """Drive at a speed for a bounded duration, then stop."""
    try:
        if direction == "forward":
            px.forward(speed)
        else:
            px.backward(speed)
        time.sleep(duration)
    finally:
        px.stop()
```

### Scan Sweep (Look Around)

```python
def scan_sweep(px, angles=None):
    """Pan the camera across angles and read distance at each."""
    if angles is None:
        angles = [-35, -20, 0, 20, 35]

    readings = {}
    for angle in angles:
        px.set_cam_pan_angle(angle)
        time.sleep(0.3)  # Let servo settle
        distance = px.get_distance()
        readings[angle] = distance

    # Return to center
    px.set_cam_pan_angle(0)
    return readings
```

### Proportional Steering for Line Following

```python
def compute_line_steering(grayscale_data, reference=None):
    """Compute a steering angle from grayscale sensor readings.

    Uses a weighted average to determine line position, then
    maps to a steering angle proportionally.

    Returns: float, steering angle in range [-35, 35]
    """
    left, middle, right = grayscale_data

    if reference is None:
        reference = [1000, 1000, 1000]

    # Normalize: higher value = more "on the line"
    # Invert because lower ADC = darker = on line
    left_norm = max(0, reference[0] - left)
    mid_norm = max(0, reference[1] - middle)
    right_norm = max(0, reference[2] - right)

    total = left_norm + mid_norm + right_norm
    if total == 0:
        return 0.0  # No line detected, go straight

    # Weighted position: -1 (left) to +1 (right)
    position = (-1 * left_norm + 0 * mid_norm + 1 * right_norm) / total

    # Map to steering angle
    max_angle = 35
    steering = position * max_angle
    return max(-max_angle, min(max_angle, steering))
```

## Error Handling Patterns

### Sensor Read with Retry

```python
def safe_distance_read(px, retries=3, delay=0.05):
    """Read ultrasonic with retries on failure."""
    for attempt in range(retries):
        distance = px.get_distance()
        if distance > 0:
            return distance
        time.sleep(delay)
    return -1  # All retries failed
```

### Graceful Degradation

```python
def drive_with_sensor_check(px, speed, sensor_timeout=5):
    """Drive forward but stop if sensor becomes unreliable."""
    last_good_reading = time.time()

    while True:
        distance = px.get_distance()

        if distance > 0:
            last_good_reading = time.time()
            if distance < 25:
                px.stop()
                return "obstacle"
            else:
                px.forward(speed)
        else:
            elapsed = time.time() - last_good_reading
            if elapsed > sensor_timeout:
                px.stop()
                return "sensor_failure"
            # Continue at reduced speed during brief sensor glitch
            px.forward(max(10, speed // 2))

        time.sleep(0.05)  # 20 Hz
```

## Performance Considerations

| Operation | Approximate Time | Impact on Control Loop |
|-----------|-----------------|----------------------|
| `get_distance()` | 20-60ms | Major bottleneck at high Hz |
| `get_grayscale_data()` | <1ms | Negligible |
| `set_dir_servo_angle()` | <1ms (command) | Servo physically moves over ~100ms |
| `forward()` / `stop()` | <1ms | Negligible |
| `Vilib.capture_array()` | 30-50ms | Run in separate thread |
| `picamera2.capture_array()` | 20-40ms | Run in separate thread |

**Recommended control loop rate:** 20 Hz (50ms per iteration) for ultrasonic-based behaviors, up to 50 Hz for grayscale-only behaviors.

## Configuration File

The Picar-X stores calibration data in `/opt/picar-x/config`. This JSON file contains servo offsets and motor direction settings. Back it up before making changes:

```bash
sudo cp /opt/picar-x/config /opt/picar-x/config.bak
```
