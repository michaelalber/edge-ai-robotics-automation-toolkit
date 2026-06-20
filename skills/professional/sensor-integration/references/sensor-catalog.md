# Sensor Catalog

Quick reference for common sensors organized by type. Each entry includes part number, protocol, default address, Python library, and minimal code to read a value.

## Installation (Common Libraries)

```bash
# Core protocol libraries
pip install smbus2 spidev pyserial gpiod

# Adafruit CircuitPython ecosystem
pip install adafruit-blinka
pip install adafruit-circuitpython-bme280
pip install adafruit-circuitpython-bno055
pip install adafruit-circuitpython-vl53l0x
pip install adafruit-circuitpython-lis3dh
pip install adafruit-circuitpython-lsm6ds
pip install adafruit-circuitpython-sht4x
pip install adafruit-circuitpython-bh1750
pip install adafruit-circuitpython-tsl2591
pip install adafruit-circuitpython-ads1x15
pip install adafruit-circuitpython-mcp3xxx

# Data processing
pip install numpy
```

---

## Distance Sensors

### HC-SR04 -- Ultrasonic Distance

| Property | Value |
|----------|-------|
| Protocol | GPIO (trigger + echo) |
| Range | 2 cm to 400 cm |
| Resolution | ~3 mm |
| Voltage | 5V (use level shifter for 3.3V SBCs) |
| Library | `gpiod` (direct GPIO) |

```
Wiring (Raspberry Pi with level shifter on ECHO):
  Pi GPIO23 ──────────────── TRIG
  Pi GPIO24 ──── [3.3V<->5V] ── ECHO
  Pi 5V     ──────────────── VCC
  Pi GND    ──────────────── GND
```

```python
# See protocol-patterns.md for full implementation with gpiod
# Minimal reading (requires the measure_distance_cm function from protocol-patterns.md):
distance = measure_distance_cm("/dev/gpiochip0", trigger_offset=23, echo_offset=24)
print(f"Distance: {distance:.1f} cm")
```

### VL53L0X -- Time-of-Flight Laser

| Property | Value |
|----------|-------|
| Protocol | I2C |
| Address | 0x29 |
| Range | 30 mm to 2000 mm |
| Accuracy | +/- 3% |
| Voltage | 3.3V or 5V |
| Library | `adafruit-circuitpython-vl53l0x` |

```
Wiring (Raspberry Pi):
  Pi 3.3V  ── VIN
  Pi GND   ── GND
  Pi SDA   ── SDA
  Pi SCL   ── SCL
  (Pull-ups usually on breakout board)
```

```python
import board
import busio
import adafruit_vl53l0x

i2c = busio.I2C(board.SCL, board.SDA)
sensor = adafruit_vl53l0x.VL53L0X(i2c)

# Set measurement timing budget (longer = more accurate)
sensor.measurement_timing_budget = 200000  # microseconds

distance_mm = sensor.range
print(f"Distance: {distance_mm} mm")
```

### TFMini-Plus -- LiDAR

| Property | Value |
|----------|-------|
| Protocol | UART (default) or I2C |
| Baud Rate | 115200 |
| Range | 0.1 m to 12 m |
| Accuracy | +/- 1% at 6m |
| Voltage | 5V |
| Library | `pyserial` (custom parser) |

```
Wiring (Raspberry Pi):
  Pi 5V     ── VCC (red)
  Pi GND    ── GND (black)
  Pi RX(10) ── TX  (green)  <-- cross-connect
  Pi TX(8)  ── RX  (white)  <-- cross-connect
```

```python
import serial

# See protocol-patterns.md for full TFMini binary parser
ser = serial.Serial("/dev/ttyS0", 115200, timeout=0.1)
reading = read_tfmini(ser)  # from protocol-patterns.md
if reading:
    print(f"Distance: {reading.distance_cm} cm")
ser.close()
```

### VL53L1X -- Long-Range Time-of-Flight

| Property | Value |
|----------|-------|
| Protocol | I2C |
| Address | 0x29 |
| Range | 40 mm to 4000 mm |
| Voltage | 3.3V or 5V |
| Library | `vl53l1x` (`pip install vl53l1x`) |

```python
import vl53l1x

tof = vl53l1x.VL53L1X(i2c_bus=1, i2c_address=0x29)
tof.open()
tof.set_timing(66000, 70)  # timing_budget_us, inter_measurement_period_ms
tof.start_ranging(2)  # 1=short, 2=medium, 3=long

distance_mm = tof.get_distance()
print(f"Distance: {distance_mm} mm")

tof.stop_ranging()
tof.close()
```

