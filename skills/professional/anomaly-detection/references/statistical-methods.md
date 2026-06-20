# Statistical Methods for Anomaly Detection

Reference guide for statistical anomaly detection methods applicable to sensor data streams. All examples use Python with numpy and scipy.

## Installation

```bash
pip install numpy scipy
```

---

## Z-Score Detection

The z-score measures how many standard deviations a value is from the mean. It is the simplest and most widely used method for point anomaly detection in normally distributed data.

**When to use:** Data is approximately normally distributed and you need fast, lightweight outlier detection.

**When to avoid:** Data is heavily skewed, has fat tails, or the baseline contains outliers that inflate the standard deviation.

```python
import numpy as np


def detect_zscore(data: list[float], threshold: float = 3.0) -> list[dict]:
    """
    Detect anomalies using the z-score method.

    A reading is anomalous if |value - mean| / std > threshold.

    Args:
        data: Sensor readings to analyze.
        threshold: Z-score threshold (default 3.0 = 99.7% confidence for normal).

    Returns:
        List of anomaly records with index, value, and z-score.
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
                "deviation_direction": "high" if val > mean else "low",
            })
    return anomalies


# Example: Temperature sensor with two outliers
readings = [22.1, 22.3, 22.0, 22.2, 85.0, 22.1, 22.4, 22.2, -10.0, 22.3]
anomalies = detect_zscore(readings, threshold=2.5)
for a in anomalies:
    print(f"Index {a['index']}: value={a['value']}, z={a['z_score']:.2f}")
```

### Modified Z-Score (Robust)

Uses the median and median absolute deviation (MAD) instead of mean and standard deviation. Much more robust to outliers in the baseline.

```python
import numpy as np


def detect_modified_zscore(data: list[float],
                           threshold: float = 3.5) -> list[dict]:
    """
    Detect anomalies using the modified z-score (Iglewicz & Hoaglin).

    Uses median and MAD instead of mean and std for robustness.
    The constant 0.6745 is the 0.75th quantile of the standard normal.

    Args:
        data: Sensor readings to analyze.
        threshold: Modified z-score threshold (3.5 recommended).

    Returns:
        List of anomaly records.
    """
    arr = np.array(data)
    median = np.median(arr)
    mad = np.median(np.abs(arr - median))
    if mad == 0:
        return []

    modified_z = 0.6745 * (arr - median) / mad
    anomalies = []
    for i, (val, mz) in enumerate(zip(arr, modified_z)):
        if abs(mz) > threshold:
            anomalies.append({
                "index": i,
                "value": float(val),
                "modified_z_score": float(mz),
            })
    return anomalies
```

---

## IQR (Interquartile Range) Detection

The IQR method uses the spread of the middle 50% of data to define outlier boundaries. It makes no assumptions about the data distribution.

**When to use:** Data is non-normal, skewed, or contains a small number of extreme outliers that would distort mean/std.

**When to avoid:** Data has a very small sample size (N < 20) or is multimodal.

```python
import numpy as np


def detect_iqr(data: list[float], factor: float = 1.5) -> list[dict]:
    """
    Detect anomalies using the IQR method.

    Values below Q1 - factor*IQR or above Q3 + factor*IQR are anomalies.
    factor=1.5 flags mild outliers; factor=3.0 flags extreme outliers only.

    Args:
        data: Sensor readings.
        factor: IQR multiplier.

    Returns:
        List of anomaly records with boundary information.
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
                "index": i, "value": float(val),
                "bound": "lower", "limit": float(lower),
            })
        elif val > upper:
            anomalies.append({
                "index": i, "value": float(val),
                "bound": "upper", "limit": float(upper),
            })
    return anomalies
```

---

## Grubbs Test

A formal statistical test for detecting a single outlier in a univariate dataset assumed to come from a normal distribution. Tests the null hypothesis that there are no outliers.

**When to use:** You need a statistically rigorous test for exactly one outlier at a time. Suitable for small datasets (N = 3 to 100).

**When to avoid:** Data has multiple outliers (masking effect), or data is not approximately normal.

