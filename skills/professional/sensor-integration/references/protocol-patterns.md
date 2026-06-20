# Protocol Patterns for Sensor Integration

Reference guide for I2C, SPI, UART, and GPIO communication protocols. All examples use Python on Linux-based SBCs (Raspberry Pi, Jetson Nano, BeagleBone).

## Installation

```bash
# I2C
pip install smbus2

# SPI
pip install spidev

# UART
pip install pyserial

# GPIO (modern libgpiod approach)
pip install gpiod

# Adafruit CircuitPython (optional, sensor-specific)
pip install adafruit-blinka
pip install adafruit-circuitpython-bme280
pip install adafruit-circuitpython-bno055
pip install adafruit-circuitpython-vl53l0x

# Data processing
pip install numpy

# Testing
pip install pytest pytest-timeout
```

---

## I2C (Inter-Integrated Circuit)

### Overview

I2C uses two wires (SDA for data, SCL for clock) with addressing to support multiple devices on a single bus. Standard mode runs at 100 kHz, fast mode at 400 kHz.

### Wiring Diagram (Raspberry Pi)

```
Raspberry Pi                Sensor (e.g., BME280)
┌──────────┐                ┌──────────┐
│  3.3V (1)├────────────────┤ VCC      │
│  GND  (6)├────────────────┤ GND      │
│  SDA  (3)├───┬────────────┤ SDA      │
│  SCL  (5)├─┬─│────────────┤ SCL      │
└──────────┘ │ │            └──────────┘
             │ │
          4.7k 4.7k   <-- Pull-up resistors to 3.3V
             │ │
             └─┴── 3.3V
```

**Note:** Many breakout boards include built-in pull-ups. Check before adding external ones -- stacking pull-ups reduces the effective resistance and can cause signal integrity issues.

### Bus Scanning

```python
"""Scan an I2C bus and report all detected devices."""
import smbus2


def scan_i2c_bus(bus_number: int = 1) -> dict[int, str]:
    """
    Scan I2C bus and return dict of {address: status}.

    Args:
        bus_number: I2C bus number (1 for Raspberry Pi, varies on Jetson).

    Returns:
        Dictionary mapping addresses to 'found' or 'empty'.
    """
    bus = smbus2.SMBus(bus_number)
    results = {}
    for addr in range(0x03, 0x78):
        try:
            bus.read_byte(addr)
            results[addr] = "found"
        except OSError:
            results[addr] = "empty"
    bus.close()
    return results


def print_i2c_scan(bus_number: int = 1) -> None:
    """Print I2C scan results in a grid format similar to i2cdetect."""
    results = scan_i2c_bus(bus_number)
    print(f"I2C Bus {bus_number} Scan:")
    print("     0  1  2  3  4  5  6  7  8  9  a  b  c  d  e  f")
    for row in range(0, 0x80, 0x10):
        row_str = f"{row:02x}: "
        for col in range(0x10):
            addr = row + col
            if addr < 0x03 or addr > 0x77:
                row_str += "   "
            elif results.get(addr) == "found":
                row_str += f"{addr:02x} "
            else:
                row_str += "-- "
        print(row_str)


# Usage
print_i2c_scan(1)
```

### Single-Byte Read / Write

```python
import smbus2


def i2c_read_byte(bus_number: int, device_addr: int, register: int) -> int:
    """Read a single byte from a register."""
    with smbus2.SMBus(bus_number) as bus:
        return bus.read_byte_data(device_addr, register)


def i2c_write_byte(bus_number: int, device_addr: int,
                   register: int, value: int) -> None:
    """Write a single byte to a register."""
    with smbus2.SMBus(bus_number) as bus:
        bus.write_byte_data(device_addr, register, value)


# Example: Read WHO_AM_I register from MPU-6050 (addr 0x68, reg 0x75)
who_am_i = i2c_read_byte(1, 0x68, 0x75)
assert who_am_i == 0x68, f"Unexpected WHO_AM_I: 0x{who_am_i:02x}"
```

### Block Read / Write

