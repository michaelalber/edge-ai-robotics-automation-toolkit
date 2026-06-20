# Drift Detection for Sensor Data

Reference guide for concept drift detection algorithms and calibration scheduling strategies. All examples use Python with numpy and scipy.

## Installation

```bash
pip install numpy scipy
```

---

## Concept Drift Types

Drift occurs when the statistical properties of sensor data change over time. Understanding the type of drift is essential for choosing the right detection algorithm and response strategy.

### Sudden Drift

The data distribution changes abruptly at a single point in time. Causes include sensor replacement, firmware update, physical relocation, or sudden environmental change.

```
Signal
  ^
  |  xxxxxxxx
  |  xxxxxxxx
  |  xxxxxxxx          yyyyyyyy
  |  xxxxxxxx          yyyyyyyy
  |  xxxxxxxx          yyyyyyyy
  +-------------------->
                 ^      Time
           Drift point
```

**Detection:** CUSUM, Page-Hinkley, or windowed comparison tests detect sudden drift quickly because the shift is large and immediate.

### Gradual Drift

The data distribution slowly transitions from one state to another over a period of time. Causes include sensor aging, calibration decay, gradual environmental change, or material degradation.

```
Signal
  ^
  |  xxxxxxxx
  |  xxxxxxxx
  |   xxxxxxxxx
  |     xxxxxxxxxxx
  |        xxxxxxxxxxxxx
  |            xxxxxxxxxxxxx
  +------------------------------>
                                Time
```

**Detection:** EWMA and ADWIN are best for gradual drift because they track the evolving distribution over time. CUSUM can also detect gradual drift but may trigger late.

### Incremental Drift

Similar to gradual drift but occurring in small discrete steps. Each step is small enough to be within normal noise, but the cumulative effect is significant.

```
Signal
  ^
  |  xxxxx
  |  xxxxx
  |        xxxxx
  |        xxxxx
  |              xxxxx
  |              xxxxx
  +------------------------------>
                                Time
```

**Detection:** CUSUM is particularly effective because it accumulates small deviations. Page-Hinkley also handles incremental drift well.

### Recurring Drift

The data distribution oscillates between two or more known states. Causes include day/night cycles, seasonal effects, operational mode changes, or periodic maintenance.

```
Signal
  ^
  |  xxxxx        xxxxx        xxxxx
  |  xxxxx        xxxxx        xxxxx
  |        yyyyy        yyyyy
  |        yyyyy        yyyyy
  +------------------------------>
                                Time
```

**Detection:** Requires context-aware detection that distinguishes expected cyclic patterns from true anomalous drift. Seasonal decomposition or mode-aware baselines are needed.

---

## Drift Detection Algorithms

### DDM (Drift Detection Method)

DDM monitors the error rate of a prediction or classification model. When the error rate increases significantly, drift is declared. For sensor data, the "error" is the deviation from expected values.

**When to use:** You have a model or baseline that produces predictions, and you want to detect when the model's accuracy degrades.

```python
import numpy as np


class DDMDetector:
    """
    Drift Detection Method (Gama et al., 2004).

    Monitors a binary signal (correct/incorrect prediction or
    within/outside tolerance) and detects when the error rate
    increases significantly.

    Warning level: error + std > min_error + 2 * min_std
    Drift level:   error + std > min_error + 3 * min_std
    """

    def __init__(self, min_samples: int = 30):
        """
        Args:
            min_samples: Minimum samples before detection starts.
        """
        self.min_samples = min_samples
        self.count = 0
        self.error_sum = 0
        self.error_rate = 0.0
        self.error_std = 0.0
        self.min_error_rate = float("inf")
        self.min_error_std = float("inf")

    def update(self, is_error: bool) -> dict:
        """
        Process a new observation.

        Args:
            is_error: True if the reading is outside expected tolerance.

        Returns:
            Dict with status: 'normal', 'warning', or 'drift'.
        """
        self.count += 1
        self.error_sum += int(is_error)
        self.error_rate = self.error_sum / self.count
        self.error_std = np.sqrt(
            self.error_rate * (1 - self.error_rate) / self.count
        )

        status = "normal"

        if self.count >= self.min_samples:
            combined = self.error_rate + self.error_std

            if combined < self.min_error_rate + self.min_error_std:
                self.min_error_rate = self.error_rate
                self.min_error_std = self.error_std

            min_combined = self.min_error_rate + self.min_error_std

            if combined > self.min_error_rate + 3 * self.min_error_std:
                status = "drift"
            elif combined > self.min_error_rate + 2 * self.min_error_std:
                status = "warning"

        return {
            "status": status,
            "error_rate": float(self.error_rate),
            "error_std": float(self.error_std),
            "count": self.count,
        }

    def reset(self) -> None:
        """Reset detector after drift is confirmed."""
        self.count = 0
        self.error_sum = 0
        self.error_rate = 0.0
        self.error_std = 0.0
        self.min_error_rate = float("inf")
        self.min_error_std = float("inf")


# Example: Simulate normal operation then degradation
ddm = DDMDetector(min_samples=30)
# Normal: 5% error rate
for _ in range(100):
    result = ddm.update(is_error=(np.random.random() < 0.05))
# Degraded: 25% error rate
for i in range(100):
    result = ddm.update(is_error=(np.random.random() < 0.25))
    if result["status"] == "drift":
        print(f"Drift detected at observation {100 + i + 1}")
        break
```