```python
import numpy as np
from scipy import stats


def grubbs_test(data: list[float], alpha: float = 0.05) -> dict:
    """
    Grubbs test for a single outlier.

    Tests whether the most extreme value is a statistically significant
    outlier under the assumption of normality.

    Args:
        data: Sensor readings (must have N >= 3).
        alpha: Significance level.

    Returns:
        Dict with test statistic, critical value, and verdict.
    """
    arr = np.array(data)
    n = len(arr)
    if n < 3:
        return {"error": "Need at least 3 data points"}

    mean = np.mean(arr)
    std = np.std(arr, ddof=1)
    if std == 0:
        return {"outlier_detected": False, "reason": "zero variance"}

    # Find the most extreme value
    abs_deviations = np.abs(arr - mean)
    max_idx = np.argmax(abs_deviations)
    g_stat = abs_deviations[max_idx] / std

    # Critical value from t-distribution
    t_crit = stats.t.ppf(1 - alpha / (2 * n), n - 2)
    g_crit = ((n - 1) / np.sqrt(n)) * np.sqrt(t_crit**2 / (n - 2 + t_crit**2))

    return {
        "test_statistic": float(g_stat),
        "critical_value": float(g_crit),
        "outlier_detected": bool(g_stat > g_crit),
        "outlier_index": int(max_idx),
        "outlier_value": float(arr[max_idx]),
        "alpha": alpha,
    }


# Example
readings = [22.1, 22.3, 22.0, 22.2, 85.0, 22.1, 22.4, 22.2, 22.0, 22.3]
result = grubbs_test(readings, alpha=0.05)
print(f"Outlier detected: {result['outlier_detected']}")
print(f"Value: {result['outlier_value']}, G={result['test_statistic']:.3f}")
```

---

## CUSUM (Cumulative Sum Control Chart)

CUSUM detects small, persistent shifts in the mean of a process. It accumulates deviations from a target value and signals when the cumulative sum exceeds a threshold.

**When to use:** Detecting gradual drift or small sustained shifts that z-score would miss.

**When to avoid:** Data has high-frequency oscillations or natural periodic patterns.

```python
import numpy as np


class CUSUMDetector:
    """
    Cumulative Sum (CUSUM) detector for mean shifts.

    Tracks both upward and downward cumulative sums. Signals when
    either sum exceeds the decision threshold h.
    """

    def __init__(self, target: float, threshold: float,
                 drift_allowance: float):
        """
        Args:
            target: Expected mean value (from baseline).
            threshold: Decision threshold h (typically 4-5x std).
            drift_allowance: Slack parameter k (typically 0.5x std).
        """
        self.target = target
        self.h = threshold
        self.k = drift_allowance
        self.s_high = 0.0
        self.s_low = 0.0
        self.readings_count = 0

    def update(self, value: float) -> dict:
        """Process a new reading and check for mean shift."""
        self.readings_count += 1
        self.s_high = max(0, self.s_high + (value - self.target) - self.k)
        self.s_low = max(0, self.s_low - (value - self.target) - self.k)

        shift_up = self.s_high > self.h
        shift_down = self.s_low > self.h

        result = {
            "value": value,
            "s_high": float(self.s_high),
            "s_low": float(self.s_low),
            "shift_detected": shift_up or shift_down,
            "shift_direction": (
                "up" if shift_up else ("down" if shift_down else "none")
            ),
        }

        # Reset after detection
        if shift_up:
            self.s_high = 0.0
        if shift_down:
            self.s_low = 0.0

        return result

    def reset(self) -> None:
        """Reset cumulative sums."""
        self.s_high = 0.0
        self.s_low = 0.0
        self.readings_count = 0


# Example: Detect a gradual upward drift
cusum = CUSUMDetector(target=22.0, threshold=4.0, drift_allowance=0.5)
readings = ([22.1, 22.0, 21.9, 22.1, 22.0]      # Normal
            + [22.3, 22.5, 22.7, 22.9, 23.1]     # Drifting up
            + [23.3, 23.5, 23.7, 23.9, 24.1])     # Still drifting
for i, r in enumerate(readings):
    result = cusum.update(r)
    if result["shift_detected"]:
        print(f"[{i}] SHIFT {result['shift_direction']}: "
              f"value={r}, S+={result['s_high']:.2f}, S-={result['s_low']:.2f}")
```

---

## EWMA (Exponentially Weighted Moving Average)

EWMA gives exponentially decreasing weight to older observations, making it responsive to recent changes while smoothing noise.

**When to use:** Real-time streaming data where you need to track a smoothed estimate and detect deviations from it.

**When to avoid:** Data has strong seasonality or periodic patterns (use seasonal decomposition instead).