---

## IMU Sensors (Inertial Measurement Unit)

### MPU-6050 -- 6-DoF Accelerometer + Gyroscope

| Property | Value |
|----------|-------|
| Protocol | I2C |
| Address | 0x68 (AD0 low) or 0x69 (AD0 high) |
| Accel Range | +/- 2g, 4g, 8g, 16g |
| Gyro Range | +/- 250, 500, 1000, 2000 deg/s |
| Voltage | 3.3V or 5V |
| Library | `smbus2` (raw registers) |

```
Wiring (Raspberry Pi):
  Pi 3.3V ── VCC
  Pi GND  ── GND
  Pi SDA  ── SDA
  Pi SCL  ── SCL
```

```python
import smbus2
import struct
import time

MPU6050_ADDR = 0x68
PWR_MGMT_1 = 0x6B
ACCEL_XOUT_H = 0x3B
GYRO_XOUT_H = 0x43

bus = smbus2.SMBus(1)

# Wake up the sensor (clear sleep bit)
bus.write_byte_data(MPU6050_ADDR, PWR_MGMT_1, 0x00)
time.sleep(0.1)

# Read accelerometer (6 bytes: XH, XL, YH, YL, ZH, ZL)
raw = bytes(bus.read_i2c_block_data(MPU6050_ADDR, ACCEL_XOUT_H, 6))
ax, ay, az = struct.unpack(">hhh", raw)

# Convert to g (default range +/- 2g, sensitivity = 16384 LSB/g)
ax_g = ax / 16384.0
ay_g = ay / 16384.0
az_g = az / 16384.0
print(f"Accel: X={ax_g:.3f}g, Y={ay_g:.3f}g, Z={az_g:.3f}g")

# Read gyroscope (6 bytes)
raw = bytes(bus.read_i2c_block_data(MPU6050_ADDR, GYRO_XOUT_H, 6))
gx, gy, gz = struct.unpack(">hhh", raw)

# Convert to deg/s (default range +/- 250 deg/s, sensitivity = 131 LSB/(deg/s))
gx_dps = gx / 131.0
gy_dps = gy / 131.0
gz_dps = gz / 131.0
print(f"Gyro:  X={gx_dps:.2f}d/s, Y={gy_dps:.2f}d/s, Z={gz_dps:.2f}d/s")

bus.close()
```

### BNO055 -- 9-DoF Absolute Orientation

| Property | Value |
|----------|-------|
| Protocol | I2C |
| Address | 0x28 (default) or 0x29 |
| DoF | 9 (accel + gyro + magnetometer) |
| Features | On-chip sensor fusion, Euler angles, quaternions |
| Voltage | 3.3V or 5V |
| Library | `adafruit-circuitpython-bno055` |

```python
import board
import busio
import adafruit_bno055

i2c = busio.I2C(board.SCL, board.SDA)
sensor = adafruit_bno055.BNO055_I2C(i2c)

# Read Euler angles (heading, roll, pitch)
euler = sensor.euler
print(f"Heading: {euler[0]:.1f}, Roll: {euler[1]:.1f}, Pitch: {euler[2]:.1f}")

# Read quaternion
quat = sensor.quaternion
print(f"Quaternion: W={quat[0]:.4f}, X={quat[1]:.4f}, "
      f"Y={quat[2]:.4f}, Z={quat[3]:.4f}")

# Read linear acceleration (gravity removed)
linear = sensor.linear_acceleration
print(f"Linear Accel: X={linear[0]:.2f}, Y={linear[1]:.2f}, Z={linear[2]:.2f} m/s^2")

# Check calibration status
cal = sensor.calibration_status
print(f"Calibration -- Sys:{cal[0]} Gyro:{cal[1]} Accel:{cal[2]} Mag:{cal[3]}")
```

### LSM6DS33 -- 6-DoF (Accel + Gyro)

| Property | Value |
|----------|-------|
| Protocol | I2C or SPI |
| Address | 0x6A (SA0 low) or 0x6B (SA0 high) |
| Accel Range | +/- 2g, 4g, 8g, 16g |
| Gyro Range | +/- 125, 250, 500, 1000, 2000 deg/s |
| Voltage | 3.3V |
| Library | `adafruit-circuitpython-lsm6ds` |

