# Calibration and Anomaly Detection

Reference guide for sensor calibration methods, statistical anomaly detection, and data validation pipelines. All examples use Python with numpy, scipy, and standard libraries.

## Installation

```bash
pip install numpy scipy pytest
```

---

## Calibration Methods

### Why Calibrate?

Every sensor has manufacturing tolerances that introduce systematic errors:
- **Offset error**: The sensor reads 1.3 C when the true temperature is 0.0 C.
- **Gain error**: The sensor reads 97.5 C when the true temperature is 100.0 C.
- **Nonlinearity**: The error changes across the measurement range.

Calibration measures these errors against a known reference and computes correction coefficients.

### Single-Point Offset Calibration

The simplest calibration: measure one known value and compute the offset.

```python
import numpy as np


def calibrate_offset(raw_readings: list[float],
                     reference_value: float) -> float:
    """
    Single-point offset calibration.

    Args:
        raw_readings: Multiple raw sensor readings at the reference point.
        reference_value: Known true value at the reference point.

    Returns:
        Offset to add to raw readings: corrected = raw + offset.
    """
    mean_raw = np.mean(raw_readings)
    offset = reference_value - mean_raw
    return float(offset)


def apply_offset(raw: float, offset: float) -> float:
    """Apply offset correction to a raw reading."""
    return raw + offset


# Example: Temperature sensor reads 1.3 C average in ice water (reference = 0 C)
raw_in_ice = [1.2, 1.4, 1.3, 1.3, 1.2, 1.4, 1.3, 1.3, 1.2, 1.3]
offset = calibrate_offset(raw_in_ice, reference_value=0.0)
print(f"Offset: {offset:.2f} C")  # -1.30

corrected = apply_offset(22.8, offset)
print(f"Raw: 22.8 C -> Corrected: {corrected:.2f} C")  # 21.50
```

### Two-Point Linear Calibration (Offset + Gain)

Measures at two known points to correct both offset and gain errors.

```python
import numpy as np


def calibrate_two_point(raw_readings_low: list[float],
                        raw_readings_high: list[float],
                        reference_low: float,
                        reference_high: float) -> dict:
    """
    Two-point linear calibration: corrected = gain * raw + offset.

    Args:
        raw_readings_low: Raw readings at the low reference point.
        raw_readings_high: Raw readings at the high reference point.
        reference_low: Known true value at low point.
        reference_high: Known true value at high point.

    Returns:
        Dict with 'gain', 'offset', and 'r_squared' keys.
    """
    mean_low = np.mean(raw_readings_low)
    mean_high = np.mean(raw_readings_high)

    gain = (reference_high - reference_low) / (mean_high - mean_low)
    offset = reference_low - gain * mean_low

    # Verify with R-squared
    raw_all = np.array(raw_readings_low + raw_readings_high)
    ref_all = np.array(
        [reference_low] * len(raw_readings_low)
        + [reference_high] * len(raw_readings_high)
    )
    corrected_all = gain * raw_all + offset
    ss_res = np.sum((ref_all - corrected_all) ** 2)
    ss_tot = np.sum((ref_all - np.mean(ref_all)) ** 2)
    r_squared = 1 - ss_res / ss_tot if ss_tot > 0 else 0.0

    return {
        "gain": float(gain),
        "offset": float(offset),
        "r_squared": float(r_squared),
    }


def apply_two_point(raw: float, cal: dict) -> float:
    """Apply two-point calibration."""
    return cal["gain"] * raw + cal["offset"]


# Example: Temperature sensor
raw_ice = [1.2, 1.3, 1.2, 1.4, 1.3]        # Reference: 0 C
raw_boil = [99.1, 99.3, 99.2, 99.0, 99.2]   # Reference: 100 C
cal = calibrate_two_point(raw_ice, raw_boil, 0.0, 100.0)
print(f"Gain: {cal['gain']:.6f}, Offset: {cal['offset']:.4f}, "
      f"R^2: {cal['r_squared']:.6f}")

corrected = apply_two_point(50.5, cal)
print(f"Raw: 50.5 -> Corrected: {corrected:.2f}")
```

### Multi-Point Polynomial Calibration

For sensors with nonlinear response, use polynomial fitting across multiple reference points.

