# Picar-X Behavior Output Templates

## Behavior Definition Report

```markdown
## Behavior: [Name]

**Goal**: [One sentence description]

**Inputs**:
| Sensor | Read Method | Expected Range |
|--------|------------|----------------|
| [sensor] | [method] | [range] |

**Outputs**:
| Actuator | Write Method | Bounded Range |
|----------|-------------|---------------|
| [actuator] | [method] | [range] |

**Safety Constraints**:
- Max speed: [value]
- Servo bounds: [min, max]
- Timeout: [seconds]
- Emergency stop: [trigger condition]

**Control Loop**:
1. Read [sensors]
2. Compute [decision]
3. Write [actuators]
4. Repeat at [Hz]

<picar-behavior-state>
step: DEFINE
behavior_name: [name]
safety_constraints: [constraints]
control_loop_hz: [hz]
last_action: Behavior defined
next_action: Implement behavior class
blockers: none
</picar-behavior-state>
```

## Test Results Report

```markdown
## Test Results: [Behavior Name]

**Test Type**: [Static | Dynamic]
**Date**: [date]

### Static Tests
| Test | Description | Result |
|------|-------------|--------|
| [test_name] | [what it checks] | PASS/FAIL |

### Dynamic Tests (if applicable)
| Test | Environment | Speed | Duration | Result | Notes |
|------|-------------|-------|----------|--------|-------|
| [test_name] | [description] | [value] | [seconds] | PASS/FAIL | [observations] |

**Safety Verification**:
- [ ] Emergency stop triggered correctly
- [ ] Speed limits respected
- [ ] Servo bounds enforced
- [ ] Timeout watchdog fired on stall

<picar-behavior-state>
step: [TEST_STATIC | TEST_DYNAMIC]
behavior_name: [name]
safety_constraints: [constraints]
control_loop_hz: [hz]
last_action: [tests completed]
next_action: [proceed to next step or fix failures]
blockers: [any test failures]
</picar-behavior-state>
```