```python
import smbus2
import struct


def i2c_read_block(bus_number: int, device_addr: int,
                   register: int, length: int) -> bytes:
    """Read a block of bytes starting at the given register."""
    with smbus2.SMBus(bus_number) as bus:
        data = bus.read_i2c_block_data(device_addr, register, length)
    return bytes(data)


def i2c_write_block(bus_number: int, device_addr: int,
                    register: int, data: list[int]) -> None:
    """Write a block of bytes starting at the given register."""
    with smbus2.SMBus(bus_number) as bus:
        bus.write_i2c_block_data(device_addr, register, data)


# Example: Read 6 bytes of accelerometer data from MPU-6050
# Registers 0x3B-0x40: ACCEL_XOUT_H, _L, YOUT_H, _L, ZOUT_H, _L
raw = i2c_read_block(1, 0x68, 0x3B, 6)
ax, ay, az = struct.unpack(">hhh", raw)
print(f"Accel: X={ax}, Y={ay}, Z={az}")
```

### I2C with smbus2 Message API (Advanced)

```python
import smbus2


def i2c_read_register_msg(bus_number: int, device_addr: int,
                          register: int, length: int) -> bytes:
    """
    Read using the message-based API for complex transactions.
    Useful when the device requires a repeated start condition.
    """
    write_msg = smbus2.i2c_msg.write(device_addr, [register])
    read_msg = smbus2.i2c_msg.read(device_addr, length)
    with smbus2.SMBus(bus_number) as bus:
        bus.i2c_rdwr(write_msg, read_msg)
    return bytes(read_msg)


# Example: Read 2 bytes with repeated start
data = i2c_read_register_msg(1, 0x76, 0xF7, 2)
```

### Multi-Device Bus Management

```python
import smbus2
import time
import logging

logger = logging.getLogger("i2c_bus")


class I2CBusManager:
    """Manage multiple I2C devices on a shared bus with conflict detection."""

    def __init__(self, bus_number: int = 1):
        self.bus_number = bus_number
        self.devices: dict[int, str] = {}  # addr -> name

    def register_device(self, addr: int, name: str) -> None:
        """Register a device on the bus. Raises if address conflicts."""
        if addr in self.devices:
            raise ValueError(
                f"Address 0x{addr:02x} already registered to "
                f"'{self.devices[addr]}', cannot register '{name}'"
            )
        # Verify device is physically present
        with smbus2.SMBus(self.bus_number) as bus:
            try:
                bus.read_byte(addr)
            except OSError:
                raise ConnectionError(
                    f"Device '{name}' not found at 0x{addr:02x}"
                )
        self.devices[addr] = name
        logger.info("Registered '%s' at 0x%02x", name, addr)

    def read_byte(self, addr: int, register: int,
                  retries: int = 3, delay: float = 0.01) -> int:
        """Read with retry logic for bus reliability."""
        for attempt in range(retries):
            try:
                with smbus2.SMBus(self.bus_number) as bus:
                    return bus.read_byte_data(addr, register)
            except OSError as e:
                logger.warning(
                    "Read failed for 0x%02x reg 0x%02x (attempt %d/%d): %s",
                    addr, register, attempt + 1, retries, e,
                )
                time.sleep(delay * (attempt + 1))
        raise IOError(
            f"Failed to read from 0x{addr:02x} after {retries} attempts"
        )

    def scan(self) -> list[int]:
        """Scan and return list of detected addresses."""
        found = []
        with smbus2.SMBus(self.bus_number) as bus:
            for addr in range(0x03, 0x78):
                try:
                    bus.read_byte(addr)
                    found.append(addr)
                except OSError:
                    pass
        return found


# Usage
bus_mgr = I2CBusManager(bus_number=1)
bus_mgr.register_device(0x76, "BME280")
bus_mgr.register_device(0x68, "MPU-6050")
temp_reg = bus_mgr.read_byte(0x76, 0xFA)
```

### Clock Stretching

Some sensors (particularly humidity and gas sensors) hold SCL low while processing. This is called clock stretching. Most Raspberry Pi I2C hardware supports it, but there are known bugs on older Pi models.