```python
import board
import busio
from adafruit_lsm6ds.lsm6ds33 import LSM6DS33

i2c = busio.I2C(board.SCL, board.SDA)
sensor = LSM6DS33(i2c)

ax, ay, az = sensor.acceleration
gx, gy, gz = sensor.gyro
print(f"Accel: ({ax:.2f}, {ay:.2f}, {az:.2f}) m/s^2")
print(f"Gyro:  ({gx:.2f}, {gy:.2f}, {gz:.2f}) rad/s")
```

### LIS3DH -- 3-Axis Accelerometer

| Property | Value |
|----------|-------|
| Protocol | I2C or SPI |
| Address | 0x18 (SA0 low) or 0x19 (SA0 high) |
| Range | +/- 2g, 4g, 8g, 16g |
| Features | Tap detection, freefall detection, ADC inputs |
| Voltage | 3.3V |
| Library | `adafruit-circuitpython-lis3dh` |

```python
import board
import busio
import adafruit_lis3dh

i2c = busio.I2C(board.SCL, board.SDA)
sensor = adafruit_lis3dh.LIS3DH_I2C(i2c, address=0x18)
sensor.range = adafruit_lis3dh.RANGE_2_G

ax, ay, az = sensor.acceleration
print(f"Accel: ({ax:.2f}, {ay:.2f}, {az:.2f}) m/s^2")

# Enable tap detection
sensor.set_tap(1, 80)  # single tap, threshold=80
if sensor.tapped:
    print("Tap detected!")
```

---

## Environmental Sensors

### BME280 -- Temperature, Humidity, Pressure

| Property | Value |
|----------|-------|
| Protocol | I2C or SPI |
| Address | 0x76 (SDO low) or 0x77 (SDO high) |
| Temp Range | -40 to +85 C |
| Humidity | 0 to 100% RH |
| Pressure | 300 to 1100 hPa |
| Voltage | 3.3V |
| Library | `adafruit-circuitpython-bme280` |

```python
import board
import busio
import adafruit_bme280.basic as adafruit_bme280

i2c = busio.I2C(board.SCL, board.SDA)
bme280 = adafruit_bme280.Adafruit_BME280_I2C(i2c, address=0x76)

bme280.sea_level_pressure = 1013.25  # hPa for altitude calculation

print(f"Temperature: {bme280.temperature:.1f} C")
print(f"Humidity:    {bme280.relative_humidity:.1f} %")
print(f"Pressure:    {bme280.pressure:.1f} hPa")
print(f"Altitude:    {bme280.altitude:.1f} m")
```

### SHT4x -- High-Accuracy Temperature & Humidity

| Property | Value |
|----------|-------|
| Protocol | I2C |
| Address | 0x44 |
| Temp Accuracy | +/- 0.2 C |
| Humidity Accuracy | +/- 1.8% RH |
| Voltage | 3.3V |
| Library | `adafruit-circuitpython-sht4x` |

```python
import board
import busio
import adafruit_sht4x

i2c = busio.I2C(board.SCL, board.SDA)
sensor = adafruit_sht4x.SHT4x(i2c)
sensor.mode = adafruit_sht4x.Mode.NOHEAT_HIGHPREC

temperature, humidity = sensor.measurements
print(f"Temperature: {temperature:.2f} C")
print(f"Humidity:    {humidity:.2f} %")
```

### BMP390 -- High-Accuracy Barometric Pressure

| Property | Value |
|----------|-------|
| Protocol | I2C or SPI |
| Address | 0x77 (default) or 0x76 |
| Pressure Range | 300 to 1250 hPa |
| Pressure Accuracy | +/- 0.5 hPa |
| Voltage | 3.3V |
| Library | `adafruit-circuitpython-bmp3xx` |

```python
import board
import busio
import adafruit_bmp3xx

i2c = busio.I2C(board.SCL, board.SDA)
sensor = adafruit_bmp3xx.BMP3XX_I2C(i2c)

sensor.pressure_oversampling = 16
sensor.temperature_oversampling = 2

print(f"Pressure:    {sensor.pressure:.2f} hPa")
print(f"Temperature: {sensor.temperature:.2f} C")
```

### SGP30 -- Air Quality (VOC + eCO2)

