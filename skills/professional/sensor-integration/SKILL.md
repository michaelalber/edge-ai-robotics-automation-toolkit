---
name: sensor-integration
audience: professional
description: >
  Build sensor data pipelines with I2C, SPI, UART, and GPIO protocols. Use when
  integrating sensors with Raspberry Pi, Jetson, or other SBCs for data collection,
  calibration, and anomaly detection. Do NOT use when there is no physical sensor
  hardware involved; Do NOT use when the goal is cloud telemetry ingestion.
---

# Sensor Integration Pipeline

> "In embedded systems, the sensor is the source of truth. If you don't trust your sensor, you don't trust your system."
> -- Jack Ganssle, The Art of Designing Embedded Systems

## Core Philosophy

This skill coordinates the full lifecycle of sensor integration: from physical wiring and protocol configuration through calibration, validation, and data publishing. Sensors produce raw analog or digital signals that must be treated with skepticism until proven reliable.

**Non-Negotiable Constraints:**
1. **Calibrate before trusting** -- raw sensor data is meaningless without a known reference frame.
2. **Validate data at the source** -- reject impossible values at the driver layer, not in the application.
3. **Handle sensor failure gracefully** -- every read operation must have a timeout, a retry policy, and a fallback behavior.
4. **Respect the electrical domain** -- software cannot fix wiring errors. Verify voltage levels, pull-up resistors, and pin assignments before writing a single line of code.
5. **Log everything, trust nothing** -- every calibration event, anomaly, and bus error must be recorded with timestamps.

## Domain Principles Table

| Principle | Description | Priority |
|-----------|-------------|----------|
| **Data Integrity** | Every reading must include timestamp, sensor ID, and validity flag | Critical |
| **Calibration First** | No sensor enters production without a documented calibration procedure | Critical |
| **Protocol Selection** | Choose the simplest protocol that meets bandwidth and latency requirements | High |
| **Sample Rate Management** | Match sample rate to the physical phenomenon; oversampling wastes resources, undersampling loses data | High |
| **Fault Tolerance** | Every sensor read must handle timeout, CRC error, and bus conflict | Critical |
| **Wiring Verification** | Confirm physical connections before software debugging | Critical |
| **Power Budget** | Account for sensor current draw, especially on battery-powered systems | High |
| **Noise Reduction** | Apply hardware filtering (decoupling caps) before software filtering | Medium |
| **Reproducibility** | Same hardware + same code = same readings within tolerance | High |
| **Documentation** | Every sensor integration must include wiring diagram, calibration data, and protocol configuration | Medium |

## Knowledge Base Lookups

| Query | When to Call |
|-------|--------------|
| `search_knowledge("I2C SPI UART GPIO protocol selection")` | During IDENTIFY -- choosing the right bus protocol for a new sensor |
| `search_knowledge("sensor calibration offset gain correction")` | During CALIBRATE -- implementing linear or multi-point calibration |
| `search_knowledge("Raspberry Pi sensor I2C smbus2")` | During CONNECT -- setting up I2C on Raspberry Pi or Jetson |
| `search_knowledge("Python sensor data pipeline async")` | During PUBLISH -- designing async data acquisition loops |
| `search_knowledge("anomaly detection outlier sensor validation")` | During VALIDATE -- building range checks and anomaly flagging |
| `search_code_examples("I2C sensor read Python")` | Before writing driver code |
| `search_code_examples("MQTT publish sensor data Python")` | Before writing publisher |

Search `automation` and `robotics` collections for hardware-specific guidance. If KB returns nothing useful for a sensor-specific question, fall back to the datasheet.

## Workflow

Pipeline flows: **IDENTIFY → CONNECT → CONFIGURE → CALIBRATE → VALIDATE → PUBLISH** (continuous monitoring loop from VALIDATE back to PUBLISH).

**Pre-flight checks:** datasheet downloaded and reviewed, operating voltage confirmed (3.3V vs 5V), protocol identified, pin assignments documented, pull-up/pull-down resistors installed if needed, decoupling capacitor near sensor VCC, I2C address confirmed (no conflicts), Python libraries installed, user has /dev/ device access, test harness ready.

**Protocol Selection:**

| Protocol | Speed | Wires | Multi-Device | Best For |
|----------|-------|-------|-------------|----------|
| I2C | 100-400 kHz | 2 (SDA, SCL) | Yes (addressing) | Low-speed sensors, config registers |
| SPI | 1-50 MHz | 4+ (MOSI, MISO, SCLK, CS) | Yes (chip select) | High-speed, ADCs, displays |
| UART | 9600-115200 baud | 2 (TX, RX) | No | GPS, serial sensors |
| GPIO | N/A | 1 per signal | No | Digital on/off, triggers, PWM |