### EDDM (Early Drift Detection Method)

EDDM improves on DDM by monitoring the distance between consecutive errors rather than the error rate itself. This makes it more sensitive to gradual drift.

**When to use:** Gradual drift where the error rate increases slowly over time.

```python
import numpy as np


class EDDMDetector:
    """
    Early Drift Detection Method (Baena-Garcia et al., 2006).

    Monitors the distance between classification errors. As drift
    occurs, errors become more frequent and the distance between
    them decreases.
    """

    def __init__(self, min_samples: int = 30):
        self.min_samples = min_samples
        self.count = 0
        self.error_count = 0
        self.last_error_pos = 0
        self.mean_distance = 0.0
        self.var_distance = 0.0
        self.max_metric = 0.0

    def update(self, is_error: bool) -> dict:
        """Process a new observation."""
        self.count += 1
        status = "normal"

        if is_error:
            self.error_count += 1
            if self.error_count > 1:
                distance = self.count - self.last_error_pos
                old_mean = self.mean_distance
                self.mean_distance += (
                    (distance - self.mean_distance) / (self.error_count - 1)
                )
                self.var_distance += (
                    (distance - old_mean) * (distance - self.mean_distance)
                )

                if self.error_count > self.min_samples:
                    std_distance = np.sqrt(
                        self.var_distance / (self.error_count - 1)
                    )
                    metric = self.mean_distance + 2 * std_distance

                    if metric > self.max_metric:
                        self.max_metric = metric

                    ratio = metric / self.max_metric if self.max_metric > 0 else 1.0

                    if ratio < 0.90:
                        status = "drift"
                    elif ratio < 0.95:
                        status = "warning"

            self.last_error_pos = self.count

        return {
            "status": status,
            "error_count": self.error_count,
            "mean_distance": float(self.mean_distance),
            "count": self.count,
        }

    def reset(self) -> None:
        """Reset detector after drift confirmation."""
        self.count = 0
        self.error_count = 0
        self.last_error_pos = 0
        self.mean_distance = 0.0
        self.var_distance = 0.0
        self.max_metric = 0.0
```

### ADWIN (Adaptive Windowing)

ADWIN maintains a variable-length window of recent data and automatically shrinks it when a change is detected. It compares the distributions of two sub-windows and drops older data when they differ significantly.

**When to use:** Streaming data where you need an algorithm that adapts its window size automatically. Excellent for both sudden and gradual drift.

```python
import numpy as np


class ADWINDetector:
    """
    Simplified ADWIN (Adaptive Windowing) drift detector.

    Maintains a sliding window and detects drift by comparing
    the means of two sub-windows. When drift is detected, old
    data is dropped to adapt to the new distribution.

    This is a simplified implementation. Production use should
    consider the full ADWIN algorithm with compressed buckets.
    """

    def __init__(self, delta: float = 0.002, max_window: int = 1000):
        """
        Args:
            delta: Confidence parameter (smaller = less sensitive).
            max_window: Maximum window size before forced trimming.
        """
        self.delta = delta
        self.max_window = max_window
        self.window: list[float] = []

    def update(self, value: float) -> dict:
        """
        Add a new value and check for drift.

        Returns:
            Dict with drift status and window statistics.
        """
        self.window.append(value)
        if len(self.window) > self.max_window:
            self.window = self.window[-self.max_window:]

        drift_detected = False
        cut_point = 0

        if len(self.window) >= 10:
            # Check all possible split points
            for i in range(5, len(self.window) - 5):
                w0 = np.array(self.window[:i])
                w1 = np.array(self.window[i:])

                n0, n1 = len(w0), len(w1)
                m0, m1 = np.mean(w0), np.mean(w1)
                n = n0 + n1

                # Hoeffding bound
                eps = np.sqrt(
                    (1 / (2 * n0) + 1 / (2 * n1))
                    * np.log(4 / self.delta)
                )

                if abs(m0 - m1) >= eps:
                    drift_detected = True
                    cut_point = i
                    break

        if drift_detected:
            self.window = self.window[cut_point:]

        return {
            "value": value,
            "drift_detected": drift_detected,
            "window_size": len(self.window),
            "window_mean": float(np.mean(self.window)),
            "window_std": float(np.std(self.window)),
        }


# Example: Detect a sudden mean shift
adwin = ADWINDetector(delta=0.01)
stream = list(np.random.normal(22.0, 0.2, 100))  # Normal
stream += list(np.random.normal(24.0, 0.2, 100))  # Shifted

for i, val in enumerate(stream):
    result = adwin.update(val)
    if result["drift_detected"]:
        print(f"[{i}] Drift detected! Window trimmed to "
              f"{result['window_size']}, new mean={result['window_mean']:.2f}")
```