| Property | Value |
|----------|-------|
| Protocol | I2C |
| Address | 0x58 |
| Measures | TVOC (0-60000 ppb), eCO2 (400-60000 ppm) |
| Voltage | 3.3V |
| Library | `adafruit-circuitpython-sgp30` |

```python
import board
import busio
import adafruit_sgp30
import time

i2c = busio.I2C(board.SCL, board.SDA)
sensor = adafruit_sgp30.Adafruit_SGP30(i2c)

# Initialize baseline (run for 12 hours for accurate baseline)
sensor.iaq_init()

# Read air quality
for _ in range(10):
    eco2, tvoc = sensor.iaq_measure()
    print(f"eCO2: {eco2} ppm, TVOC: {tvoc} ppb")
    time.sleep(1)
```

### DS18B20 -- Waterproof Temperature Probe

| Property | Value |
|----------|-------|
| Protocol | 1-Wire (GPIO with 4.7k pull-up) |
| Range | -55 to +125 C |
| Accuracy | +/- 0.5 C (from -10 to +85 C) |
| Resolution | 9 to 12 bits |
| Voltage | 3.3V or 5V |
| Library | System sysfs (no pip package needed) |

```
Wiring (Raspberry Pi):
  Pi 3.3V    ── VDD (red)
  Pi GND     ── GND (black)
  Pi GPIO4   ── DATA (yellow)
  4.7k ohm   between DATA and VDD (pull-up)

Enable 1-Wire in /boot/config.txt:
  dtoverlay=w1-gpio,gpiopin=4
```

```python
import glob
import time


def read_ds18b20() -> float | None:
    """Read temperature from DS18B20 via 1-Wire sysfs interface."""
    base_dir = "/sys/bus/w1/devices/"
    try:
        device_dirs = glob.glob(base_dir + "28-*")
        if not device_dirs:
            return None
        device_file = device_dirs[0] + "/w1_slave"
        with open(device_file, "r") as f:
            lines = f.readlines()
        # First line ends with YES if CRC is valid
        if lines[0].strip().endswith("YES"):
            temp_pos = lines[1].find("t=")
            if temp_pos != -1:
                temp_string = lines[1][temp_pos + 2:]
                return float(temp_string) / 1000.0
    except (IndexError, FileNotFoundError):
        pass
    return None


temp = read_ds18b20()
if temp is not None:
    print(f"Temperature: {temp:.2f} C")
else:
    print("DS18B20 not found. Check wiring and 1-Wire overlay.")
```

---

## Light Sensors

### BH1750 -- Ambient Light

| Property | Value |
|----------|-------|
| Protocol | I2C |
| Address | 0x23 (ADDR low) or 0x5C (ADDR high) |
| Range | 1 to 65535 lux |
| Voltage | 3.3V or 5V |
| Library | `adafruit-circuitpython-bh1750` |

```python
import board
import busio
import adafruit_bh1750

i2c = busio.I2C(board.SCL, board.SDA)
sensor = adafruit_bh1750.BH1750(i2c)

lux = sensor.lux
print(f"Ambient light: {lux:.1f} lux")
```

### TSL2591 -- High Dynamic Range Light

| Property | Value |
|----------|-------|
| Protocol | I2C |
| Address | 0x29 |
| Range | 188 ulux to 88,000 lux |
| Features | Separate IR and visible light channels |
| Voltage | 3.3V or 5V |
| Library | `adafruit-circuitpython-tsl2591` |

```python
import board
import busio
import adafruit_tsl2591

i2c = busio.I2C(board.SCL, board.SDA)
sensor = adafruit_tsl2591.TSL2591(i2c)

# Configure gain and integration time
sensor.gain = adafruit_tsl2591.GAIN_MED  # 25x
sensor.integration_time = adafruit_tsl2591.INTEGRATIONTIME_100MS

print(f"Lux:     {sensor.lux:.2f}")
print(f"Visible: {sensor.visible}")
print(f"IR:      {sensor.infrared}")
```

### VCNL4010 -- Proximity + Ambient Light

| Property | Value |
|----------|-------|
| Protocol | I2C |
| Address | 0x13 |
| Proximity Range | ~200 mm |
| Voltage | 3.3V |
| Library | `adafruit-circuitpython-vcnl4010` |

```python
import board
import busio
import adafruit_vcnl4010

i2c = busio.I2C(board.SCL, board.SDA)
sensor = adafruit_vcnl4010.VCNL4010(i2c)

proximity = sensor.proximity    # Raw proximity count (higher = closer)
ambient = sensor.ambient_lux
print(f"Proximity: {proximity}, Ambient: {ambient:.1f} lux")
```