```python
# If clock stretching causes issues, reduce bus speed:
# Edit /boot/config.txt (Raspberry Pi):
#   dtparam=i2c_arm=on
#   dtparam=i2c_arm_baudrate=50000   # Reduce from 100000 to 50000

# Alternatively, use bit-banged I2C on different pins:
#   dtoverlay=i2c-gpio,bus=3,i2c_gpio_sda=23,i2c_gpio_scl=24,i2c_gpio_delay_us=2
```

---

## SPI (Serial Peripheral Interface)

### Overview

SPI uses four wires: MOSI (Master Out Slave In), MISO (Master In Slave Out), SCLK (clock), and CS (Chip Select, active low). It supports full-duplex communication at speeds from 100 kHz to 50+ MHz.

### Wiring Diagram (Raspberry Pi)

```
Raspberry Pi                Sensor (e.g., MCP3008 ADC)
┌──────────┐                ┌──────────┐
│  3.3V (1)├────────────────┤ VDD/VREF │
│  GND  (6)├────────────────┤ GND/AGND │
│ MOSI (19)├────────────────┤ DIN      │
│ MISO (21)├────────────────┤ DOUT     │
│ SCLK (23)├────────────────┤ CLK      │
│ CE0  (24)├────────────────┤ CS       │
└──────────┘                └──────────┘
```

### SPI Mode Selection

SPI has four modes based on CPOL (clock polarity) and CPHA (clock phase):

```
Mode 0: CPOL=0, CPHA=0  -- Clock idle low, sample on rising edge  (most common)
Mode 1: CPOL=0, CPHA=1  -- Clock idle low, sample on falling edge
Mode 2: CPOL=1, CPHA=0  -- Clock idle high, sample on rising edge
Mode 3: CPOL=1, CPHA=1  -- Clock idle high, sample on falling edge
```

**Always check the sensor datasheet for the correct mode.**

### Basic SPI Communication

```python
"""SPI communication using spidev."""
import spidev


def spi_open(bus: int = 0, device: int = 0,
             speed_hz: int = 1_000_000, mode: int = 0) -> spidev.SpiDev:
    """Open and configure an SPI device."""
    spi = spidev.SpiDev()
    spi.open(bus, device)
    spi.max_speed_hz = speed_hz
    spi.mode = mode
    spi.bits_per_word = 8
    return spi


def spi_transfer(spi: spidev.SpiDev, tx_data: list[int]) -> list[int]:
    """Full-duplex SPI transfer. Sends tx_data, returns received bytes."""
    return spi.xfer2(tx_data)


def spi_close(spi: spidev.SpiDev) -> None:
    """Close the SPI device."""
    spi.close()


# Example: Read channel 0 from MCP3008 ADC
spi = spi_open(bus=0, device=0, speed_hz=1_350_000, mode=0)

# MCP3008 protocol: send start bit, single-ended, channel number
# Returns 10-bit ADC value
channel = 0
cmd = [0x01, (0x80 | (channel << 4)), 0x00]
result = spi_transfer(spi, cmd)
adc_value = ((result[1] & 0x03) << 8) | result[2]
voltage = adc_value * 3.3 / 1023.0
print(f"Channel {channel}: ADC={adc_value}, Voltage={voltage:.3f}V")

spi_close(spi)
```

### Multi-Channel ADC Reading

```python
import spidev
import time


class MCP3008:
    """Driver for MCP3008 10-bit ADC over SPI."""

    def __init__(self, bus: int = 0, device: int = 0,
                 speed_hz: int = 1_350_000, vref: float = 3.3):
        self.spi = spidev.SpiDev()
        self.spi.open(bus, device)
        self.spi.max_speed_hz = speed_hz
        self.spi.mode = 0
        self.vref = vref

    def read_channel(self, channel: int) -> int:
        """Read raw 10-bit ADC value from a channel (0-7)."""
        if not 0 <= channel <= 7:
            raise ValueError(f"Channel must be 0-7, got {channel}")
        cmd = [0x01, (0x80 | (channel << 4)), 0x00]
        result = self.spi.xfer2(cmd)
        return ((result[1] & 0x03) << 8) | result[2]

    def read_voltage(self, channel: int) -> float:
        """Read voltage from a channel."""
        raw = self.read_channel(channel)
        return raw * self.vref / 1023.0

    def read_all_channels(self) -> list[float]:
        """Read voltage from all 8 channels."""
        return [self.read_voltage(ch) for ch in range(8)]

    def close(self) -> None:
        self.spi.close()


# Usage
adc = MCP3008(vref=3.3)
for ch in range(8):
    v = adc.read_voltage(ch)
    print(f"  CH{ch}: {v:.3f}V")
adc.close()
```

