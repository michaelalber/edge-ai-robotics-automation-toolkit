# Picar-X Behavior Conventions

Depth behind the Core Philosophy constraints: principles, the pre-flight safety checklist, per-phase
workflow detail, discipline rules, anti-patterns, and error recovery. Composition patterns are in
`behavior-composition.md`; the hardware/driver API in `picar-x-api.md`.

## Domain Principles

| Principle | Description | Priority |
|-----------|-------------|----------|
| **Safety Constraints** | Hard limits on speed, servo range, runtime; emergency stop always accessible | Critical |
| **Behavior Isolation** | Each behavior reads sensors and produces commands independently; no hidden shared state | Critical |
| **Composability** | Behaviors combine via priority, sequence, parallel patterns with predictable results | Critical |
| **Reactive Control** | Sense-act loops at fixed frequency; respond to current sensor state, not stale data | High |
| **Graceful Degradation** | A failed sensor reduces capability rather than crashing or acting on garbage | High |
| **Deterministic Startup** | Always start in a known safe state: speed zero, servos centered, sensors polled | High |
| **Timeout Watchdogs** | Every motor command expires after a bounded interval; no set-and-forget drive commands | High |
| **Testability** | Every behavior testable with mocked hardware; real-hardware tests are a second pass | High |
| **Observability** | Behaviors log decisions, sensor readings, actuator commands for post-run analysis | Medium |
| **Resource Awareness** | Respect Raspberry Pi CPU/memory; camera processing and control loops share resources | Medium |

## Pre-Flight Hardware Safety Check

Before ANY dynamic test or deployment, verify all:
- [ ] Battery charged and securely connected
- [ ] Wheels off ground OR in a bounded test area
- [ ] Emergency stop mechanism verified working
- [ ] Servo range calibration confirmed
- [ ] Ultrasonic sensor returning valid readings
- [ ] Camera stream active (if a vision behavior)
- [ ] Max speed set to TEST level (≤ 30)
- [ ] Watchdog timeout configured (< 2 seconds)
- [ ] Clear path / no obstacles in the test zone
- [ ] Operator within physical reach of the robot

## Per-Phase Detail

**DEFINE** — name the behavior + one-sentence goal; list sensor inputs (ultrasonic, grayscale,
camera) and actuator outputs (drive motors, steering servo, camera servos); define safety
constraints (max speed, servo bounds, timeout); describe the sense-act loop.

**IMPLEMENT** — class inheriting `Behavior`; implement `setup()`, `update()`, `teardown()`; safety
bounds checking inside `update()`; `teardown()` always stops motors and centers servos; log sensor
reads and actuator writes.

**TEST_STATIC** — mock all hardware; test `update()` produces correct commands for given inputs;
boundary conditions (sensor min/max, obstacle at threshold); `teardown()` issues stop; safety limits
enforced (speed clamping, servo range). All `pytest` tests pass before proceeding.

**TEST_DYNAMIC** — complete the pre-flight checklist; speed at minimum (10-15); run bounded duration
(5-10s); observe and log motion; verify sensor readings match the environment; increase speed
gradually only after clean runs; test physical edge cases.

**COMPOSE** — define priority order (highest = safety); wire into a behavior tree / priority
selector; static-test the composition first; verify higher priority suppresses lower; dynamic-test at low speed.

**DEPLOY** — set operational speed limits; configure production watchdog timeouts; enable logging;
monitor the first full run with operator present; iterate on tuning (speeds, thresholds, timing).

## Discipline Rules

- **Always implement emergency stop first.** Before any behavior logic: verify `EmergencyStop`
  exists and is tested, is wired as highest priority, and triggers on keyboard interrupt, sensor
  timeout, comms loss, and speed-limit-exceeded. If it's missing or untested, STOP and build it.
- **Never deploy untested motor commands.** Before any real motor/servo command: passing static
  tests with mocked hardware; the specific command sequence appears in a test case; speed values and
  servo angles verified against limits in tests. If static tests don't cover it, don't run it.
- **Test at low speed before high speed.** First dynamic test ≤ 15 (of 100); increase in increments
  of 10 only after clean runs; never jump from static to operational speed; document the test speed.
- **Validate sensor readings before acting.** Check the reading is in valid range and not stale; on
  out-of-range/stale, trigger graceful degradation (slow or stop); never act on a single anomalous
  reading — filter or require N consecutive readings.

## Anti-Patterns

| Anti-Pattern | Why It's Dangerous | Correct Approach |
|--------------|--------------------|------------------|
| Monolithic control loop | Untestable, fragile, cannot compose | Isolated behaviors with single responsibility |
| Set-and-forget motor commands | Robot runs away if the loop crashes | Watchdog timeouts; motors stop if not refreshed |
| Raw sensor values in decisions | Noise causes erratic behavior | Filter (moving average, median) before thresholds |
| Testing only on hardware | Slow iteration, risk of damage | Static tests with mocks first, hardware second |
| Shared mutable state between behaviors | Race conditions, unpredictable priority | Each behavior gets an immutable sensor snapshot |
| No speed ramp on startup | Sudden motion, wheel slip, mechanical stress | Ramp speed over 0.5-1 second |
| Hardcoded calibration values | Different robots have different offsets | Load calibration from config; provide a calibration routine |
| Camera processing in control loop | Blocks the sense-act loop, drops control Hz | Vision in a separate thread/process; read latest result |

## Error Recovery

**Motor stall detected** (current spike or no motion despite speed > 0):
1. Speed to 0; wait 1s; check ultrasonic for contact-distance obstacle (< 5cm)
2. Obstacle → back up slowly, re-plan. No obstacle → possible mechanical jam, stop and alert operator
3. Log the stall with a sensor snapshot

**Sensor failure mid-behavior** (ultrasonic returns -1/out-of-range, grayscale all zeros):
1. Mark the sensor unreliable in state; reduce speed to minimum (10)
2. Ultrasonic failed → stop forward motion. Grayscale failed → abandon line following, switch to obstacle avoidance or stop
3. Log the failure with timestamp + last good reading; do NOT continue at full speed with degraded sensing

**Behavior conflict in composition** (contradictory commands):
1. Priority resolves: highest priority wins. Same priority → stop and log the conflict
2. Conditions should be mutually exclusive at the same priority; add guard conditions; re-test the conflict scenario

**Runaway robot** (moving unexpectedly or ignoring stop):
1. Physical intervention: pick up or block the robot; kill the Python process; if that fails, disconnect battery
2. Post-mortem: check watchdog config, verify emergency-stop wiring; add the scenario to tests; never re-run without understanding the cause

**Communication loss (SSH/WiFi drop):**
1. Watchdog timeout MUST auto-stop (this is why watchdogs exist); if unconfigured, physically stop
2. Reconnect, check logs; set the watchdog ≤ 2s for all future runs; consider running critical behaviors locally on the Pi
