---
name: anomaly-detection
audience: professional
description: Statistical anomaly detection for sensor data streams. Use when implementing outlier detection, drift monitoring, anomaly classification, and alert/recalibration decision trees for time-series sensor data.
---

# Anomaly Detection for Sensor Data

> "The goal is not to eliminate anomalies. The goal is to understand them faster than they can cause harm."
> -- W. Edwards Deming (paraphrased)

## Core Philosophy

This skill provides the statistical methods, drift detection algorithms, and decision frameworks needed to detect, classify, and respond to anomalies in sensor data streams. It assumes sensor data arrives as a time series of numeric readings with associated timestamps.

**Non-Negotiable Constraints:**
1. **Baseline first** -- no detection algorithm produces meaningful results without a valid baseline for comparison.
2. **Multiple methods** -- never rely on a single statistical test; use at least two independent methods for consensus.
3. **Context matters** -- detection thresholds must be tuned per sensor and environment.
4. **Log everything** -- every anomaly event, threshold crossing, and suppression decision must be recorded.
5. **Distinguish fault from signal** -- a sensor reporting an unusual value may be broken, or the environment may have genuinely changed.

## Domain Principles Table

| Principle | Description | Priority |
|-----------|-------------|----------|
| **Baseline Validity** | Detection thresholds are only meaningful relative to a valid, stable baseline | Critical |
| **Statistical Consensus** | Multiple independent methods must agree before declaring an anomaly | Critical |
| **Temporal Context** | A single outlier is less significant than a sustained deviation | High |
| **Physical Plausibility** | Anomaly classification must consider what is physically possible for the sensor | Critical |
| **Adaptive Thresholds** | Static thresholds fail as sensor behavior drifts; thresholds must adapt | High |
| **Alert Hygiene** | Too many false positives cause alert fatigue; too few miss real events | High |
| **Drift Awareness** | Gradual drift is harder to detect than spikes but often more consequential | High |
| **Recalibration Discipline** | Recalibration is an invasive action requiring evidence and approval | Critical |

## Knowledge Base Lookups

| Query | When to Call |
|-------|--------------|
| `search_knowledge("Z-score CUSUM EWMA anomaly detection statistical methods")` | At BASELINE phase — algorithm selection and threshold calculation |
| `search_knowledge("sensor drift detection time series change point")` | When implementing drift detection |
| `search_knowledge("Python numpy scipy statistical anomaly detection time series")` | When implementing detection code |
| `search_knowledge("alert fatigue false positive threshold tuning sensor")` | During RESPOND phase — alert hygiene and threshold tuning |
| `search_knowledge("sensor calibration recalibration trigger conditions")` | When building recalibration decision trees |

Search at BASELINE and DETECT phases. Algorithm choices must be grounded in the KB before implementation.

## Workflow

The pipeline flows: **BASELINE → CONFIGURE → DETECT → CLASSIFY → RESPOND**, looping back to MONITOR after each reading; re-baseline after confirmed drift correction.

### Detection Method by Anomaly Type

| Anomaly Type | Methods | When to Use |
|--------------|---------|-------------|
| Point outliers (spikes) | Z-score, IQR, Grubbs test | Normal or near-normal distributions |
| Gradual drift | CUSUM, Page-Hinkley, EWMA drift | Any distribution; sustained mean shift |
| Distribution change | ADWIN, Kolmogorov-Smirnov | When the entire distribution shifts |

### Anomaly Classification

Classify based on temporal pattern: **SPIKE** (returns to normal within 1–3 readings), **DRIFT** (sustained trend away from baseline), **FLATLINE** (≤2 unique values in last 10 readings), **NOISE** (variance >2x baseline std but no mean shift).

## Step-by-Step Workflow

**Step 1: Establish Baseline** — Collect a representative sample of normal operation.