### Chip Select Management for Multiple Devices

```python
import spidev


class SPIBus:
    """Manage multiple SPI devices on the same bus with different CS lines."""

    def __init__(self, bus: int = 0):
        self.bus = bus
        self.devices: dict[str, spidev.SpiDev] = {}

    def add_device(self, name: str, cs: int, speed_hz: int,
                   mode: int = 0) -> None:
        """Register a device on a chip select line."""
        spi = spidev.SpiDev()
        spi.open(self.bus, cs)
        spi.max_speed_hz = speed_hz
        spi.mode = mode
        self.devices[name] = spi

    def transfer(self, name: str, data: list[int]) -> list[int]:
        """Transfer data to/from a named device."""
        if name not in self.devices:
            raise KeyError(f"Device '{name}' not registered")
        return self.devices[name].xfer2(data)

    def close_all(self) -> None:
        """Close all SPI devices."""
        for spi in self.devices.values():
            spi.close()
        self.devices.clear()


# Usage: ADC on CE0, DAC on CE1
spi_bus = SPIBus(bus=0)
spi_bus.add_device("adc", cs=0, speed_hz=1_350_000)
spi_bus.add_device("dac", cs=1, speed_hz=10_000_000)

adc_result = spi_bus.transfer("adc", [0x01, 0x80, 0x00])
spi_bus.transfer("dac", [0x30, 0x00, 0xFF])  # Write to DAC

spi_bus.close_all()
```

---

## UART (Universal Asynchronous Receiver/Transmitter)

### Overview

UART is a point-to-point serial protocol with configurable baud rate, data bits, parity, and stop bits. Most sensors use 9600 or 115200 baud, 8N1 format (8 data bits, no parity, 1 stop bit).

### Wiring Diagram (Raspberry Pi)

```
Raspberry Pi                Sensor (e.g., GPS Module)
┌──────────┐                ┌──────────┐
│  3.3V (1)├────────────────┤ VCC      │
│  GND  (6)├────────────────┤ GND      │
│  TX  (8) ├────────────────┤ RX       │  <-- Cross-connect!
│  RX  (10)├────────────────┤ TX       │  <-- Cross-connect!
└──────────┘                └──────────┘

IMPORTANT: TX connects to RX and RX connects to TX (crossover).
```

### Basic UART Read / Write

```python
"""UART communication using pyserial."""
import serial
import time


def uart_open(port: str = "/dev/ttyS0", baudrate: int = 9600,
              timeout: float = 1.0) -> serial.Serial:
    """Open a UART port with standard 8N1 configuration."""
    return serial.Serial(
        port=port,
        baudrate=baudrate,
        bytesize=serial.EIGHTBITS,
        parity=serial.PARITY_NONE,
        stopbits=serial.STOPBITS_ONE,
        timeout=timeout,
    )


def uart_read_line(ser: serial.Serial) -> str:
    """Read a line from UART (blocks until newline or timeout)."""
    line = ser.readline()
    return line.decode("ascii", errors="replace").strip()


def uart_write(ser: serial.Serial, data: str) -> int:
    """Write a string to UART. Returns number of bytes written."""
    return ser.write(data.encode("ascii"))


# Example: Read from GPS module
ser = uart_open("/dev/ttyS0", baudrate=9600, timeout=2.0)
for _ in range(10):
    line = uart_read_line(ser)
    if line.startswith("$GPGGA"):
        print(f"GPS Fix: {line}")
ser.close()
```

### GPS NMEA Sentence Parser