```python
import numpy as np


class EWMADetector:
    """
    EWMA-based anomaly detector with adaptive control limits.

    Maintains an exponentially weighted moving average and variance,
    and flags readings that deviate beyond the control limits.
    """

    def __init__(self, alpha: float = 0.3, sigma_threshold: float = 3.0):
        """
        Args:
            alpha: Smoothing factor (0 < alpha < 1). Higher = more reactive.
            sigma_threshold: Number of standard deviations for anomaly limit.
        """
        self.alpha = alpha
        self.sigma_threshold = sigma_threshold
        self.ewma: float | None = None
        self.ewma_var: float = 0.0
        self.count = 0

    def update(self, value: float) -> dict:
        """Process a new reading and check for anomaly."""
        self.count += 1

        if self.ewma is None:
            self.ewma = value
            return {"value": value, "ewma": value, "is_anomaly": False,
                    "deviation_sigma": 0.0}

        ewma_std = self.ewma_var ** 0.5
        deviation_sigma = (
            abs(value - self.ewma) / ewma_std if ewma_std > 0 else 0.0
        )
        is_anomaly = deviation_sigma > self.sigma_threshold

        if not is_anomaly:
            diff = value - self.ewma
            self.ewma = self.alpha * value + (1 - self.alpha) * self.ewma
            self.ewma_var = (1 - self.alpha) * (self.ewma_var
                                                 + self.alpha * diff ** 2)

        return {
            "value": value,
            "ewma": float(self.ewma),
            "ewma_std": float(ewma_std),
            "is_anomaly": is_anomaly,
            "deviation_sigma": float(deviation_sigma),
        }


# Example: Streaming temperature with a spike
detector = EWMADetector(alpha=0.2, sigma_threshold=3.0)
stream = [22.1, 22.3, 22.0, 22.2, 22.1, 85.0, 22.0, 22.3, 22.1, 22.2]
for i, val in enumerate(stream):
    result = detector.update(val)
    flag = " ** ANOMALY **" if result["is_anomaly"] else ""
    print(f"[{i}] val={val:6.1f}  ewma={result['ewma']:.2f}  "
          f"dev={result['deviation_sigma']:.2f}{flag}")
```

---

## Moving Average Deviation

Compares each reading against a local moving average to detect short-term deviations from the recent trend.

```python
import numpy as np
from collections import deque


class MovingAverageDetector:
    """
    Anomaly detection based on deviation from a sliding window average.

    Flags readings that deviate from the window mean by more than
    a configurable number of window standard deviations.
    """

    def __init__(self, window_size: int = 20,
                 threshold_sigma: float = 3.0):
        self.window: deque[float] = deque(maxlen=window_size)
        self.threshold = threshold_sigma

    def update(self, value: float) -> dict:
        """Process a new reading."""
        if len(self.window) < 5:
            self.window.append(value)
            return {"value": value, "is_anomaly": False, "window_mean": value}

        win = np.array(self.window)
        win_mean = float(np.mean(win))
        win_std = float(np.std(win))

        if win_std > 0:
            deviation = abs(value - win_mean) / win_std
            is_anomaly = deviation > self.threshold
        else:
            deviation = 0.0
            is_anomaly = False

        if not is_anomaly:
            self.window.append(value)

        return {
            "value": value,
            "window_mean": win_mean,
            "window_std": win_std,
            "deviation_sigma": float(deviation),
            "is_anomaly": is_anomaly,
        }
```

---

## Consensus Detection (Multi-Method)

Combining multiple detection methods reduces false positives and increases confidence in anomaly declarations.

