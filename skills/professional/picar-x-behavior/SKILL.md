---
name: picar-x-behavior
audience: professional
description: >
  Build composable robot behaviors for SunFounder Picar-X. Use when creating
  autonomous driving behaviors, sensor-reactive patterns, and behavior trees for
  the Picar-X robot platform. Do NOT use when the platform is not a SunFounder
  Picar-X without first adapting the API references; Do NOT use when the goal is
  general robotics outside the Picar-X hardware profile.
---

# Picar-X Behavior Composer

> "The world is its own best model. The trick is to sense it appropriately and often enough."
> -- Rodney Brooks, *Intelligence Without Representation*

## Core Philosophy

This skill builds composable, safe robot behaviors for the SunFounder Picar-X. Behaviors are small,
testable units of reactive control that combine into complex autonomous systems through well-defined
composition patterns — priority, sequence, and parallel. Each behavior senses and acts
independently; safety is enforced at the driver layer, not just the behavior layer; and nothing
reaches real motors before it passes static tests with mocked hardware.

**Non-Negotiable Constraints:**
1. SAFETY FIRST — every behavior tree includes an emergency stop at the highest priority. No exceptions.
2. TEST INCREMENTALLY — validate each behavior in static tests (no motors) before any dynamic test on real hardware.
3. COMPOSE FROM SIMPLE — build complex behaviors by composing verified simple ones; never a monolithic control loop.
4. BOUND ALL OUTPUTS — motor speeds, servo angles, and timing have hard limits enforced at the driver layer.
5. FAIL SAFE — any unhandled exception, sensor timeout, or comms failure results in a full stop, not continued operation.

Full principle table, the pre-flight safety checklist, per-phase detail, discipline rules,
anti-patterns, and error recovery live in `references/conventions.md`.

## Workflow

```
DEFINE        Name + one-sentence goal; sensor inputs; actuator outputs; safety constraints; sense-act loop.
IMPLEMENT     Behavior subclass: setup()/update()/teardown(); bounds checks in update(); teardown()
              always stops motors + centers servos; log reads/writes.
TEST_STATIC   Mock all hardware; test update() command mapping, boundary conditions, teardown stop,
              and safety-limit enforcement. All pytest pass before proceeding.
TEST_DYNAMIC  Complete the pre-flight safety checklist (conventions.md). Speed 10-15; bounded run
              (5-10s); observe + log; raise speed gradually only after clean runs.
COMPOSE       Priority order (highest = safety); wire a behavior tree / priority selector
              (patterns in behavior-composition.md); static-test first; verify suppression; low-speed dynamic test.
DEPLOY        Operational speed limits; production watchdog timeouts; logging; monitor the first run
              with operator present; iterate on tuning.
```

**Exit criteria:** a verified emergency-stop behavior wired at highest priority; each behavior passes
static tests with mocked hardware before any hardware run; dynamic tests started at ≤ 15 speed and
ramped only after clean runs; composed system suppresses lower priorities correctly; watchdog
timeouts configured. Driver API in `references/picar-x-api.md`.

## State Block

```
<picar-behavior-state>
step: DEFINE | IMPLEMENT | TEST_STATIC | TEST_DYNAMIC | COMPOSE | DEPLOY
behavior_name: [e.g., "obstacle_avoidance", "line_following", "object_tracking"]
safety_constraints: [e.g., "max_speed=30, emergency_stop=enabled, min_distance=25cm"]
control_loop_hz: [number, e.g., 20]
last_action: [what was just done]
next_action: [what should happen next]
blockers: [any issues]
</picar-behavior-state>
```

## Output Template

- **Behavior definition report, test results report** — `references/output-templates.md`.
- **Composition patterns (priority / sequence / parallel, behavior trees)** — `references/behavior-composition.md`.
- **Hardware/driver API (motors, servos, ultrasonic, grayscale, camera)** — `references/picar-x-api.md`.
- **Principle table, pre-flight checklist, per-phase detail, discipline rules, anti-patterns, error recovery** — `references/conventions.md`.

## Integration with Other Skills

| Skill | Relationship |
|-------|-------------|
| `sensor-integration` | Build and calibrate sensor pipelines (ultrasonic filtering, grayscale normalization, camera capture); feed processed data into behaviors. |
| `edge-cv-pipeline` | Build CV pipelines (object/lane/sign detection) on the Pi; vision behaviors consume their outputs. |
| `tdd` / `tdd-agent` | Apply TDD when implementing behavior classes — failing tests for sensor-to-actuator logic before implementation, especially for static tests with mocked hardware. |
| `jetson-deploy` | If offloading heavy CV inference to a Jetson, use it for deployment; the Picar-X reads inference results over the network. |