```python
import serial
import time
from dataclasses import dataclass


@dataclass
class GPSFix:
    """Parsed GPS fix data from a GPGGA sentence."""
    timestamp: str
    latitude: float
    longitude: float
    fix_quality: int
    num_satellites: int
    altitude: float


def parse_gpgga(sentence: str) -> GPSFix | None:
    """
    Parse a GPGGA NMEA sentence.

    Example: $GPGGA,123519,4807.038,N,01131.000,E,1,08,0.9,545.4,M,47.0,M,,*47
    """
    if not sentence.startswith("$GPGGA"):
        return None
    parts = sentence.split(",")
    if len(parts) < 15 or not parts[2]:
        return None

    def nmea_to_decimal(value: str, direction: str) -> float:
        """Convert NMEA coordinate (DDMM.MMMM) to decimal degrees."""
        if not value:
            return 0.0
        if direction in ("S", "W"):
            sign = -1
        else:
            sign = 1
        dot_pos = value.index(".")
        degrees = int(value[: dot_pos - 2])
        minutes = float(value[dot_pos - 2 :])
        return sign * (degrees + minutes / 60.0)

    return GPSFix(
        timestamp=parts[1],
        latitude=nmea_to_decimal(parts[2], parts[3]),
        longitude=nmea_to_decimal(parts[4], parts[5]),
        fix_quality=int(parts[6]) if parts[6] else 0,
        num_satellites=int(parts[7]) if parts[7] else 0,
        altitude=float(parts[9]) if parts[9] else 0.0,
    )


def read_gps_stream(port: str = "/dev/ttyS0", baudrate: int = 9600,
                    duration_seconds: float = 10.0) -> list[GPSFix]:
    """Read GPS fixes for a specified duration."""
    fixes = []
    ser = serial.Serial(port, baudrate, timeout=1.0)
    end_time = time.time() + duration_seconds
    while time.time() < end_time:
        line = ser.readline().decode("ascii", errors="replace").strip()
        fix = parse_gpgga(line)
        if fix and fix.fix_quality > 0:
            fixes.append(fix)
    ser.close()
    return fixes
```

### Binary Protocol Parsing

```python
"""Parse binary sensor protocols over UART."""
import serial
import struct
from dataclasses import dataclass


@dataclass
class TFMiniReading:
    """Reading from TFMini-Plus LiDAR sensor."""
    distance_cm: int
    signal_strength: int
    temperature_c: float


def read_tfmini(ser: serial.Serial) -> TFMiniReading | None:
    """
    Read a frame from TFMini-Plus LiDAR.

    Frame format (9 bytes):
    [0x59] [0x59] [Dist_L] [Dist_H] [Str_L] [Str_H] [Temp_L] [Temp_H] [Checksum]
    """
    # Sync to frame header (two 0x59 bytes)
    while True:
        byte = ser.read(1)
        if not byte:
            return None
        if byte[0] == 0x59:
            second = ser.read(1)
            if second and second[0] == 0x59:
                break

    # Read remaining 7 bytes
    payload = ser.read(7)
    if len(payload) != 7:
        return None

    # Verify checksum
    checksum = (0x59 + 0x59 + sum(payload[:6])) & 0xFF
    if checksum != payload[6]:
        return None

    dist = payload[0] | (payload[1] << 8)
    strength = payload[2] | (payload[3] << 8)
    temp_raw = payload[4] | (payload[5] << 8)
    temp_c = temp_raw / 8.0 - 256.0

    return TFMiniReading(
        distance_cm=dist,
        signal_strength=strength,
        temperature_c=temp_c,
    )


# Usage
ser = serial.Serial("/dev/ttyUSB0", 115200, timeout=0.1)
reading = read_tfmini(ser)
if reading:
    print(f"Distance: {reading.distance_cm} cm, "
          f"Strength: {reading.signal_strength}")
ser.close()
```

### Flow Control

```python
import serial


def uart_with_flow_control(port: str, baudrate: int,
                           hw_flow: bool = False,
                           sw_flow: bool = False) -> serial.Serial:
    """
    Open UART with optional flow control.

    hw_flow: Hardware flow control (RTS/CTS) -- requires extra wires.
    sw_flow: Software flow control (XON/XOFF) -- uses in-band signaling.
    """
    return serial.Serial(
        port=port,
        baudrate=baudrate,
        bytesize=serial.EIGHTBITS,
        parity=serial.PARITY_NONE,
        stopbits=serial.STOPBITS_ONE,
        timeout=1.0,
        rtscts=hw_flow,
        xonxoff=sw_flow,
    )
```