```python
import numpy as np


def consensus_detect(value: float, baseline: dict,
                     ewma_state: dict,
                     window_readings: list[float],
                     min_votes: int = 2) -> dict:
    """
    Multi-method consensus anomaly detection.

    Runs z-score, IQR, and EWMA in parallel and requires min_votes
    methods to agree before declaring an anomaly.

    Args:
        value: Current reading.
        baseline: Baseline statistics dict.
        ewma_state: Current EWMA state (ewma, ewma_var).
        window_readings: Recent sliding window readings.
        min_votes: Minimum methods that must agree.

    Returns:
        Consensus result with per-method details.
    """
    votes = []

    # Method 1: Z-score
    if baseline["std"] > 0:
        z = abs(value - baseline["mean"]) / baseline["std"]
        z_anomaly = z > 3.0
        votes.append(("zscore", z_anomaly, {"z_score": float(z)}))

    # Method 2: IQR
    iqr = baseline["iqr"]
    lower = baseline["q1"] - 1.5 * iqr
    upper = baseline["q3"] + 1.5 * iqr
    iqr_anomaly = value < lower or value > upper
    votes.append(("iqr", iqr_anomaly, {"lower": lower, "upper": upper}))

    # Method 3: EWMA
    ewma = ewma_state.get("ewma", baseline["mean"])
    ewma_var = ewma_state.get("ewma_var", baseline["std"] ** 2)
    ewma_std = ewma_var ** 0.5
    ewma_dev = abs(value - ewma) / ewma_std if ewma_std > 0 else 0.0
    ewma_anomaly = ewma_dev > 3.0
    votes.append(("ewma", ewma_anomaly, {"deviation": float(ewma_dev)}))

    anomaly_count = sum(1 for _, is_anom, _ in votes if is_anom)
    is_anomaly = anomaly_count >= min_votes

    return {
        "value": value,
        "is_anomaly": is_anomaly,
        "anomaly_votes": anomaly_count,
        "total_methods": len(votes),
        "methods": {name: {"is_anomaly": anom, **detail}
                    for name, anom, detail in votes},
    }
```

---

## Choosing a Method: Quick Reference

| Method | Best For | Distribution | Sensitivity | Computational Cost |
|--------|----------|-------------|-------------|-------------------|
| Z-score | Point outliers in normal data | Normal required | High to single outliers | Very low |
| Modified Z-score | Point outliers with contaminated baseline | Any | Robust to baseline outliers | Low |
| IQR | Point outliers in any distribution | Any | Moderate | Low |
| Grubbs test | Statistically rigorous single-outlier test | Normal required | Formal significance test | Low |
| CUSUM | Small sustained mean shifts | Any | High to gradual drift | Low (streaming) |
| EWMA | Streaming trend tracking + outliers | Any | Adaptive to recent data | Low (streaming) |
| Moving Average | Local trend deviations | Any | Good for short-term anomalies | Low (streaming) |
| Consensus | Production anomaly detection | Any | Reduced false positives | Moderate (runs multiple) |

---

## Testing Statistical Methods

```python
import pytest
import numpy as np


class TestZScore:
    def test_clean_data_no_anomalies(self):
        data = list(np.random.normal(22.0, 0.1, 100))
        anomalies = detect_zscore(data, threshold=3.0)
        assert len(anomalies) <= 1  # Expect 0-1 by chance

    def test_obvious_outlier_detected(self):
        data = [22.0] * 50 + [100.0] + [22.0] * 49
        anomalies = detect_zscore(data, threshold=3.0)
        assert len(anomalies) >= 1
        assert anomalies[0]["value"] == 100.0

    def test_constant_data_no_anomalies(self):
        data = [22.0] * 100
        anomalies = detect_zscore(data, threshold=3.0)
        assert len(anomalies) == 0


class TestCUSUM:
    def test_no_shift_in_stable_data(self):
        cusum = CUSUMDetector(target=22.0, threshold=4.0,
                              drift_allowance=0.5)
        for val in np.random.normal(22.0, 0.1, 50):
            result = cusum.update(val)
            assert not result["shift_detected"]

    def test_detects_upward_shift(self):
        cusum = CUSUMDetector(target=22.0, threshold=3.0,
                              drift_allowance=0.3)
        detected = False
        for val in list(np.random.normal(22.0, 0.1, 20)) + \
                   list(np.random.normal(24.0, 0.1, 20)):
            result = cusum.update(val)
            if result["shift_detected"]:
                detected = True
                break
        assert detected


class TestEWMA:
    def test_stable_data_no_anomalies(self):
        detector = EWMADetector(alpha=0.2, sigma_threshold=3.0)
        for val in np.random.normal(22.0, 0.1, 50):
            result = detector.update(val)
        # After warmup, stable data should not trigger
        result = detector.update(22.05)
        assert not result["is_anomaly"]

    def test_spike_detected(self):
        detector = EWMADetector(alpha=0.2, sigma_threshold=3.0)
        for val in [22.0, 22.1, 22.0, 22.1, 22.0, 22.1, 22.0,
                    22.1, 22.0, 22.1]:
            detector.update(val)
        result = detector.update(85.0)
        assert result["is_anomaly"]
```