### Page-Hinkley Test

A sequential analysis technique for detecting a change in the mean of a time series. Similar to CUSUM but uses a different formulation that is particularly effective for detecting abrupt changes.

**When to use:** Real-time detection of sudden or incremental mean shifts with low computational overhead.

```python
import numpy as np


class PageHinkleyDetector:
    """
    Page-Hinkley test for change detection.

    Monitors the cumulative difference between observed values and
    their running mean. Drift is signaled when the cumulative sum
    deviates too far from its minimum.
    """

    def __init__(self, threshold: float = 50.0,
                 delta: float = 0.005, alpha: float = 0.9999):
        """
        Args:
            threshold: Detection threshold lambda.
            delta: Minimum magnitude of change to detect.
            alpha: Forgetting factor for the running mean (0 < alpha < 1).
        """
        self.threshold = threshold
        self.delta = delta
        self.alpha = alpha
        self.running_mean = 0.0
        self.sum = 0.0
        self.min_sum = float("inf")
        self.count = 0

    def update(self, value: float) -> dict:
        """Process a new reading."""
        self.count += 1

        # Update running mean with forgetting factor
        self.running_mean = (
            self.alpha * self.running_mean + (1 - self.alpha) * value
        )

        # Update cumulative sum
        self.sum += value - self.running_mean - self.delta
        self.min_sum = min(self.min_sum, self.sum)

        # Check for drift
        ph_value = self.sum - self.min_sum
        drift_detected = ph_value > self.threshold

        if drift_detected:
            self.reset_partial()

        return {
            "value": value,
            "drift_detected": drift_detected,
            "ph_value": float(ph_value),
            "running_mean": float(self.running_mean),
            "count": self.count,
        }

    def reset_partial(self) -> None:
        """Partial reset after drift detection."""
        self.sum = 0.0
        self.min_sum = float("inf")


# Example: Detect sudden shift
ph = PageHinkleyDetector(threshold=20.0, delta=0.01)
stream = list(np.random.normal(22.0, 0.1, 80))
stream += list(np.random.normal(23.5, 0.1, 80))

for i, val in enumerate(stream):
    result = ph.update(val)
    if result["drift_detected"]:
        print(f"[{i}] Drift detected! PH={result['ph_value']:.2f}, "
              f"running_mean={result['running_mean']:.3f}")
```

---

## Calibration Scheduling

When drift is confirmed, the sensor may need recalibration. This section covers strategies for deciding when and how to recalibrate.

### Drift-Triggered Recalibration

Recalibrate when drift magnitude exceeds a defined tolerance.