---

## GPIO (General Purpose Input/Output)

### Overview

GPIO provides direct digital pin control: high/low output, digital input with optional pull-up/down, edge detection for interrupts, and PWM for analog-like output.

**Use `gpiod` (libgpiod), NOT `RPi.GPIO`.** The `gpiod` library is portable, does not require root, and works across SBCs.

### Installation

```bash
# Install libgpiod system library
sudo apt-get install -y libgpiod-dev gpiod

# Install Python bindings
pip install gpiod
```

### Wiring Diagram (Basic Input/Output)

```
Raspberry Pi
┌──────────────┐
│  GPIO17 (11) ├──────── LED (+) ──── 330 ohm ──── GND
│              │
│  GPIO27 (13) ├──────── Button ──── GND
│              │         (with internal pull-up enabled)
│  GND     (6) ├─────┘
└──────────────┘
```

### Digital Output

```python
"""Control a GPIO output pin using gpiod (libgpiod v2)."""
import gpiod
import time
from gpiod.line import Direction, Value


def blink_led(chip_path: str, line_offset: int,
              count: int = 10, interval: float = 0.5) -> None:
    """Blink an LED on the specified GPIO line."""
    with gpiod.request_lines(
        chip_path,
        consumer="blink-led",
        config={line_offset: gpiod.LineSettings(direction=Direction.OUTPUT)},
    ) as request:
        for _ in range(count):
            request.set_value(line_offset, Value.ACTIVE)
            time.sleep(interval)
            request.set_value(line_offset, Value.INACTIVE)
            time.sleep(interval)


# Raspberry Pi: chip is /dev/gpiochip0 (Pi 4) or /dev/gpiochip4 (Pi 5)
# GPIO17 = line offset 17
blink_led("/dev/gpiochip0", 17, count=5)
```

### Digital Input with Pull-Up

```python
import gpiod
from gpiod.line import Direction, Bias, Value


def read_button(chip_path: str, line_offset: int) -> bool:
    """Read a button state with internal pull-up enabled."""
    with gpiod.request_lines(
        chip_path,
        consumer="read-button",
        config={
            line_offset: gpiod.LineSettings(
                direction=Direction.INPUT,
                bias=Bias.PULL_UP,
            )
        },
    ) as request:
        value = request.get_value(line_offset)
        # With pull-up, button pressed = INACTIVE (grounded)
        return value == Value.INACTIVE


is_pressed = read_button("/dev/gpiochip0", 27)
print(f"Button pressed: {is_pressed}")
```

### Edge Detection (Interrupt-Driven)

```python
import gpiod
import time
from gpiod.line import Direction, Edge, Bias


def wait_for_button_press(chip_path: str, line_offset: int,
                          timeout_seconds: float = 10.0) -> bool:
    """Wait for a falling edge (button press) with timeout."""
    with gpiod.request_lines(
        chip_path,
        consumer="button-edge",
        config={
            line_offset: gpiod.LineSettings(
                direction=Direction.INPUT,
                bias=Bias.PULL_UP,
                edge_detection=Edge.FALLING,
            )
        },
    ) as request:
        if request.wait_edge_events(timeout=timeout_seconds):
            events = request.read_edge_events()
            for event in events:
                print(f"Edge detected on line {event.line_offset} "
                      f"at {event.timestamp_ns}ns")
            return True
        return False  # Timeout


pressed = wait_for_button_press("/dev/gpiochip0", 27, timeout_seconds=5.0)
print(f"Button was pressed: {pressed}")
```

### Ultrasonic Distance (HC-SR04 via GPIO)