```python
import numpy as np


def calibrate_multipoint(raw_values: list[float],
                         reference_values: list[float],
                         degree: int = 2) -> dict:
    """
    Multi-point polynomial calibration.

    Args:
        raw_values: Mean raw readings at each reference point.
        reference_values: Known true values at each reference point.
        degree: Polynomial degree (1=linear, 2=quadratic, etc.).

    Returns:
        Dict with 'coefficients' (highest degree first), 'degree',
        'r_squared', and 'residuals'.
    """
    raw_arr = np.array(raw_values)
    ref_arr = np.array(reference_values)

    coeffs = np.polyfit(raw_arr, ref_arr, degree)
    poly = np.poly1d(coeffs)

    predicted = poly(raw_arr)
    ss_res = np.sum((ref_arr - predicted) ** 2)
    ss_tot = np.sum((ref_arr - np.mean(ref_arr)) ** 2)
    r_squared = 1 - ss_res / ss_tot if ss_tot > 0 else 0.0

    residuals = ref_arr - predicted

    return {
        "coefficients": coeffs.tolist(),
        "degree": degree,
        "r_squared": float(r_squared),
        "residuals": residuals.tolist(),
    }


def apply_multipoint(raw: float, cal: dict) -> float:
    """Apply polynomial calibration."""
    poly = np.poly1d(cal["coefficients"])
    return float(poly(raw))


# Example: Pressure sensor with nonlinear response
raw_points = [10.2, 30.5, 50.8, 70.1, 90.4]
ref_points = [10.0, 30.0, 50.0, 70.0, 90.0]  # kPa
cal = calibrate_multipoint(raw_points, ref_points, degree=2)
print(f"Coefficients: {cal['coefficients']}")
print(f"R^2: {cal['r_squared']:.6f}")

corrected = apply_multipoint(45.3, cal)
print(f"Raw: 45.3 kPa -> Corrected: {corrected:.2f} kPa")
```

### Temperature Compensation

Many sensors drift with ambient temperature. Temperature compensation applies a correction factor based on a temperature measurement.

```python
import numpy as np


class TemperatureCompensator:
    """
    Compensate sensor readings for temperature-dependent drift.

    Requires calibration data collected at multiple temperatures.
    """

    def __init__(self):
        self.temp_coefficients: np.ndarray | None = None

    def calibrate(self, temperatures: list[float],
                  offsets_at_temp: list[float],
                  degree: int = 1) -> dict:
        """
        Fit a polynomial mapping temperature to offset correction.

        Args:
            temperatures: Ambient temperatures during calibration.
            offsets_at_temp: Measured offset error at each temperature.
            degree: Polynomial degree for the fit.

        Returns:
            Calibration summary.
        """
        self.temp_coefficients = np.polyfit(temperatures, offsets_at_temp, degree)
        poly = np.poly1d(self.temp_coefficients)
        predicted = poly(np.array(temperatures))
        residuals = np.array(offsets_at_temp) - predicted
        return {
            "coefficients": self.temp_coefficients.tolist(),
            "max_residual": float(np.max(np.abs(residuals))),
        }

    def compensate(self, raw_value: float, temperature: float) -> float:
        """Apply temperature compensation to a raw reading."""
        if self.temp_coefficients is None:
            raise RuntimeError("Not calibrated. Call calibrate() first.")
        poly = np.poly1d(self.temp_coefficients)
        offset = poly(temperature)
        return raw_value - offset


# Example: Pressure sensor offset drifts with temperature
comp = TemperatureCompensator()
temps = [0.0, 10.0, 20.0, 30.0, 40.0]
offsets = [0.5, 0.3, 0.1, -0.2, -0.4]  # Measured offset error at each temp
result = comp.calibrate(temps, offsets, degree=1)
print(f"Temperature coefficients: {result['coefficients']}")
print(f"Max residual: {result['max_residual']:.4f}")

corrected = comp.compensate(101.3, temperature=25.0)
print(f"Compensated pressure: {corrected:.2f} kPa")
```

### Calibration Storage and Loading