```python
import numpy as np
from scipy import stats

def establish_baseline(readings: list[float], min_samples: int = 100) -> dict:
    """Compute baseline statistics from known-normal readings."""
    if len(readings) < min_samples:
        raise ValueError(f"Need >= {min_samples} samples, got {len(readings)}")
    arr = np.array(readings)
    q1, q3 = np.percentile(arr, [25, 75])
    iqr = q3 - q1
    mid = len(arr) // 2
    mean_drift = abs(np.mean(arr[mid:]) - np.mean(arr[:mid])) / np.std(arr)
    _, normality_p = stats.shapiro(arr[:min(len(arr), 5000)])
    return {
        "mean": float(np.mean(arr)), "std": float(np.std(arr)),
        "median": float(np.median(arr)), "min": float(np.min(arr)), "max": float(np.max(arr)),
        "q1": float(q1), "q3": float(q3), "iqr": float(iqr), "count": len(arr),
        "is_normal": bool(normality_p > 0.05), "normality_p": float(normality_p),
        "is_stationary": bool(mean_drift < 0.5), "mean_drift_sigma": float(mean_drift),
    }
```

**Step 2: Configure Detectors** — Set thresholds from baseline statistics.

```python
def configure_detectors(baseline: dict) -> dict:
    """Configure detection thresholds based on baseline statistics."""
    return {
        "zscore": {
            "enabled": baseline["is_normal"], "threshold": 3.0,
            "mean": baseline["mean"], "std": baseline["std"],
        },
        "iqr": {
            "enabled": True, "factor": 1.5,
            "lower": baseline["q1"] - 1.5 * baseline["iqr"],
            "upper": baseline["q3"] + 1.5 * baseline["iqr"],
        },
        "ewma": {"enabled": True, "alpha": 0.3, "sigma_threshold": 3.0, "initial_mean": baseline["mean"]},
        "cusum": {"enabled": True, "target": baseline["mean"],
                  "threshold": 5.0 * baseline["std"], "drift_allowance": 0.5 * baseline["std"]},
    }
```

**Step 3: Detect** — Run each reading through all configured detectors, require consensus.

```python
def detect_anomaly(value: float, config: dict) -> dict:
    """Run a reading through all detectors; return per-method results and consensus."""
    results = {}
    votes_anomaly, votes_total = 0, 0

    if config["zscore"]["enabled"]:
        z = abs(value - config["zscore"]["mean"]) / config["zscore"]["std"]
        is_anomaly = z > config["zscore"]["threshold"]
        results["zscore"] = {"z_score": float(z), "is_anomaly": is_anomaly}
        votes_total += 1
        if is_anomaly: votes_anomaly += 1

    if config["iqr"]["enabled"]:
        below = value < config["iqr"]["lower"]
        above = value > config["iqr"]["upper"]
        is_anomaly = below or above
        results["iqr"] = {"is_anomaly": is_anomaly,
                          "bound_violated": "lower" if below else ("upper" if above else "none")}
        votes_total += 1
        if is_anomaly: votes_anomaly += 1

    consensus = votes_anomaly >= max(1, votes_total // 2 + 1)
    results["consensus"] = {
        "is_anomaly": consensus, "votes_anomaly": votes_anomaly, "votes_total": votes_total,
        "agreement_ratio": votes_anomaly / votes_total if votes_total > 0 else 0,
    }
    return results
```

**Step 4: Classify** — Determine anomaly type from temporal pattern.

```python
def classify_anomaly(recent_anomalies: list[dict], baseline: dict,
                     window_readings: list[float]) -> dict:
    """Classify anomaly type based on recent detection history and window statistics."""
    arr = np.array(window_readings)
    current_mean, current_std = np.mean(arr), np.std(arr)
    unique_values = len(set(window_readings[-10:]))

    if unique_values <= 2 and len(window_readings) >= 10:
        return {"type": "FLATLINE", "severity": "CRITICAL",
                "evidence": f"Only {unique_values} unique values in last 10 readings"}

    drift_sigma = abs(current_mean - baseline["mean"]) / baseline["std"]
    if drift_sigma > 2.0 and len(recent_anomalies) >= 5:
        severity = "CRITICAL" if drift_sigma > 4.0 else "WARNING"
        return {"type": "DRIFT", "severity": severity,
                "evidence": f"Mean shifted {drift_sigma:.1f} sigma from baseline",
                "drift_magnitude": float(drift_sigma)}

    noise_ratio = current_std / baseline["std"] if baseline["std"] > 0 else 0
    if noise_ratio > 2.0:
        severity = "CRITICAL" if noise_ratio > 4.0 else "WARNING"
        return {"type": "NOISE", "severity": severity, "evidence": f"Noise {noise_ratio:.1f}x baseline"}

    severity = "INFO" if len(recent_anomalies) == 1 else "WARNING"
    return {"type": "SPIKE", "severity": severity,
            "evidence": f"{len(recent_anomalies)} spike(s) detected"}
```