```python
"""HC-SR04 ultrasonic sensor using GPIO trigger and echo pins."""
import gpiod
import time
from gpiod.line import Direction, Value, Edge


SPEED_OF_SOUND_CM_PER_US = 0.0343


def measure_distance_cm(chip_path: str, trigger_offset: int,
                        echo_offset: int,
                        timeout: float = 0.1) -> float | None:
    """
    Measure distance using HC-SR04 ultrasonic sensor.

    Args:
        chip_path: GPIO chip device path.
        trigger_offset: GPIO line for TRIGGER pin.
        echo_offset: GPIO line for ECHO pin.
        timeout: Maximum wait time for echo in seconds.

    Returns:
        Distance in centimeters, or None if measurement failed.
    """
    with gpiod.request_lines(
        chip_path,
        consumer="hcsr04",
        config={
            trigger_offset: gpiod.LineSettings(direction=Direction.OUTPUT),
            echo_offset: gpiod.LineSettings(
                direction=Direction.INPUT,
                edge_detection=Edge.BOTH,
            ),
        },
    ) as request:
        # Send 10us trigger pulse
        request.set_value(trigger_offset, Value.INACTIVE)
        time.sleep(0.002)
        request.set_value(trigger_offset, Value.ACTIVE)
        time.sleep(0.00001)  # 10 microseconds
        request.set_value(trigger_offset, Value.INACTIVE)

        # Wait for rising edge (echo start)
        if not request.wait_edge_events(timeout=timeout):
            return None
        events = request.read_edge_events()
        if not events:
            return None
        start_ns = events[-1].timestamp_ns

        # Wait for falling edge (echo end)
        if not request.wait_edge_events(timeout=timeout):
            return None
        events = request.read_edge_events()
        if not events:
            return None
        end_ns = events[-1].timestamp_ns

        # Calculate distance
        pulse_us = (end_ns - start_ns) / 1000.0
        distance_cm = (pulse_us * SPEED_OF_SOUND_CM_PER_US) / 2.0

        if distance_cm < 2 or distance_cm > 400:
            return None  # Out of sensor range
        return distance_cm


# Usage: TRIG on GPIO23, ECHO on GPIO24
dist = measure_distance_cm("/dev/gpiochip0", 23, 24)
if dist is not None:
    print(f"Distance: {dist:.1f} cm")
else:
    print("Measurement failed")
```

### PWM Output (Software PWM)

```python
"""Software PWM using gpiod for servo or LED dimming."""
import gpiod
import time
import threading
from gpiod.line import Direction, Value


class SoftwarePWM:
    """Software PWM on a GPIO pin. For hardware PWM, use the SBC's PWM peripheral."""

    def __init__(self, chip_path: str, line_offset: int,
                 frequency_hz: float = 50.0):
        self.chip_path = chip_path
        self.line_offset = line_offset
        self.frequency_hz = frequency_hz
        self.duty_cycle = 0.0  # 0.0 to 1.0
        self._running = False
        self._thread: threading.Thread | None = None

    def start(self, duty_cycle: float = 0.5) -> None:
        """Start PWM with given duty cycle (0.0 to 1.0)."""
        self.duty_cycle = max(0.0, min(1.0, duty_cycle))
        self._running = True
        self._thread = threading.Thread(target=self._pwm_loop, daemon=True)
        self._thread.start()

    def stop(self) -> None:
        """Stop PWM output."""
        self._running = False
        if self._thread:
            self._thread.join(timeout=1.0)

    def set_duty_cycle(self, duty_cycle: float) -> None:
        """Update duty cycle while running."""
        self.duty_cycle = max(0.0, min(1.0, duty_cycle))

    def _pwm_loop(self) -> None:
        period = 1.0 / self.frequency_hz
        with gpiod.request_lines(
            self.chip_path,
            consumer="soft-pwm",
            config={
                self.line_offset: gpiod.LineSettings(
                    direction=Direction.OUTPUT
                )
            },
        ) as request:
            while self._running:
                if self.duty_cycle > 0:
                    request.set_value(self.line_offset, Value.ACTIVE)
                    time.sleep(period * self.duty_cycle)
                if self.duty_cycle < 1.0:
                    request.set_value(self.line_offset, Value.INACTIVE)
                    time.sleep(period * (1.0 - self.duty_cycle))


# Example: Dim an LED on GPIO18
pwm = SoftwarePWM("/dev/gpiochip0", 18, frequency_hz=1000)
pwm.start(duty_cycle=0.25)  # 25% brightness
time.sleep(2)
pwm.set_duty_cycle(0.75)    # 75% brightness
time.sleep(2)
pwm.stop()
```