```python
import json
import time
from pathlib import Path


def save_calibration(cal_data: dict, sensor_id: str,
                     cal_dir: str = "./calibrations") -> str:
    """
    Save calibration data to a JSON file with metadata.

    Returns:
        Path to the saved calibration file.
    """
    Path(cal_dir).mkdir(parents=True, exist_ok=True)

    record = {
        "sensor_id": sensor_id,
        "calibrated_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "calibration": cal_data,
    }

    filename = f"{sensor_id}_{time.strftime('%Y%m%d_%H%M%S')}.json"
    filepath = Path(cal_dir) / filename
    filepath.write_text(json.dumps(record, indent=2))
    return str(filepath)


def load_latest_calibration(sensor_id: str,
                            cal_dir: str = "./calibrations") -> dict | None:
    """Load the most recent calibration for a sensor."""
    cal_path = Path(cal_dir)
    if not cal_path.exists():
        return None
    files = sorted(cal_path.glob(f"{sensor_id}_*.json"), reverse=True)
    if not files:
        return None
    record = json.loads(files[0].read_text())
    return record["calibration"]


# Usage
cal = {"gain": 1.0204, "offset": -1.30, "r_squared": 0.9999}
path = save_calibration(cal, "bme280-unit-001")
print(f"Saved to: {path}")

loaded = load_latest_calibration("bme280-unit-001")
print(f"Loaded: {loaded}")
```

---

## Anomaly Detection

### Z-Score Detection

Flags readings that are more than N standard deviations from the mean. Works well for normally distributed data with a stable baseline.

```python
import numpy as np


def detect_anomalies_zscore(data: list[float],
                            threshold: float = 3.0) -> list[dict]:
    """
    Detect anomalies using z-score method.

    Args:
        data: List of sensor readings.
        threshold: Number of standard deviations for anomaly threshold.

    Returns:
        List of dicts with 'index', 'value', and 'z_score' for each anomaly.
    """
    arr = np.array(data)
    mean = np.mean(arr)
    std = np.std(arr)
    if std == 0:
        return []

    anomalies = []
    for i, val in enumerate(arr):
        z = abs(val - mean) / std
        if z > threshold:
            anomalies.append({
                "index": i,
                "value": float(val),
                "z_score": float(z),
            })
    return anomalies


# Example
readings = [22.1, 22.3, 22.0, 22.2, 85.0, 22.1, 22.4, 22.2, -10.0, 22.3]
anomalies = detect_anomalies_zscore(readings, threshold=2.5)
for a in anomalies:
    print(f"Anomaly at index {a['index']}: value={a['value']}, "
          f"z-score={a['z_score']:.2f}")
```

### IQR (Interquartile Range) Detection

More robust than z-score for non-normal distributions and small sample sizes.

```python
import numpy as np


def detect_anomalies_iqr(data: list[float],
                         factor: float = 1.5) -> list[dict]:
    """
    Detect anomalies using the IQR method.

    Values below Q1 - factor*IQR or above Q3 + factor*IQR are anomalies.
    Use factor=3.0 for extreme outliers only.

    Args:
        data: List of sensor readings.
        factor: IQR multiplier (1.5 = mild outlier, 3.0 = extreme).

    Returns:
        List of dicts with 'index', 'value', and 'bound_violated'.
    """
    arr = np.array(data)
    q1 = np.percentile(arr, 25)
    q3 = np.percentile(arr, 75)
    iqr = q3 - q1

    lower = q1 - factor * iqr
    upper = q3 + factor * iqr

    anomalies = []
    for i, val in enumerate(arr):
        if val < lower:
            anomalies.append({
                "index": i,
                "value": float(val),
                "bound_violated": "lower",
                "bound_value": float(lower),
            })
        elif val > upper:
            anomalies.append({
                "index": i,
                "value": float(val),
                "bound_violated": "upper",
                "bound_value": float(upper),
            })
    return anomalies


# Example
readings = [22.1, 22.3, 22.0, 22.2, 85.0, 22.1, 22.4, 22.2, -10.0, 22.3]
anomalies = detect_anomalies_iqr(readings, factor=1.5)
for a in anomalies:
    print(f"Anomaly at index {a['index']}: {a['value']} "
          f"({a['bound_violated']} bound = {a['bound_value']:.2f})")
```

### Moving Average Filter

Smooths noisy data and detects readings that deviate from the local trend.