---

## ADC (Analog-to-Digital Converters)

### ADS1115 -- 16-bit 4-Channel I2C ADC

| Property | Value |
|----------|-------|
| Protocol | I2C |
| Address | 0x48 (default), 0x49, 0x4A, 0x4B |
| Resolution | 16 bits |
| Channels | 4 single-ended or 2 differential |
| Sample Rate | 8 to 860 SPS |
| Voltage | 2.0V to 5.5V |
| Library | `adafruit-circuitpython-ads1x15` |

```python
import board
import busio
import adafruit_ads1x15.ads1115 as ADS
from adafruit_ads1x15.analog_in import AnalogIn

i2c = busio.I2C(board.SCL, board.SDA)
ads = ADS.ADS1115(i2c)

# Single-ended reading on channel 0
chan0 = AnalogIn(ads, ADS.P0)
print(f"Channel 0: {chan0.value} raw, {chan0.voltage:.4f}V")

# Differential reading (P0 - P1)
diff = AnalogIn(ads, ADS.P0, ADS.P1)
print(f"Differential: {diff.value} raw, {diff.voltage:.4f}V")

# Set gain for different ranges
ads.gain = 2  # +/- 2.048V range (1 = +/-4.096V, 16 = +/-0.256V)
```

### MCP3008 -- 10-bit 8-Channel SPI ADC

| Property | Value |
|----------|-------|
| Protocol | SPI |
| Resolution | 10 bits |
| Channels | 8 single-ended or 4 differential |
| Sample Rate | Up to 200 kSPS |
| Voltage | 2.7V to 5.5V |
| Library | `adafruit-circuitpython-mcp3xxx` or `spidev` (raw) |

```python
# Using adafruit library:
import board
import busio
import digitalio
import adafruit_mcp3xxx.mcp3008 as MCP
from adafruit_mcp3xxx.analog_in import AnalogIn

spi = busio.SPI(clock=board.SCK, MISO=board.MISO, MOSI=board.MOSI)
cs = digitalio.DigitalInOut(board.CE0)
mcp = MCP.MCP3008(spi, cs)

chan0 = AnalogIn(mcp, MCP.P0)
print(f"Channel 0: {chan0.value} raw, {chan0.voltage:.3f}V")
```

```python
# Using raw spidev (see protocol-patterns.md for MCP3008 class):
from protocol_patterns import MCP3008  # hypothetical import

adc = MCP3008(vref=3.3)
for ch in range(8):
    print(f"  CH{ch}: {adc.read_voltage(ch):.3f}V")
adc.close()
```

---

## GPIO Pin Reference

### Raspberry Pi 40-Pin Header

```
                 3.3V  (1)  (2)  5V
   I2C SDA (GPIO2) (3)  (4)  5V
   I2C SCL (GPIO3) (5)  (6)  GND
            GPIO4   (7)  (8)  GPIO14 (UART TX)
                GND  (9)  (10) GPIO15 (UART RX)
           GPIO17  (11)  (12) GPIO18 (PWM0)
           GPIO27  (13)  (14) GND
           GPIO22  (15)  (16) GPIO23
              3.3V (17)  (18) GPIO24
  SPI MOSI GPIO10  (19)  (20) GND
  SPI MISO GPIO9   (21)  (22) GPIO25
  SPI SCLK GPIO11  (23)  (24) GPIO8  (SPI CE0)
                GND (25)  (26) GPIO7  (SPI CE1)
           GPIO0   (27)  (28) GPIO1
           GPIO5   (29)  (30) GND
           GPIO6   (31)  (32) GPIO12 (PWM0)
     PWM1  GPIO13  (33)  (34) GND
           GPIO19  (35)  (36) GPIO16
           GPIO26  (37)  (38) GPIO20
                GND (39)  (40) GPIO21
```

**Key Pin Groups:**
- I2C: GPIO2 (SDA), GPIO3 (SCL)
- SPI0: GPIO10 (MOSI), GPIO9 (MISO), GPIO11 (SCLK), GPIO8 (CE0), GPIO7 (CE1)
- UART: GPIO14 (TX), GPIO15 (RX)
- PWM: GPIO12, GPIO13, GPIO18, GPIO19