---

## Testing Patterns

### Mocking Hardware for Unit Tests

```python
"""Test patterns for sensor code without physical hardware."""
import pytest
from unittest.mock import MagicMock, patch


# Example: Testing an I2C sensor driver
class BME280Driver:
    """Simplified BME280 driver for testing demonstration."""

    def __init__(self, bus_number: int = 1, address: int = 0x76):
        import smbus2
        self.bus = smbus2.SMBus(bus_number)
        self.address = address

    def read_temperature_raw(self) -> int:
        data = self.bus.read_i2c_block_data(self.address, 0xFA, 3)
        return (data[0] << 12) | (data[1] << 4) | (data[2] >> 4)

    def close(self) -> None:
        self.bus.close()


@pytest.fixture
def mock_smbus():
    """Fixture providing a mocked SMBus."""
    with patch("smbus2.SMBus") as mock:
        bus_instance = MagicMock()
        mock.return_value = bus_instance
        yield bus_instance


def test_read_temperature_raw(mock_smbus):
    """Test that raw temperature bytes are correctly assembled."""
    # Simulate reading 3 bytes: [0x80, 0x00, 0x00] -> raw = 0x80000
    mock_smbus.read_i2c_block_data.return_value = [0x80, 0x00, 0x00]
    driver = BME280Driver()
    raw = driver.read_temperature_raw()
    assert raw == 0x80000
    mock_smbus.read_i2c_block_data.assert_called_once_with(0x76, 0xFA, 3)


def test_bus_error_propagates(mock_smbus):
    """Test that OSError from bus read is not silently swallowed."""
    mock_smbus.read_i2c_block_data.side_effect = OSError("I2C bus error")
    driver = BME280Driver()
    with pytest.raises(OSError, match="I2C bus error"):
        driver.read_temperature_raw()
```

### Integration Test with Real Hardware

```python
import pytest
import os

# Skip tests if not running on hardware with I2C
HAS_I2C = os.path.exists("/dev/i2c-1")


@pytest.mark.skipif(not HAS_I2C, reason="No I2C bus available")
class TestI2CHardware:
    """Integration tests that require physical I2C bus."""

    def test_bus_scan_finds_devices(self):
        import smbus2
        bus = smbus2.SMBus(1)
        found = False
        for addr in range(0x03, 0x78):
            try:
                bus.read_byte(addr)
                found = True
                break
            except OSError:
                pass
        bus.close()
        assert found, "No I2C devices detected -- check wiring"

    def test_known_device_responds(self):
        """Verify a known device at a specific address."""
        import smbus2
        bus = smbus2.SMBus(1)
        try:
            bus.read_byte(0x76)  # BME280 expected address
        except OSError:
            pytest.fail("BME280 not responding at 0x76")
        finally:
            bus.close()
```

---

## Common Pitfalls

| Pitfall | Protocol | Solution |
|---------|----------|----------|
| Missing pull-ups | I2C | Add 4.7k ohm resistors on SDA and SCL to VCC |
| Wrong SPI mode | SPI | Check datasheet for CPOL/CPHA; default Mode 0 is not always correct |
| TX/RX swapped | UART | Cross-connect: sensor TX to SBC RX, sensor RX to SBC TX |
| 5V sensor on 3.3V bus | All | Use a level shifter or choose a 3.3V-compatible sensor |
| Permission denied on /dev | All | Add user to `i2c`, `spi`, `dialout` groups: `sudo usermod -aG i2c,spi,dialout $USER` |
| Bus busy after crash | I2C | Reset bus: `i2cdetect -y 1` or reboot; add bus recovery in code |
| Chip select not managed | SPI | Always deassert CS between transactions; use `spidev.SpiDev.no_cs = False` |
| GPIO numbering confusion | GPIO | Use `gpioinfo` to list all lines and their names on your chip |