```python
import numpy as np
from collections import deque


class MovingAverageFilter:
    """
    Streaming moving average filter with anomaly detection.

    Maintains a sliding window and flags readings that deviate
    from the window average by more than the threshold.
    """

    def __init__(self, window_size: int = 10, anomaly_threshold: float = 3.0):
        self.window_size = window_size
        self.anomaly_threshold = anomaly_threshold
        self.window: deque[float] = deque(maxlen=window_size)

    def update(self, value: float) -> dict:
        """
        Add a new reading and return filtered result.

        Returns:
            Dict with 'raw', 'filtered', 'is_anomaly', and 'deviation'.
        """
        if len(self.window) < 2:
            self.window.append(value)
            return {
                "raw": value,
                "filtered": value,
                "is_anomaly": False,
                "deviation": 0.0,
            }

        window_mean = np.mean(list(self.window))
        window_std = np.std(list(self.window))

        if window_std > 0:
            deviation = abs(value - window_mean) / window_std
            is_anomaly = deviation > self.anomaly_threshold
        else:
            deviation = 0.0
            is_anomaly = False

        if not is_anomaly:
            self.window.append(value)

        filtered = np.mean(list(self.window))

        return {
            "raw": value,
            "filtered": float(filtered),
            "is_anomaly": is_anomaly,
            "deviation": float(deviation),
        }

    def reset(self) -> None:
        """Clear the filter window."""
        self.window.clear()


# Example: Filter a noisy temperature stream
maf = MovingAverageFilter(window_size=10, anomaly_threshold=3.0)
readings = [22.1, 22.3, 22.0, 22.2, 85.0, 22.1, 22.4, 22.2, 22.0, 22.3,
            22.1, 22.2, -10.0, 22.3, 22.1]

for i, r in enumerate(readings):
    result = maf.update(r)
    flag = " ** ANOMALY **" if result["is_anomaly"] else ""
    print(f"  [{i:2d}] raw={r:6.1f}  filtered={result['filtered']:.2f}"
          f"  dev={result['deviation']:.2f}{flag}")
```

### Simple Kalman Filter (1D)

Optimal for single-variable sensor fusion where you have a process model and measurement noise.

```python
import numpy as np


class KalmanFilter1D:
    """
    Simple 1D Kalman filter for sensor data smoothing.

    Models a single state variable with constant dynamics
    (random walk process model).
    """

    def __init__(self, process_variance: float = 1e-4,
                 measurement_variance: float = 0.1,
                 initial_estimate: float = 0.0,
                 initial_error: float = 1.0):
        """
        Args:
            process_variance: Q -- how much the true value changes per step.
            measurement_variance: R -- how noisy the sensor is.
            initial_estimate: Starting estimate of the state.
            initial_error: Starting uncertainty in the estimate.
        """
        self.q = process_variance
        self.r = measurement_variance
        self.x = initial_estimate      # State estimate
        self.p = initial_error          # Estimate uncertainty

    def update(self, measurement: float) -> dict:
        """
        Process one measurement and return filtered result.

        Returns:
            Dict with 'estimate', 'uncertainty', and 'kalman_gain'.
        """
        # Predict step (constant model: x_pred = x, p_pred = p + q)
        p_pred = self.p + self.q

        # Update step
        k = p_pred / (p_pred + self.r)  # Kalman gain
        self.x = self.x + k * (measurement - self.x)
        self.p = (1 - k) * p_pred

        return {
            "estimate": float(self.x),
            "uncertainty": float(self.p),
            "kalman_gain": float(k),
        }

    def reset(self, initial_estimate: float = 0.0,
              initial_error: float = 1.0) -> None:
        """Reset the filter state."""
        self.x = initial_estimate
        self.p = initial_error


# Example: Smooth noisy temperature readings
kf = KalmanFilter1D(
    process_variance=1e-4,
    measurement_variance=0.5,
    initial_estimate=22.0,
    initial_error=1.0,
)

noisy_readings = [22.1, 22.5, 21.8, 22.3, 22.0, 85.0, 22.2, 22.1,
                  22.4, 22.0, 22.3, 22.1]

for i, reading in enumerate(noisy_readings):
    result = kf.update(reading)
    print(f"  [{i:2d}] measured={reading:6.1f}  "
          f"estimate={result['estimate']:.3f}  "
          f"K={result['kalman_gain']:.4f}")
```