### Step 1: IDENTIFY

Determine sensor type, part number, protocol, operating voltage, and required libraries.

```python
sensor_manifest = {
    "name": "BME280", "type": "Environmental",
    "measures": ["temperature", "humidity", "pressure"],
    "protocol": "i2c", "address": 0x76, "voltage": 3.3,
    "library": "adafruit-circuitpython-bme280",
}
```

### Step 2: CONNECT

Wire the sensor and verify physical connections.

```python
import smbus2

def scan_i2c_bus(bus_number: int = 1) -> list[int]:
    bus = smbus2.SMBus(bus_number)
    devices = []
    for addr in range(0x03, 0x78):
        try:
            bus.read_byte(addr)
            devices.append(addr)
        except OSError:
            pass
    bus.close()
    return devices

detected = scan_i2c_bus()
assert 0x76 in detected, f"BME280 not found! Detected: {[hex(a) for a in detected]}"
```

### Step 3: CONFIGURE

Set sample rate, resolution, filtering, and operating mode.

```python
import adafruit_bme280.advanced as adafruit_bme280
import board, busio

i2c = busio.I2C(board.SCL, board.SDA)
bme280 = adafruit_bme280.Adafruit_BME280_I2C(i2c, address=0x76)
bme280.overscan_temperature = adafruit_bme280.OVERSCAN_X16
bme280.overscan_humidity = adafruit_bme280.OVERSCAN_X16
bme280.iir_filter = adafruit_bme280.IIR_FILTER_X16
bme280.mode = adafruit_bme280.MODE_NORMAL
```

### Step 4: CALIBRATE

Compare sensor readings against known reference values and compute correction factors.

```python
import numpy as np

def calibrate_temperature(sensor_readings: list[float],
                          reference_readings: list[float]) -> tuple[float, float]:
    gain, offset = np.polyfit(np.array(sensor_readings), np.array(reference_readings), 1)
    return offset, gain

raw_readings = [1.2, 99.5]   # ice water (0C) and boiling water (100C)
reference = [0.0, 100.0]
offset, gain = calibrate_temperature(raw_readings, reference)
```

### Step 5: VALIDATE

Run the sensor under controlled conditions and verify readings fall within expected tolerance.

```python
def validate_sensor(sensor, calibration, tolerance: float = 0.5, num_samples: int = 100) -> dict:
    readings = []
    for _ in range(num_samples):
        raw = sensor.temperature
        corrected = calibration["gain"] * raw + calibration["offset"]
        readings.append(corrected)
        time.sleep(0.1)
    arr = np.array(readings)
    return {"mean": float(np.mean(arr)), "std": float(np.std(arr)),
            "range_ok": bool(np.std(arr) < tolerance)}
```

### Step 6: PUBLISH

Push validated data to downstream consumers (MQTT, database, file, etc.).

```python
def publish_reading(sensor_id: str, value: float, unit: str, calibrated: bool = True) -> dict:
    return {"sensor_id": sensor_id, "timestamp": time.time(),
            "value": round(value, 4), "unit": unit,
            "calibrated": calibrated, "quality": "valid"}
```

## State Block

```
<sensor-state>
step: [IDENTIFY | CONNECT | CONFIGURE | CALIBRATE | VALIDATE | PUBLISH]
sensor_type: [e.g., "IMU", "LiDAR", "Ultrasonic", "Camera", "Temperature"]
protocol: [i2c | spi | uart | gpio]
calibrated: [true | false]
sample_rate_hz: [number]
last_action: [what was just done]
next_action: [what should happen next]
blockers: [any issues]
</sensor-state>
```

**Example:**

```
<sensor-state>
step: CALIBRATE
sensor_type: Environmental (BME280)
protocol: i2c
calibrated: false
sample_rate_hz: 2
last_action: Configured oversampling and IIR filter
next_action: Run two-point temperature calibration against reference thermometer
blockers: Need reference thermometer readings at 0C and 25C
</sensor-state>
```

## Output Templates

```markdown
## Sensor Setup: [Sensor Name]
**Protocol**: [I2C/SPI/UART/GPIO] | **Address/CS**: [value] | **Voltage**: [3.3V/5V]
**Library**: `pip install [package]` | **Bus**: [/dev/i2c-1, /dev/spidev0.0, etc.]
**Sample Rate**: [Hz] | **Resolution**: [bits] | **Filter**: [type and setting]

## Calibration Report: [Sensor Name]
**Reference Standard**: [instrument, last cal date]
| Reference Value | Raw Reading | Corrected Reading | Error |
| [val] | [val] | [val] | [val] |
**Coefficients**: Offset=[value], Gain=[value], R²=[value]
**Pass/Fail**: [PASS if all errors within tolerance]
```