### Jetson Nano 40-Pin Header

```
                3.3V  (1)  (2)  5V
   I2C1 SDA (GPIO2) (3)  (4)  5V
   I2C1 SCL (GPIO3) (5)  (6)  GND
            GPIO4    (7)  (8)  GPIO14 (UART1 TX)
                GND  (9)  (10) GPIO15 (UART1 RX)
           GPIO17   (11)  (12) GPIO18
           GPIO27   (13)  (14) GND
           GPIO22   (15)  (16) GPIO23
              3.3V  (17)  (18) GPIO24
  SPI1 MOSI GPIO10  (19)  (20) GND
  SPI1 MISO GPIO9   (21)  (22) GPIO25
  SPI1 SCLK GPIO11  (23)  (24) GPIO8  (SPI1 CS0)
                GND  (25)  (26) GPIO7  (SPI1 CS1)
  I2C0 SDA  GPIO0   (27)  (28) GPIO1  (I2C0 SCL)
           GPIO5    (29)  (30) GND
           GPIO6    (31)  (32) GPIO12
           GPIO13   (33)  (34) GND
           GPIO19   (35)  (36) GPIO16
           GPIO26   (37)  (38) GPIO20
                GND  (39)  (40) GPIO21
```

**Jetson-Specific Notes:**
- Two I2C buses available: I2C0 (pins 27/28) and I2C1 (pins 3/5)
- I2C bus numbers differ from Raspberry Pi. Use `i2cdetect -l` to list buses.
- Jetson uses `/dev/gpiochip0` (Tegra GPIO) and `/dev/gpiochip1` (GPIO expander).
- SPI and UART require device tree configuration: `sudo /opt/nvidia/jetson-io/jetson-io.py`

### Listing GPIO Chips and Lines

```bash
# List all GPIO chips
gpiodetect

# List all lines on a chip (shows names and usage)
gpioinfo /dev/gpiochip0

# Read a specific line
gpioget /dev/gpiochip0 17

# Set a line high
gpioset /dev/gpiochip0 17=1
```

```python
# Programmatic chip/line discovery
import gpiod

chip = gpiod.Chip("/dev/gpiochip0")
info = chip.get_info()
print(f"Chip: {info.name}, Label: {info.label}, Lines: {info.num_lines}")

for offset in range(info.num_lines):
    line_info = chip.get_line_info(offset)
    status = "used" if line_info.used else "free"
    consumer = line_info.consumer if line_info.consumer else "-"
    print(f"  Line {offset:3d}: {status:4s}  consumer={consumer}")
```

---

## Quick Address Reference

Common I2C addresses for popular sensors. Check for conflicts when placing multiple sensors on the same bus.

| Address | Sensor(s) |
|---------|-----------|
| 0x13 | VCNL4010 |
| 0x18 | LIS3DH (SA0 low) |
| 0x19 | LIS3DH (SA0 high) |
| 0x23 | BH1750 (ADDR low) |
| 0x28 | BNO055 (default) |
| 0x29 | VL53L0X, VL53L1X, TSL2591, BNO055 (alt) |
| 0x3C | SSD1306 OLED |
| 0x3D | SSD1306 OLED (alt) |
| 0x44 | SHT4x |
| 0x48 | ADS1115 (default) |
| 0x49-0x4B | ADS1115 (alt addresses) |
| 0x58 | SGP30 |
| 0x5C | BH1750 (ADDR high) |
| 0x68 | MPU-6050 (AD0 low), DS3231 RTC |
| 0x69 | MPU-6050 (AD0 high) |
| 0x6A | LSM6DS33 (SA0 low) |
| 0x6B | LSM6DS33 (SA0 high) |
| 0x76 | BME280 (SDO low), BMP390 (alt) |
| 0x77 | BME280 (SDO high), BMP390 (default) |

**When addresses conflict:** Use address selection pins first. If unavailable, use a TCA9548A I2C multiplexer (`pip install adafruit-circuitpython-tca9548a`).

```python
import board
import busio
import adafruit_tca9548a

i2c = busio.I2C(board.SCL, board.SDA)
mux = adafruit_tca9548a.TCA9548A(i2c)

# Access sensor on mux channel 0
sensor_a = adafruit_bme280.Adafruit_BME280_I2C(mux[0])

# Access another sensor with same address on channel 1
sensor_b = adafruit_bme280.Adafruit_BME280_I2C(mux[1])
```