### Exponentially Weighted Moving Average (EWMA)

A lightweight alternative to Kalman filtering that gives more weight to recent readings.

```python
class EWMAFilter:
    """Exponentially Weighted Moving Average with anomaly detection."""

    def __init__(self, alpha: float = 0.3, anomaly_sigma: float = 3.0):
        """
        Args:
            alpha: Smoothing factor (0 < alpha < 1). Higher = more responsive.
            anomaly_sigma: Standard deviation multiplier for anomaly threshold.
        """
        self.alpha = alpha
        self.anomaly_sigma = anomaly_sigma
        self.ewma: float | None = None
        self.ewma_var: float = 0.0

    def update(self, value: float) -> dict:
        """Process a new reading."""
        if self.ewma is None:
            self.ewma = value
            return {
                "raw": value,
                "filtered": value,
                "is_anomaly": False,
            }

        # Check for anomaly before updating
        ewma_std = self.ewma_var ** 0.5
        is_anomaly = False
        if ewma_std > 0:
            deviation = abs(value - self.ewma) / ewma_std
            is_anomaly = deviation > self.anomaly_sigma

        if not is_anomaly:
            # Update EWMA and variance
            diff = value - self.ewma
            self.ewma = self.alpha * value + (1 - self.alpha) * self.ewma
            self.ewma_var = ((1 - self.alpha)
                             * (self.ewma_var + self.alpha * diff ** 2))

        return {
            "raw": value,
            "filtered": float(self.ewma),
            "is_anomaly": is_anomaly,
        }


# Example
ewma = EWMAFilter(alpha=0.2, anomaly_sigma=3.0)
for val in [22.1, 22.3, 22.0, 22.2, 85.0, 22.1, 22.4, 22.2]:
    result = ewma.update(val)
    flag = " ANOMALY" if result["is_anomaly"] else ""
    print(f"  raw={val:6.1f}  filtered={result['filtered']:.3f}{flag}")
```

---

## Data Validation Pipelines

### Reading Validator

```python
import time
import logging
from dataclasses import dataclass, field

logger = logging.getLogger("sensor.validation")


@dataclass
class SensorReading:
    """A validated sensor reading with quality metadata."""
    sensor_id: str
    timestamp: float
    raw_value: float
    corrected_value: float
    unit: str
    quality: str  # "valid", "suspect", "anomalous", "error"
    flags: list[str] = field(default_factory=list)


class ReadingValidator:
    """
    Validate sensor readings against physical constraints and
    statistical expectations.
    """

    def __init__(self, sensor_id: str, unit: str,
                 physical_min: float, physical_max: float,
                 rate_of_change_max: float | None = None):
        """
        Args:
            sensor_id: Unique identifier for the sensor.
            unit: Unit of measurement.
            physical_min: Minimum physically possible value.
            physical_max: Maximum physically possible value.
            rate_of_change_max: Maximum allowed change between consecutive
                readings (per second). None to disable.
        """
        self.sensor_id = sensor_id
        self.unit = unit
        self.physical_min = physical_min
        self.physical_max = physical_max
        self.rate_of_change_max = rate_of_change_max
        self.last_reading: SensorReading | None = None

    def validate(self, raw: float, corrected: float) -> SensorReading:
        """Validate a reading and return annotated SensorReading."""
        now = time.time()
        flags = []
        quality = "valid"

        # Check physical bounds
        if corrected < self.physical_min or corrected > self.physical_max:
            flags.append(
                f"out_of_range: {corrected} not in "
                f"[{self.physical_min}, {self.physical_max}]"
            )
            quality = "anomalous"
            logger.warning(
                "%s: out-of-range reading %.4f %s",
                self.sensor_id, corrected, self.unit,
            )

        # Check rate of change
        if (self.rate_of_change_max is not None
                and self.last_reading is not None):
            dt = now - self.last_reading.timestamp
            if dt > 0:
                rate = abs(corrected - self.last_reading.corrected_value) / dt
                if rate > self.rate_of_change_max:
                    flags.append(
                        f"rate_exceeded: {rate:.2f}/s > "
                        f"{self.rate_of_change_max}/s"
                    )
                    if quality == "valid":
                        quality = "suspect"

        # Check for stuck sensor (identical readings)
        if (self.last_reading is not None
                and raw == self.last_reading.raw_value):
            flags.append("stuck_sensor: identical consecutive raw values")
            if quality == "valid":
                quality = "suspect"

        reading = SensorReading(
            sensor_id=self.sensor_id,
            timestamp=now,
            raw_value=raw,
            corrected_value=corrected,
            unit=self.unit,
            quality=quality,
            flags=flags,
        )
        self.last_reading = reading
        return reading


# Usage
validator = ReadingValidator(
    sensor_id="bme280-temp-01",
    unit="celsius",
    physical_min=-40.0,
    physical_max=85.0,    # BME280 operating range
    rate_of_change_max=5.0,  # Max 5 C/s change
)

test_readings = [22.0, 22.1, 22.0, 85.5, 22.0, 22.0]
for raw in test_readings:
    reading = validator.validate(raw=raw, corrected=raw)
    print(f"  {reading.corrected_value:.1f} {reading.unit} "
          f"[{reading.quality}] {reading.flags}")
```