## AI Discipline Rules

**Always verify physical wiring before software.** Before writing driver code or debugging software: confirm sensor is powered (measure VCC), confirm the correct bus is being accessed, confirm pull-up resistors are present (4.7k ohm for I2C), confirm pin assignments. If the sensor is not detected on the bus, it is a wiring problem until proven otherwise. Do NOT attempt software workarounds for hardware issues.

**Calibrate before collecting production data.** Raw sensor readings have manufacturing offsets and gain errors. Define reference points, collect raw readings, compute correction coefficients, validate corrected readings, store calibration coefficients with sensor metadata. Shipping uncalibrated data is equivalent to shipping broken code.

**Handle I2C bus conflicts.** Always scan the bus before adding a new device. Check for address collisions (many sensors use 0x68, 0x76). Use address selection pins (A0, A1) to resolve conflicts. If conflicts cannot be resolved, use a TCA9548A I2C multiplexer. Never assume a device is the only one on the bus.

**Never ignore anomalous readings.** Log every anomaly with full context (timestamp, raw value, expected range). Do not silently clamp or discard -- downstream consumers must know data quality degraded. Check bus health when readings are corrupted. Increment anomaly counters -- patterns indicate systemic problems.

## Anti-Patterns Table

| Anti-Pattern | Why It Fails | Correct Approach |
|--------------|-------------|------------------|
| Reading sensors without calibration | Raw values have unknown offset and gain errors | Always calibrate against a known reference before trusting data |
| Using `RPi.GPIO` for new projects | Deprecated, requires root, not portable across SBCs | Use `gpiod` (libgpiod) for modern, portable GPIO access |
| Ignoring I2C NAK errors | A NAK means the device did not respond; masking it hides wiring faults | Retry with backoff, then fail loudly if device is unresponsive |
| Polling sensors in a tight loop | Wastes CPU, may exceed sensor conversion time, causes self-heating | Use timers or `time.sleep()` matched to sensor sample rate |
| Hardcoding calibration coefficients | Calibration drifts over time and varies per unit | Store coefficients in config files, re-calibrate periodically |
| No timeout on bus reads | A stuck bus hangs the entire application | Always set a timeout; wrap in try/except |
| Sharing SPI bus without chip select management | Data corruption when multiple devices respond | Assert CS low only for the active device; release immediately |
| Treating all sensor data as equally valid | Startup transients, out-of-range values, and CRC failures are not valid | Tag every reading with a quality flag: valid, suspect, anomalous, error |

## Error Recovery

**Bus conflict (I2C)**: Run `i2cdetect -y 1` to list all devices. Use address selection pins to reassign one device. If impossible, install TCA9548A multiplexer. Re-scan bus and test each device independently.

**Timing issues (SPI)**: Reduce SPI clock speed (start at 100 kHz). Verify CPOL/CPHA mode matches datasheet. Check wire length (keep under 15 cm). Add 100nF decoupling cap near sensor VCC. Use a logic analyzer to inspect actual waveforms.

**Noisy readings**: Check power supply -- use a dedicated LDO regulator. Add hardware filtering (100nF ceramic cap on VCC, 10uF bulk cap). Apply software moving average filter (window 5-20 samples). Increase oversampling in sensor configuration. Shield signal wires from motor or relay noise.

**Sensor not responding**: Measure VCC at the sensor pin (not board header). Verify common ground. Check wiring (SDA to SDA, SCL to SCL). Verify 4.7k ohm pull-ups on SDA and SCL. Verify voltage level match (3.3V sensor on 3.3V bus). Try a different bus or GPIO pin.

**UART framing errors**: Verify baud rate matches datasheet exactly. Check data format (8N1 most common). Ensure TX/RX are not swapped. Add small delay between consecutive reads. Implement packet framing with start/end markers.

## Integration with Other Skills

- **`edge-cv-pipeline`** -- Camera modules are sensors too. Use this skill for camera initialization, frame rate management, and handling camera disconnection or frame corruption.
- **`jetson-deploy`** -- Jetson boards have specific I2C bus mappings and GPIO numbering. Use alongside `jetson-deploy` to configure sensor buses on Jetson Nano, Xavier NX, and Orin.