```python
import time
import logging

logger = logging.getLogger("calibration.scheduler")


class DriftTriggeredScheduler:
    """
    Schedule recalibration based on detected drift magnitude.

    Tracks drift over time and recommends recalibration when
    the cumulative drift exceeds the sensor's calibration tolerance.
    """

    def __init__(self, sensor_id: str, tolerance: float,
                 min_interval_hours: float = 24.0):
        """
        Args:
            sensor_id: Sensor identifier.
            tolerance: Maximum acceptable drift in measurement units.
            min_interval_hours: Minimum time between recalibrations.
        """
        self.sensor_id = sensor_id
        self.tolerance = tolerance
        self.min_interval = min_interval_hours * 3600
        self.last_calibration = time.time()
        self.baseline_mean: float | None = None
        self.current_mean: float | None = None

    def update(self, current_mean: float,
               baseline_mean: float) -> dict:
        """
        Check if recalibration is needed.

        Args:
            current_mean: Current rolling mean of sensor readings.
            baseline_mean: Original baseline mean after last calibration.

        Returns:
            Recalibration recommendation.
        """
        self.current_mean = current_mean
        self.baseline_mean = baseline_mean
        drift = abs(current_mean - baseline_mean)
        drift_ratio = drift / self.tolerance if self.tolerance > 0 else 0

        time_since_cal = time.time() - self.last_calibration
        can_recalibrate = time_since_cal >= self.min_interval

        needs_recalibration = drift >= self.tolerance and can_recalibrate

        recommendation = {
            "sensor_id": self.sensor_id,
            "drift_magnitude": float(drift),
            "drift_ratio": float(drift_ratio),
            "tolerance": self.tolerance,
            "needs_recalibration": needs_recalibration,
            "reason": "",
            "hours_since_last_cal": time_since_cal / 3600,
        }

        if needs_recalibration:
            recommendation["reason"] = (
                f"Drift ({drift:.4f}) exceeds tolerance ({self.tolerance})"
            )
            logger.warning(
                "Recalibration recommended for %s: drift=%.4f, "
                "tolerance=%.4f",
                self.sensor_id, drift, self.tolerance,
            )
        elif drift >= self.tolerance and not can_recalibrate:
            recommendation["reason"] = (
                f"Drift exceeds tolerance but minimum interval not reached "
                f"({time_since_cal/3600:.1f}h < {self.min_interval/3600:.1f}h)"
            )

        return recommendation

    def confirm_recalibration(self) -> None:
        """Record that recalibration was performed."""
        self.last_calibration = time.time()
        logger.info("Recalibration confirmed for %s", self.sensor_id)


# Example
scheduler = DriftTriggeredScheduler(
    sensor_id="bme280-temp-01",
    tolerance=0.5,  # 0.5 C tolerance
    min_interval_hours=24.0,
)

result = scheduler.update(current_mean=22.7, baseline_mean=22.0)
print(f"Needs recalibration: {result['needs_recalibration']}")
print(f"Drift: {result['drift_magnitude']:.2f} / {result['tolerance']}")
```

### Time-Based Recalibration Schedule

For sensors with known aging characteristics, schedule recalibrations at fixed intervals.

```python
import time
from dataclasses import dataclass


@dataclass
class CalibrationScheduleEntry:
    """A scheduled calibration event."""
    sensor_id: str
    interval_days: float
    last_calibration: float  # Unix timestamp
    priority: str  # "routine", "overdue", "critical"


class CalibrationScheduler:
    """
    Time-based calibration scheduler for multiple sensors.

    Tracks calibration due dates and generates a prioritized schedule.
    """

    def __init__(self):
        self.sensors: dict[str, CalibrationScheduleEntry] = {}

    def register_sensor(self, sensor_id: str,
                        interval_days: float,
                        last_calibration: float | None = None) -> None:
        """Register a sensor with its calibration interval."""
        self.sensors[sensor_id] = CalibrationScheduleEntry(
            sensor_id=sensor_id,
            interval_days=interval_days,
            last_calibration=last_calibration or time.time(),
            priority="routine",
        )

    def check_schedule(self) -> list[dict]:
        """
        Check all sensors and return a prioritized calibration schedule.

        Returns:
            List of sensors needing calibration, sorted by priority.
        """
        now = time.time()
        schedule = []

        for sensor_id, entry in self.sensors.items():
            days_since = (now - entry.last_calibration) / 86400
            days_until_due = entry.interval_days - days_since
            overdue_ratio = days_since / entry.interval_days

            if overdue_ratio >= 1.5:
                priority = "critical"
            elif overdue_ratio >= 1.0:
                priority = "overdue"
            else:
                priority = "routine"

            entry.priority = priority
            schedule.append({
                "sensor_id": sensor_id,
                "days_since_calibration": round(days_since, 1),
                "interval_days": entry.interval_days,
                "days_until_due": round(days_until_due, 1),
                "overdue_ratio": round(overdue_ratio, 2),
                "priority": priority,
            })

        # Sort: critical first, then overdue, then routine
        priority_order = {"critical": 0, "overdue": 1, "routine": 2}
        schedule.sort(key=lambda x: (priority_order[x["priority"]],
                                     -x["overdue_ratio"]))
        return schedule

    def record_calibration(self, sensor_id: str) -> None:
        """Record that a sensor has been calibrated."""
        if sensor_id in self.sensors:
            self.sensors[sensor_id].last_calibration = time.time()
            self.sensors[sensor_id].priority = "routine"


# Example
scheduler = CalibrationScheduler()
scheduler.register_sensor("bme280-temp-01", interval_days=90)
scheduler.register_sensor("mpu6050-imu-01", interval_days=30)
scheduler.register_sensor("vl53l0x-dist-01", interval_days=180)

schedule = scheduler.check_schedule()
for entry in schedule:
    print(f"  {entry['sensor_id']}: {entry['priority']} "
          f"({entry['days_since_calibration']}d since cal, "
          f"due in {entry['days_until_due']}d)")
```