### Multi-Sensor Pipeline

```python
import time
import json
import logging
from dataclasses import dataclass, field, asdict

logger = logging.getLogger("pipeline")


@dataclass
class PipelineReading:
    """A reading that has passed through the full pipeline."""
    sensor_id: str
    timestamp: float
    raw_value: float
    calibrated_value: float
    filtered_value: float
    unit: str
    quality: str
    anomaly_detected: bool
    pipeline_stage: str


class SensorPipeline:
    """
    End-to-end pipeline: read -> calibrate -> filter -> validate -> publish.
    """

    def __init__(self, sensor_id: str, unit: str,
                 calibration: dict,
                 physical_min: float, physical_max: float,
                 filter_window: int = 10,
                 anomaly_threshold: float = 3.0):
        self.sensor_id = sensor_id
        self.unit = unit
        self.calibration = calibration
        self.physical_min = physical_min
        self.physical_max = physical_max

        from collections import deque
        self.filter_window: deque[float] = deque(maxlen=filter_window)
        self.anomaly_threshold = anomaly_threshold
        self.readings_processed = 0
        self.anomalies_detected = 0

    def process(self, raw_value: float) -> PipelineReading:
        """Run a raw reading through the full pipeline."""
        timestamp = time.time()
        self.readings_processed += 1

        # Stage 1: Calibrate
        gain = self.calibration.get("gain", 1.0)
        offset = self.calibration.get("offset", 0.0)
        calibrated = gain * raw_value + offset

        # Stage 2: Filter (moving average, skip anomalies)
        import numpy as np
        is_anomaly = False
        if len(self.filter_window) >= 3:
            window_mean = np.mean(list(self.filter_window))
            window_std = np.std(list(self.filter_window))
            if window_std > 0:
                z = abs(calibrated - window_mean) / window_std
                is_anomaly = z > self.anomaly_threshold

        if not is_anomaly:
            self.filter_window.append(calibrated)

        filtered = float(np.mean(list(self.filter_window))) if self.filter_window else calibrated

        # Stage 3: Validate physical bounds
        quality = "valid"
        if calibrated < self.physical_min or calibrated > self.physical_max:
            quality = "out_of_range"
            is_anomaly = True
        elif is_anomaly:
            quality = "anomalous"

        if is_anomaly:
            self.anomalies_detected += 1
            logger.warning(
                "%s anomaly #%d: raw=%.4f cal=%.4f",
                self.sensor_id, self.anomalies_detected,
                raw_value, calibrated,
            )

        return PipelineReading(
            sensor_id=self.sensor_id,
            timestamp=timestamp,
            raw_value=raw_value,
            calibrated_value=calibrated,
            filtered_value=filtered,
            unit=self.unit,
            quality=quality,
            anomaly_detected=is_anomaly,
            pipeline_stage="publish",
        )

    def stats(self) -> dict:
        """Return pipeline statistics."""
        return {
            "sensor_id": self.sensor_id,
            "readings_processed": self.readings_processed,
            "anomalies_detected": self.anomalies_detected,
            "anomaly_rate": (self.anomalies_detected / self.readings_processed
                            if self.readings_processed > 0 else 0.0),
        }


# Usage
pipeline = SensorPipeline(
    sensor_id="bme280-temp-01",
    unit="celsius",
    calibration={"gain": 1.0204, "offset": -1.30},
    physical_min=-40.0,
    physical_max=85.0,
    filter_window=10,
    anomaly_threshold=3.0,
)

raw_stream = [22.1, 22.3, 22.0, 22.2, 85.0, 22.1, 22.4, -10.0,
              22.2, 22.0, 22.3, 22.1, 22.2, 22.3, 22.0]

for raw in raw_stream:
    result = pipeline.process(raw)
    flag = " ** ANOMALY **" if result.anomaly_detected else ""
    print(f"  raw={raw:6.1f}  cal={result.calibrated_value:.2f}  "
          f"filt={result.filtered_value:.2f}  [{result.quality}]{flag}")

print(f"\nPipeline stats: {json.dumps(pipeline.stats(), indent=2)}")
```