**Step 5: Respond** — Log, alert, and recommend recalibration or replacement based on classification. See `references/response-actions.md` for the full `respond_to_anomaly()` implementation including alert routing, recalibration approval workflow, and FLATLINE replacement escalation.

## State Block

```
<anomaly-detection-state>
step: [BASELINE | CONFIGURE | DETECT | CLASSIFY | RESPOND]
sensor_id: [sensor identifier]
baseline_established: [true | false]
detection_methods: [z-score, IQR, EWMA, CUSUM]
anomaly_type: [SPIKE | DRIFT | FLATLINE | NOISE | none]
severity: [INFO | WARNING | CRITICAL | EMERGENCY | none]
readings_processed: [count]
anomalies_detected: [count]
last_action: [what was just done]
next_action: [what should happen next]
blockers: [any issues]
</anomaly-detection-state>
```

## Output Templates

```markdown
## Anomaly Detection Report: [Sensor ID]
**Period**: [start] to [end] | **Readings**: [count] | **Anomaly Rate**: [%]

**Baseline**: Mean=[value], Std=[value], Distribution=[normal/skewed], Quality=[excellent/acceptable/marginal]

| Timestamp | Value | Type | Severity | Action |
|-----------|-------|------|----------|--------|
| [time] | [val] | SPIKE/DRIFT/FLATLINE/NOISE | INFO/WARNING/CRITICAL | logged/alerted/recal-recommended |

**Summary**: Spikes=[N], Drift events=[N] (magnitude=[sigma]σ), Flatline=[N], Noise=[N]
**Recommendations**: [action items]
```

## Anti-Patterns Table

| Anti-Pattern | Why It Fails | Correct Approach |
|--------------|-------------|------------------|
| Detecting without a baseline | No reference for "normal" — everything or nothing is anomalous | Always establish baseline before enabling detection |
| Using only z-score | Fails on non-normal distributions, sensitive to outliers in baseline | Combine z-score with IQR and EWMA for robustness |
| Static thresholds forever | Sensor behavior drifts; static thresholds accumulate false positives | Use adaptive methods (EWMA, ADWIN) that track evolving normal |
| Alerting on every single outlier | Single-sample spikes are often noise; causes alert fatigue | Require N consecutive violations or use a debounce window |
| Ignoring flatline as "stable" | A sensor reading the exact same value repeatedly is likely stuck | Monitor unique value count; flatline is always suspicious |
| Auto-recalibrating on drift | Drift may indicate a real environmental change, not sensor error | Require human approval and cross-sensor validation before recalibrating |
| Suppressing repeated alerts silently | Hides escalating problems; repeated anomalies may indicate worsening failure | Log all suppressions with rationale; escalate if pattern persists |
| Using training data with anomalies | Contaminated baseline produces thresholds that miss real anomalies | Curate baseline data; validate stationarity and distribution |

## AI Discipline Rules

**Baseline before detection.** Calling `detect_anomaly()` without an established baseline produces meaningless results — every threshold is derived from baseline statistics. Run `establish_baseline()` first, verify `is_stationary=True`, then configure detectors. A non-stationary baseline produces unreliable thresholds.

**Multiple methods must agree.** A single Z-score breach is insufficient. Requiring consensus from ≥2 independent methods eliminates most false positives from non-normal distributions and baseline contamination. The consensus threshold is `votes_anomaly >= ceil(votes_total / 2)`.

**Distinguish fault from signal.** Run a fault filter before anomaly scoring — check for null, out-of-range, or flatline values. Applying statistical outlier detection to a broken sensor produces misleading SPIKE alerts. Sensor faults are hardware events; they must be reported separately from environmental anomalies.

## Integration with Other Skills

- **`sensor-integration`** -- Use for physical sensor setup, protocol configuration, and calibration. Anomaly detection begins after `sensor-integration` has established a calibrated data pipeline.
- **`edge-cv-pipeline`** -- Frame rate and inference quality monitoring use similar EWMA and drift detection patterns.
- **`jetson-deploy`** -- When deploying anomaly detection on Jetson hardware, use this skill for statistical methods and `jetson-deploy` for the containerized deployment pipeline.