---

## Drift Response Decision Tree

```
        ┌──────────────────────────────────┐
        │ Drift detected by monitoring     │
        │ algorithm                        │
        └───────────────┬──────────────────┘
                        │
            ┌───────────┴───────────┐
            │                       │
     Within tolerance         Exceeds tolerance
            │                       │
            v                       v
    ┌──────────────┐    ┌────────────────────┐
    │ Log drift    │    │ Cross-validate with │
    │ Continue     │    │ redundant sensor    │
    │ monitoring   │    └──────────┬─────────┘
    └──────────────┘               │
                        ┌──────────┴──────────┐
                        │                     │
                  Both sensors           Only one sensor
                  show drift             shows drift
                        │                     │
                        v                     v
              ┌──────────────┐     ┌──────────────────┐
              │ Environmental │     │ Sensor fault     │
              │ change (real) │     │ suspected        │
              └──────┬───────┘     └────────┬─────────┘
                     │                      │
                     v                      v
           ┌──────────────────┐   ┌──────────────────┐
           │ Update baseline  │   │ Recommend         │
           │ to reflect new   │   │ recalibration     │
           │ normal           │   │ (REQUIRES APPROVAL)│
           └──────────────────┘   └──────────────────┘
```

---

## Algorithm Selection Guide

| Algorithm | Drift Type | Sensitivity | Latency | Memory | Best For |
|-----------|-----------|-------------|---------|--------|----------|
| DDM | Sudden, gradual | Moderate | Medium | Low | Model accuracy monitoring |
| EDDM | Gradual | High | Low | Low | Slow degradation detection |
| ADWIN | Sudden, gradual | High | Low | Moderate | Streaming with auto-windowing |
| Page-Hinkley | Sudden, incremental | High | Very low | Very low | Real-time edge deployment |
| CUSUM | Gradual, incremental | Very high | Medium | Very low | Small persistent shifts |

---

## Testing Drift Detectors

```python
import pytest
import numpy as np


class TestDDM:
    def test_stable_data_no_drift(self):
        ddm = DDMDetector(min_samples=30)
        for _ in range(200):
            result = ddm.update(is_error=(np.random.random() < 0.05))
        assert result["status"] == "normal"

    def test_detects_error_rate_increase(self):
        ddm = DDMDetector(min_samples=30)
        for _ in range(100):
            ddm.update(is_error=(np.random.random() < 0.05))
        detected = False
        for _ in range(200):
            result = ddm.update(is_error=(np.random.random() < 0.40))
            if result["status"] == "drift":
                detected = True
                break
        assert detected


class TestADWIN:
    def test_stable_data_no_drift(self):
        adwin = ADWINDetector(delta=0.01)
        any_drift = False
        for val in np.random.normal(22.0, 0.1, 200):
            result = adwin.update(val)
            if result["drift_detected"]:
                any_drift = True
        assert not any_drift

    def test_detects_mean_shift(self):
        adwin = ADWINDetector(delta=0.01)
        detected = False
        stream = list(np.random.normal(22.0, 0.1, 100))
        stream += list(np.random.normal(25.0, 0.1, 100))
        for val in stream:
            result = adwin.update(val)
            if result["drift_detected"]:
                detected = True
                break
        assert detected


class TestPageHinkley:
    def test_stable_data_no_drift(self):
        ph = PageHinkleyDetector(threshold=30.0, delta=0.01)
        for val in np.random.normal(22.0, 0.1, 200):
            result = ph.update(val)
            assert not result["drift_detected"]

    def test_detects_upward_shift(self):
        ph = PageHinkleyDetector(threshold=20.0, delta=0.01)
        detected = False
        stream = list(np.random.normal(22.0, 0.1, 80))
        stream += list(np.random.normal(24.0, 0.1, 80))
        for val in stream:
            result = ph.update(val)
            if result["drift_detected"]:
                detected = True
                break
        assert detected
```