---

## Logging and Alerting

### Structured Sensor Logging

```python
import logging
import json
import time


def setup_sensor_logging(log_file: str = "sensor.log",
                         level: int = logging.INFO) -> logging.Logger:
    """
    Configure structured JSON logging for sensor data.

    Each log entry includes timestamp, sensor_id, and structured data
    for machine-parseable analysis.
    """
    logger = logging.getLogger("sensor")
    logger.setLevel(level)

    handler = logging.FileHandler(log_file)
    handler.setLevel(level)

    class JSONFormatter(logging.Formatter):
        def format(self, record: logging.LogRecord) -> str:
            entry = {
                "timestamp": time.strftime(
                    "%Y-%m-%dT%H:%M:%S%z",
                    time.localtime(record.created),
                ),
                "level": record.levelname,
                "logger": record.name,
                "message": record.getMessage(),
            }
            if hasattr(record, "sensor_data"):
                entry["sensor_data"] = record.sensor_data
            return json.dumps(entry)

    handler.setFormatter(JSONFormatter())
    logger.addHandler(handler)
    return logger


def log_reading(logger: logging.Logger, sensor_id: str,
                value: float, unit: str, quality: str) -> None:
    """Log a sensor reading with structured data."""
    extra = {
        "sensor_data": {
            "sensor_id": sensor_id,
            "value": value,
            "unit": unit,
            "quality": quality,
        }
    }
    record = logger.makeRecord(
        logger.name, logging.INFO, "", 0,
        f"{sensor_id}: {value} {unit} [{quality}]",
        (), None,
    )
    record.sensor_data = extra["sensor_data"]
    logger.handle(record)
```

### Threshold-Based Alerting

```python
import time
import logging
from dataclasses import dataclass

logger = logging.getLogger("sensor.alerts")


@dataclass
class AlertRule:
    """A threshold-based alert rule for a sensor."""
    sensor_id: str
    metric: str
    min_threshold: float | None = None
    max_threshold: float | None = None
    consecutive_count: int = 3  # Readings before alerting
    cooldown_seconds: float = 60.0


class AlertManager:
    """Manage alert rules and track alert state."""

    def __init__(self):
        self.rules: list[AlertRule] = []
        self.violation_counts: dict[str, int] = {}
        self.last_alert_time: dict[str, float] = {}

    def add_rule(self, rule: AlertRule) -> None:
        self.rules.append(rule)
        key = f"{rule.sensor_id}:{rule.metric}"
        self.violation_counts[key] = 0
        self.last_alert_time[key] = 0.0

    def check(self, sensor_id: str, metric: str,
              value: float) -> list[str]:
        """
        Check a value against all matching rules.

        Returns list of alert messages (empty if no alerts triggered).
        """
        alerts = []
        now = time.time()

        for rule in self.rules:
            if rule.sensor_id != sensor_id or rule.metric != metric:
                continue

            key = f"{rule.sensor_id}:{rule.metric}"
            violated = False

            if rule.min_threshold is not None and value < rule.min_threshold:
                violated = True
                direction = "below"
                threshold = rule.min_threshold

            if rule.max_threshold is not None and value > rule.max_threshold:
                violated = True
                direction = "above"
                threshold = rule.max_threshold

            if violated:
                self.violation_counts[key] += 1
                if self.violation_counts[key] >= rule.consecutive_count:
                    if now - self.last_alert_time[key] > rule.cooldown_seconds:
                        msg = (
                            f"ALERT: {sensor_id} {metric} = {value} "
                            f"is {direction} threshold {threshold} "
                            f"({self.violation_counts[key]} consecutive)"
                        )
                        alerts.append(msg)
                        logger.warning(msg)
                        self.last_alert_time[key] = now
            else:
                self.violation_counts[key] = 0

        return alerts


# Usage
alert_mgr = AlertManager()
alert_mgr.add_rule(AlertRule(
    sensor_id="bme280-01",
    metric="temperature",
    max_threshold=40.0,
    consecutive_count=3,
    cooldown_seconds=300.0,
))

test_temps = [22.0, 38.0, 41.0, 42.0, 43.0, 39.0, 22.0]
for temp in test_temps:
    alerts = alert_mgr.check("bme280-01", "temperature", temp)
    for a in alerts:
        print(f"  >>> {a}")
```

---

## Testing Calibration and Anomaly Detection

```python
import pytest
import numpy as np


class TestZScoreDetection:
    """Tests for z-score anomaly detection."""

    def test_no_anomalies_in_clean_data(self):
        data = [22.0, 22.1, 21.9, 22.0, 22.1, 22.0, 21.9, 22.0]
        anomalies = detect_anomalies_zscore(data, threshold=3.0)
        assert len(anomalies) == 0

    def test_detects_obvious_outlier(self):
        data = [22.0, 22.1, 21.9, 22.0, 100.0, 22.1, 22.0]
        anomalies = detect_anomalies_zscore(data, threshold=2.0)
        assert len(anomalies) >= 1
        assert anomalies[0]["value"] == 100.0

    def test_empty_data_returns_empty(self):
        anomalies = detect_anomalies_zscore([], threshold=3.0)
        assert anomalies == []

    def test_constant_data_no_anomalies(self):
        data = [22.0] * 100
        anomalies = detect_anomalies_zscore(data, threshold=3.0)
        assert len(anomalies) == 0


class TestTwoPointCalibration:
    """Tests for two-point linear calibration."""

    def test_perfect_sensor_needs_no_correction(self):
        raw_low = [0.0, 0.0, 0.0]
        raw_high = [100.0, 100.0, 100.0]
        cal = calibrate_two_point(raw_low, raw_high, 0.0, 100.0)
        assert abs(cal["gain"] - 1.0) < 1e-6
        assert abs(cal["offset"]) < 1e-6

    def test_offset_sensor_corrected(self):
        raw_low = [2.0, 2.0, 2.0]
        raw_high = [102.0, 102.0, 102.0]
        cal = calibrate_two_point(raw_low, raw_high, 0.0, 100.0)
        corrected = apply_two_point(52.0, cal)
        assert abs(corrected - 50.0) < 0.01

    def test_r_squared_near_one(self):
        raw_low = [1.0, 1.1, 0.9]
        raw_high = [99.0, 99.1, 98.9]
        cal = calibrate_two_point(raw_low, raw_high, 0.0, 100.0)
        assert cal["r_squared"] > 0.99


class TestMovingAverageFilter:
    """Tests for moving average filter."""

    def test_stable_data_passes_through(self):
        maf = MovingAverageFilter(window_size=5, anomaly_threshold=3.0)
        for val in [22.0, 22.1, 22.0, 22.1, 22.0]:
            result = maf.update(val)
            assert not result["is_anomaly"]

    def test_spike_detected_as_anomaly(self):
        maf = MovingAverageFilter(window_size=5, anomaly_threshold=3.0)
        for val in [22.0, 22.1, 22.0, 22.1, 22.0]:
            maf.update(val)
        result = maf.update(100.0)
        assert result["is_anomaly"]

    def test_anomaly_excluded_from_window(self):
        maf = MovingAverageFilter(window_size=5, anomaly_threshold=3.0)
        for val in [22.0, 22.1, 22.0, 22.1, 22.0]:
            maf.update(val)
        maf.update(100.0)  # Anomaly
        result = maf.update(22.0)  # Normal reading after anomaly
        assert not result["is_anomaly"]
        assert abs(result["filtered"] - 22.0) < 0.5
```
