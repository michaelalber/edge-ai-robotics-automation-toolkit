# Behavior Composition for Picar-X

## Overview

Behavior-based robotics builds complex robot autonomy from simple, self-contained behaviors that each handle a specific aspect of the robot's interaction with its environment. This reference covers three composition paradigms -- subsumption architecture, behavior trees, and finite state machines -- with concrete Python implementations for the Picar-X platform.

## Behavior Base Class

All behaviors inherit from a common base class that enforces a consistent interface for the composition layer.

```python
from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from typing import Optional
import time


@dataclass
class SensorSnapshot:
    """Immutable snapshot of all sensor readings at a point in time."""
    distance_cm: float = -1.0
    grayscale: tuple = (0, 0, 0)
    line_status: tuple = (1, 1, 1)
    timestamp: float = field(default_factory=time.time)

    @property
    def is_distance_valid(self):
        return self.distance_cm > 0

    @property
    def has_line(self):
        return 0 in self.line_status


@dataclass
class ActuatorCommand:
    """Output command from a behavior to the actuator layer."""
    speed: int = 0               # -100 to 100 (negative = reverse)
    steering_angle: float = 0.0  # -35 to 35
    cam_pan: Optional[float] = None    # None = don't change
    cam_tilt: Optional[float] = None   # None = don't change

    def clamp(self, max_speed=100, max_angle=35):
        """Enforce hard limits on all outputs."""
        self.speed = max(-max_speed, min(max_speed, self.speed))
        self.steering_angle = max(-max_angle, min(max_angle, self.steering_angle))
        if self.cam_pan is not None:
            self.cam_pan = max(-max_angle, min(max_angle, self.cam_pan))
        if self.cam_tilt is not None:
            self.cam_tilt = max(-max_angle, min(max_angle, self.cam_tilt))
        return self


class Behavior(ABC):
    """Base class for all Picar-X behaviors.

    Each behavior:
    - Reads from a SensorSnapshot (immutable, shared)
    - Produces an ActuatorCommand (or None if not applicable)
    - Has a priority for composition
    - Has setup/teardown lifecycle methods
    """

    def __init__(self, name: str, priority: int = 0):
        self.name = name
        self.priority = priority  # Higher number = higher priority
        self._active = False

    @abstractmethod
    def should_activate(self, sensors: SensorSnapshot) -> bool:
        """Return True if this behavior wants to take control."""
        pass

    @abstractmethod
    def compute(self, sensors: SensorSnapshot) -> ActuatorCommand:
        """Compute actuator commands given current sensor state."""
        pass

    def setup(self):
        """Called once when the behavior is first started."""
        self._active = True

    def teardown(self):
        """Called when the behavior is stopped. Must be safe to call multiple times."""
        self._active = False

    def update(self, sensors: SensorSnapshot) -> Optional[ActuatorCommand]:
        """Main entry point called by the composition layer."""
        if self.should_activate(sensors):
            if not self._active:
                self.setup()
            return self.compute(sensors)
        else:
            if self._active:
                self.teardown()
            return None
```

## Subsumption Architecture

Subsumption is Rodney Brooks' original paradigm: layers of behaviors where higher-priority layers suppress (subsume) lower-priority ones. The key insight is that there is no central planner -- behaviors run in parallel and the priority mechanism resolves conflicts.

### Priority-Based Selector

```python
class SubsumptionSelector:
    """Run all behaviors, pick the command from the highest-priority active one.

    Behaviors are sorted by priority (highest first). The first behavior
    whose should_activate() returns True wins -- its command is executed,
    and all lower-priority behaviors are suppressed.
    """

    def __init__(self, behaviors: list[Behavior]):
        self.behaviors = sorted(behaviors, key=lambda b: b.priority, reverse=True)
        self._active_behavior = None

    def update(self, sensors: SensorSnapshot) -> ActuatorCommand:
        for behavior in self.behaviors:
            command = behavior.update(sensors)
            if command is not None:
                if self._active_behavior != behavior:
                    # Log behavior switch for observability
                    if self._active_behavior:
                        print(f"[SUBSUMPTION] {self._active_behavior.name} "
                              f"suppressed by {behavior.name}")
                    self._active_behavior = behavior
                return command.clamp()

        # No behavior active -- stop
        self._active_behavior = None
        return ActuatorCommand(speed=0, steering_angle=0)

    def teardown_all(self):
        for behavior in self.behaviors:
            behavior.teardown()
```

### Subsumption Example: Three-Layer Robot

```python
class EmergencyStop(Behavior):
    """Highest priority: stop if obstacle is dangerously close."""

    def __init__(self, min_distance=10):
        super().__init__("emergency_stop", priority=100)
        self.min_distance = min_distance

    def should_activate(self, sensors):
        return (sensors.is_distance_valid and
                sensors.distance_cm < self.min_distance)

    def compute(self, sensors):
        return ActuatorCommand(speed=0, steering_angle=0)


class ObstacleAvoidance(Behavior):
    """Medium priority: slow down and steer away from obstacles."""

    def __init__(self, caution_distance=40, min_distance=15):
        super().__init__("obstacle_avoidance", priority=50)
        self.caution_distance = caution_distance
        self.min_distance = min_distance

    def should_activate(self, sensors):
        return (sensors.is_distance_valid and
                sensors.distance_cm < self.caution_distance)

    def compute(self, sensors):
        # Proportional speed reduction
        ratio = sensors.distance_cm / self.caution_distance
        speed = int(15 * ratio)  # Slow down as obstacle gets closer

        # Steer away (simple: always turn right)
        # A smarter version would scan left/right to pick the clearer side
        return ActuatorCommand(speed=max(speed, 5), steering_angle=25)


class Cruise(Behavior):
    """Lowest priority: drive forward when nothing else is happening."""

    def __init__(self, cruise_speed=25):
        super().__init__("cruise", priority=10)
        self.cruise_speed = cruise_speed

    def should_activate(self, sensors):
        return True  # Always willing to cruise

    def compute(self, sensors):
        return ActuatorCommand(speed=self.cruise_speed, steering_angle=0)


# Composition
robot = SubsumptionSelector([
    EmergencyStop(min_distance=10),
    ObstacleAvoidance(caution_distance=40),
    Cruise(cruise_speed=25),
])
```

## Behavior Trees

Behavior trees provide a more structured composition model with explicit control flow: sequences (do all in order), selectors (try each until one succeeds), and decorators (modify child behavior).

### Node Types

```python
from enum import Enum


class NodeStatus(Enum):
    SUCCESS = "success"
    FAILURE = "failure"
    RUNNING = "running"


class BTNode(ABC):
    """Base node for behavior trees."""

    def __init__(self, name: str):
        self.name = name

    @abstractmethod
    def tick(self, sensors: SensorSnapshot) -> tuple[NodeStatus, Optional[ActuatorCommand]]:
        """Execute one tick of this node.

        Returns:
            (status, command) -- status indicates success/failure/running,
            command is the actuator output (or None).
        """
        pass

    def reset(self):
        """Reset node state for a new tree traversal."""
        pass


class Sequence(BTNode):
    """Execute children in order. Fails if any child fails.
    Returns RUNNING if a child is still running.
    Returns SUCCESS only when all children succeed.
    """

    def __init__(self, name: str, children: list[BTNode]):
        super().__init__(name)
        self.children = children
        self._current_index = 0

    def tick(self, sensors):
        while self._current_index < len(self.children):
            child = self.children[self._current_index]
            status, command = child.tick(sensors)
            if status == NodeStatus.FAILURE:
                self._current_index = 0
                return NodeStatus.FAILURE, command
            if status == NodeStatus.RUNNING:
                return NodeStatus.RUNNING, command
            self._current_index += 1

        self._current_index = 0
        return NodeStatus.SUCCESS, None

    def reset(self):
        self._current_index = 0
        for child in self.children:
            child.reset()


class Selector(BTNode):
    """Try children in order. Succeeds if any child succeeds.
    Returns RUNNING if a child is still running.
    Returns FAILURE only when all children fail.
    """

    def __init__(self, name: str, children: list[BTNode]):
        super().__init__(name)
        self.children = children

    def tick(self, sensors):
        for child in self.children:
            status, command = child.tick(sensors)
            if status == NodeStatus.SUCCESS:
                return NodeStatus.SUCCESS, command
            if status == NodeStatus.RUNNING:
                return NodeStatus.RUNNING, command
        return NodeStatus.FAILURE, None

    def reset(self):
        for child in self.children:
            child.reset()


class Condition(BTNode):
    """Leaf node: checks a condition, returns SUCCESS or FAILURE."""

    def __init__(self, name: str, check_fn):
        super().__init__(name)
        self._check_fn = check_fn

    def tick(self, sensors):
        if self._check_fn(sensors):
            return NodeStatus.SUCCESS, None
        return NodeStatus.FAILURE, None


class Action(BTNode):
    """Leaf node: produces an actuator command."""

    def __init__(self, name: str, action_fn):
        super().__init__(name)
        self._action_fn = action_fn

    def tick(self, sensors):
        command = self._action_fn(sensors)
        return NodeStatus.SUCCESS, command
```

### Decorators

```python
class Inverter(BTNode):
    """Inverts child's SUCCESS/FAILURE. RUNNING passes through."""

    def __init__(self, name: str, child: BTNode):
        super().__init__(name)
        self.child = child

    def tick(self, sensors):
        status, command = self.child.tick(sensors)
        if status == NodeStatus.SUCCESS:
            return NodeStatus.FAILURE, command
        if status == NodeStatus.FAILURE:
            return NodeStatus.SUCCESS, command
        return NodeStatus.RUNNING, command


class RepeatUntilFail(BTNode):
    """Keeps ticking child until it fails. Returns RUNNING while child succeeds."""

    def __init__(self, name: str, child: BTNode):
        super().__init__(name)
        self.child = child

    def tick(self, sensors):
        status, command = self.child.tick(sensors)
        if status == NodeStatus.FAILURE:
            return NodeStatus.SUCCESS, command
        return NodeStatus.RUNNING, command
```

### Behavior Tree Example: Obstacle-Aware Line Following

```python
def build_line_follow_tree():
    """
    Tree structure:
        Selector (root)
        ├── Sequence (emergency)
        │   ├── Condition: obstacle_very_close
        │   └── Action: full_stop
        ├── Sequence (avoid_obstacle)
        │   ├── Condition: obstacle_nearby
        │   └── Action: slow_and_steer_away
        └── Sequence (follow_line)
            ├── Condition: line_detected
            └── Action: steer_to_line
    """

    def obstacle_very_close(sensors):
        return sensors.is_distance_valid and sensors.distance_cm < 10

    def obstacle_nearby(sensors):
        return sensors.is_distance_valid and sensors.distance_cm < 30

    def line_detected(sensors):
        return sensors.has_line

    def full_stop(sensors):
        return ActuatorCommand(speed=0, steering_angle=0)

    def slow_and_steer(sensors):
        return ActuatorCommand(speed=10, steering_angle=25)

    def steer_to_line(sensors):
        left, middle, right = sensors.line_status
        if left == 0 and middle == 1 and right == 1:
            return ActuatorCommand(speed=20, steering_angle=-20)
        elif left == 1 and middle == 1 and right == 0:
            return ActuatorCommand(speed=20, steering_angle=20)
        elif middle == 0:
            return ActuatorCommand(speed=25, steering_angle=0)
        else:
            # Lost the line -- go straight slowly
            return ActuatorCommand(speed=10, steering_angle=0)

    tree = Selector("root", [
        Sequence("emergency", [
            Condition("obstacle_very_close", obstacle_very_close),
            Action("full_stop", full_stop),
        ]),
        Sequence("avoid_obstacle", [
            Condition("obstacle_nearby", obstacle_nearby),
            Action("slow_and_steer", slow_and_steer),
        ]),
        Sequence("follow_line", [
            Condition("line_detected", line_detected),
            Action("steer_to_line", steer_to_line),
        ]),
    ])

    return tree
```

### Running the Behavior Tree

```python
class BehaviorTreeRunner:
    """Ticks a behavior tree at a fixed rate and applies commands to the robot."""

    def __init__(self, px, tree: BTNode, hz=20, max_speed=30):
        self._px = px
        self._tree = tree
        self._hz = hz
        self._max_speed = max_speed
        self._running = False

    def read_sensors(self) -> SensorSnapshot:
        distance = self._px.get_distance()
        grayscale = tuple(self._px.get_grayscale_data())
        line_status = tuple(self._px.get_line_status())
        return SensorSnapshot(
            distance_cm=distance,
            grayscale=grayscale,
            line_status=line_status,
        )

    def apply_command(self, cmd: ActuatorCommand):
        cmd.clamp(max_speed=self._max_speed)
        self._px.set_dir_servo_angle(cmd.steering_angle)
        if cmd.speed > 0:
            self._px.forward(cmd.speed)
        elif cmd.speed < 0:
            self._px.backward(abs(cmd.speed))
        else:
            self._px.stop()
        if cmd.cam_pan is not None:
            self._px.set_cam_pan_angle(cmd.cam_pan)
        if cmd.cam_tilt is not None:
            self._px.set_cam_tilt_angle(cmd.cam_tilt)

    def run(self):
        interval = 1.0 / self._hz
        self._running = True
        try:
            while self._running:
                loop_start = time.time()
                sensors = self.read_sensors()
                status, command = self._tree.tick(sensors)
                if command:
                    self.apply_command(command)
                else:
                    self._px.stop()
                elapsed = time.time() - loop_start
                sleep_time = interval - elapsed
                if sleep_time > 0:
                    time.sleep(sleep_time)
        finally:
            self._px.stop()

    def stop(self):
        self._running = False
```

## Finite State Machines

FSMs are useful when behaviors have distinct operational modes with explicit transitions. Better than behavior trees when the number of states is small and transitions are well-defined.

```python
from enum import Enum, auto


class RobotState(Enum):
    IDLE = auto()
    LINE_FOLLOWING = auto()
    OBSTACLE_DETECTED = auto()
    OBSTACLE_AVOIDING = auto()
    RECOVERING = auto()
    STOPPED = auto()


class StateMachine:
    """Generic finite state machine for robot control."""

    def __init__(self):
        self._state = RobotState.IDLE
        self._handlers = {}
        self._transitions = {}
        self._on_enter = {}
        self._on_exit = {}

    @property
    def state(self):
        return self._state

    def add_state(self, state, handler, on_enter=None, on_exit=None):
        """Register a state handler function.

        handler(sensors) -> (ActuatorCommand, next_state_or_None)
        """
        self._handlers[state] = handler
        if on_enter:
            self._on_enter[state] = on_enter
        if on_exit:
            self._on_exit[state] = on_exit

    def transition_to(self, new_state):
        if new_state == self._state:
            return
        if self._state in self._on_exit:
            self._on_exit[self._state]()
        old_state = self._state
        self._state = new_state
        if new_state in self._on_enter:
            self._on_enter[new_state]()
        print(f"[FSM] {old_state.name} -> {new_state.name}")

    def update(self, sensors: SensorSnapshot) -> ActuatorCommand:
        handler = self._handlers.get(self._state)
        if handler is None:
            return ActuatorCommand(speed=0, steering_angle=0)

        command, next_state = handler(sensors)
        if next_state is not None and next_state != self._state:
            self.transition_to(next_state)
        return command
```

### FSM Example: Line Following with Obstacle Handling

```python
def build_line_follow_fsm():
    fsm = StateMachine()
    avoid_start_time = None

    def idle_handler(sensors):
        if sensors.has_line:
            return ActuatorCommand(speed=0), RobotState.LINE_FOLLOWING
        return ActuatorCommand(speed=0), None

    def line_following_handler(sensors):
        # Check for obstacles first
        if sensors.is_distance_valid and sensors.distance_cm < 20:
            return ActuatorCommand(speed=0), RobotState.OBSTACLE_DETECTED

        # Follow the line
        if not sensors.has_line:
            return ActuatorCommand(speed=10, steering_angle=0), RobotState.RECOVERING

        left, middle, right = sensors.line_status
        if left == 0:
            cmd = ActuatorCommand(speed=20, steering_angle=-20)
        elif right == 0:
            cmd = ActuatorCommand(speed=20, steering_angle=20)
        else:
            cmd = ActuatorCommand(speed=25, steering_angle=0)
        return cmd, None

    def obstacle_detected_handler(sensors):
        nonlocal avoid_start_time
        avoid_start_time = time.time()
        return ActuatorCommand(speed=0), RobotState.OBSTACLE_AVOIDING

    def obstacle_avoiding_handler(sensors):
        nonlocal avoid_start_time
        elapsed = time.time() - avoid_start_time

        # Time-based avoidance maneuver
        if elapsed < 1.0:
            # Back up
            return ActuatorCommand(speed=-15, steering_angle=0), None
        elif elapsed < 2.5:
            # Turn right
            return ActuatorCommand(speed=15, steering_angle=30), None
        else:
            # Try to find the line again
            return ActuatorCommand(speed=15, steering_angle=0), RobotState.RECOVERING

    def recovering_handler(sensors):
        if sensors.has_line:
            return ActuatorCommand(speed=15), RobotState.LINE_FOLLOWING

        # Spiral search: slow forward with gentle turn
        return ActuatorCommand(speed=10, steering_angle=-15), None

    fsm.add_state(RobotState.IDLE, idle_handler)
    fsm.add_state(RobotState.LINE_FOLLOWING, line_following_handler)
    fsm.add_state(RobotState.OBSTACLE_DETECTED, obstacle_detected_handler)
    fsm.add_state(RobotState.OBSTACLE_AVOIDING, obstacle_avoiding_handler)
    fsm.add_state(RobotState.RECOVERING, recovering_handler)
    fsm.add_state(RobotState.STOPPED, lambda s: (ActuatorCommand(speed=0), None))

    return fsm
```

## Common Behaviors

### Wall Following

```python
class WallFollower(Behavior):
    """Follow a wall at a target distance using the ultrasonic sensor.

    Assumes the ultrasonic sensor faces forward. The robot drives parallel
    to the wall by making small steering adjustments based on distance
    readings.
    """

    def __init__(self, target_distance=25, tolerance=5, speed=20):
        super().__init__("wall_following", priority=30)
        self.target_distance = target_distance
        self.tolerance = tolerance
        self.speed = speed

    def should_activate(self, sensors):
        if not sensors.is_distance_valid:
            return False
        return sensors.distance_cm < (self.target_distance + self.tolerance + 20)

    def compute(self, sensors):
        error = sensors.distance_cm - self.target_distance

        if abs(error) < self.tolerance:
            # Within tolerance, drive straight
            return ActuatorCommand(speed=self.speed, steering_angle=0)
        elif error > 0:
            # Too far from wall, steer toward it (left, assuming wall is on left)
            angle = -min(25, error * 2)
            return ActuatorCommand(speed=self.speed, steering_angle=angle)
        else:
            # Too close to wall, steer away
            angle = min(25, abs(error) * 2)
            return ActuatorCommand(speed=max(10, self.speed - 5), steering_angle=angle)
```

### Patrol (Waypoint Sequence)

```python
class Patrol(Behavior):
    """Drive a timed sequence of movements to patrol an area.

    Waypoints are (speed, steering_angle, duration_seconds) tuples.
    The robot executes them in order, then loops.
    """

    def __init__(self, waypoints=None):
        super().__init__("patrol", priority=20)
        self.waypoints = waypoints or [
            (20, 0, 2.0),      # Forward 2s
            (15, 30, 1.0),     # Turn right 1s
            (20, 0, 2.0),      # Forward 2s
            (15, -30, 1.0),    # Turn left 1s
        ]
        self._current_wp = 0
        self._wp_start_time = None

    def should_activate(self, sensors):
        return True  # Patrol is a default behavior

    def setup(self):
        super().setup()
        self._current_wp = 0
        self._wp_start_time = time.time()

    def compute(self, sensors):
        if self._wp_start_time is None:
            self._wp_start_time = time.time()

        speed, angle, duration = self.waypoints[self._current_wp]
        elapsed = time.time() - self._wp_start_time

        if elapsed >= duration:
            self._current_wp = (self._current_wp + 1) % len(self.waypoints)
            self._wp_start_time = time.time()
            speed, angle, duration = self.waypoints[self._current_wp]

        return ActuatorCommand(speed=speed, steering_angle=angle)
```

### Object Tracking (Camera-Based)

```python
class ObjectTracker(Behavior):
    """Track a detected object by panning the camera and steering toward it.

    Expects object detection results to be provided via an external
    vision pipeline that writes to a shared result object.
    """

    def __init__(self, detection_source, speed=15):
        super().__init__("object_tracking", priority=40)
        self._detection_source = detection_source
        self._speed = speed
        self._frame_center_x = 320  # Assuming 640px wide frame

    def should_activate(self, sensors):
        detection = self._detection_source.latest
        return detection is not None and detection.confidence > 0.5

    def compute(self, sensors):
        detection = self._detection_source.latest
        if detection is None:
            return ActuatorCommand(speed=0, steering_angle=0)

        # Compute error from frame center
        error_x = detection.center_x - self._frame_center_x
        normalized_error = error_x / self._frame_center_x  # -1 to 1

        # Pan camera toward object
        cam_pan = normalized_error * 35

        # Steer robot toward object (less aggressively than camera)
        steering = normalized_error * 20

        # Speed based on object size (closer = bigger = slower)
        size_ratio = detection.width / 640
        speed = max(10, int(self._speed * (1 - size_ratio)))

        return ActuatorCommand(
            speed=speed,
            steering_angle=steering,
            cam_pan=cam_pan,
        )
```

## Safety Wrapper Patterns

### Speed Ramp

```python
class SpeedRamp:
    """Gradually ramp speed up or down to prevent sudden motion."""

    def __init__(self, ramp_rate=10):
        """
        Args:
            ramp_rate: Maximum speed change per update cycle (units per tick).
        """
        self._ramp_rate = ramp_rate
        self._current_speed = 0

    def apply(self, target_speed: int) -> int:
        diff = target_speed - self._current_speed
        if abs(diff) <= self._ramp_rate:
            self._current_speed = target_speed
        elif diff > 0:
            self._current_speed += self._ramp_rate
        else:
            self._current_speed -= self._ramp_rate
        return self._current_speed

    def reset(self):
        self._current_speed = 0
```

### Timeout Guard

```python
class TimeoutGuard:
    """Wraps a behavior to enforce a maximum run duration."""

    def __init__(self, behavior: Behavior, max_duration: float):
        self._behavior = behavior
        self._max_duration = max_duration
        self._start_time = None

    def update(self, sensors: SensorSnapshot) -> Optional[ActuatorCommand]:
        command = self._behavior.update(sensors)
        if command is not None:
            if self._start_time is None:
                self._start_time = time.time()
            elapsed = time.time() - self._start_time
            if elapsed > self._max_duration:
                print(f"[TIMEOUT] {self._behavior.name} exceeded "
                      f"{self._max_duration}s -- forcing stop")
                self._behavior.teardown()
                self._start_time = None
                return ActuatorCommand(speed=0, steering_angle=0)
        else:
            self._start_time = None
        return command
```

### Safe Execution Context

```python
import signal
import threading


class SafeExecutionContext:
    """Context manager that ensures the robot stops on any exit condition."""

    def __init__(self, px, watchdog_timeout=1.5, max_speed=30):
        self._px = px
        self._watchdog_timeout = watchdog_timeout
        self._max_speed = max_speed
        self._watchdog = None
        self._original_sigint = None

    def __enter__(self):
        # Install signal handler for clean shutdown
        self._original_sigint = signal.getsignal(signal.SIGINT)
        signal.signal(signal.SIGINT, self._shutdown_handler)

        # Start watchdog
        self._watchdog = MotorWatchdog(self._px, self._watchdog_timeout)
        self._watchdog.start()

        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        self._px.stop()
        self._px.set_dir_servo_angle(0)
        if self._watchdog:
            self._watchdog.stop()
        signal.signal(signal.SIGINT, self._original_sigint)
        return False  # Don't suppress exceptions

    def _shutdown_handler(self, signum, frame):
        print("\n[SAFE EXIT] Stopping robot...")
        self._px.stop()
        raise KeyboardInterrupt


class MotorWatchdog:
    """Stops motors if refresh() is not called within timeout."""

    def __init__(self, px, timeout=1.5):
        self._px = px
        self._timeout = timeout
        self._last_refresh = time.time()
        self._running = False
        self._thread = None

    def start(self):
        self._running = True
        self._last_refresh = time.time()
        self._thread = threading.Thread(target=self._monitor, daemon=True)
        self._thread.start()

    def stop(self):
        self._running = False
        if self._thread:
            self._thread.join(timeout=2)

    def refresh(self):
        self._last_refresh = time.time()

    def _monitor(self):
        while self._running:
            if time.time() - self._last_refresh > self._timeout:
                print(f"[WATCHDOG] Timeout -- stopping motors")
                self._px.stop()
            time.sleep(0.1)
```

## Testing Behaviors

### Unit Tests with Mocked Hardware

Static tests verify behavior logic without any real hardware. Mock the `Picarx` object and test that behaviors produce correct commands for given sensor inputs.

```python
import pytest
from unittest.mock import MagicMock


class TestEmergencyStop:
    def test_activates_when_obstacle_very_close(self):
        behavior = EmergencyStop(min_distance=10)
        sensors = SensorSnapshot(distance_cm=5.0)
        assert behavior.should_activate(sensors) is True

    def test_does_not_activate_when_clear(self):
        behavior = EmergencyStop(min_distance=10)
        sensors = SensorSnapshot(distance_cm=50.0)
        assert behavior.should_activate(sensors) is False

    def test_produces_zero_speed_command(self):
        behavior = EmergencyStop(min_distance=10)
        sensors = SensorSnapshot(distance_cm=5.0)
        command = behavior.compute(sensors)
        assert command.speed == 0
        assert command.steering_angle == 0

    def test_does_not_activate_on_invalid_reading(self):
        behavior = EmergencyStop(min_distance=10)
        sensors = SensorSnapshot(distance_cm=-1.0)
        assert behavior.should_activate(sensors) is False


class TestObstacleAvoidance:
    def test_activates_within_caution_distance(self):
        behavior = ObstacleAvoidance(caution_distance=40)
        sensors = SensorSnapshot(distance_cm=25.0)
        assert behavior.should_activate(sensors) is True

    def test_slows_down_proportionally(self):
        behavior = ObstacleAvoidance(caution_distance=40)
        close = SensorSnapshot(distance_cm=10.0)
        far = SensorSnapshot(distance_cm=35.0)
        close_cmd = behavior.compute(close)
        far_cmd = behavior.compute(far)
        assert close_cmd.speed < far_cmd.speed

    def test_steers_away(self):
        behavior = ObstacleAvoidance(caution_distance=40)
        sensors = SensorSnapshot(distance_cm=20.0)
        command = behavior.compute(sensors)
        assert command.steering_angle != 0


class TestSubsumptionSelector:
    def test_highest_priority_wins(self):
        estop = EmergencyStop(min_distance=10)
        cruise = Cruise(cruise_speed=25)
        selector = SubsumptionSelector([cruise, estop])

        sensors = SensorSnapshot(distance_cm=5.0)
        command = selector.update(sensors)
        assert command.speed == 0  # Emergency stop wins

    def test_lower_priority_when_higher_inactive(self):
        estop = EmergencyStop(min_distance=10)
        cruise = Cruise(cruise_speed=25)
        selector = SubsumptionSelector([cruise, estop])

        sensors = SensorSnapshot(distance_cm=100.0)
        command = selector.update(sensors)
        assert command.speed == 25  # Cruise active


class TestActuatorCommand:
    def test_clamp_enforces_speed_limit(self):
        cmd = ActuatorCommand(speed=80)
        cmd.clamp(max_speed=30)
        assert cmd.speed == 30

    def test_clamp_enforces_negative_speed(self):
        cmd = ActuatorCommand(speed=-80)
        cmd.clamp(max_speed=30)
        assert cmd.speed == -30

    def test_clamp_enforces_steering_range(self):
        cmd = ActuatorCommand(steering_angle=50)
        cmd.clamp(max_angle=35)
        assert cmd.steering_angle == 35
```

### Integration Tests with Real Hardware

These tests run on the actual Picar-X. They must be run with the pre-flight checklist completed and an operator present.

```python
import pytest
import time


# Mark all tests in this module as requiring hardware
pytestmark = pytest.mark.hardware


@pytest.fixture
def px():
    """Provide a Picarx instance with safety limits."""
    from picarx import Picarx
    robot = Picarx()
    robot.stop()
    robot.set_dir_servo_angle(0)
    yield robot
    robot.stop()
    robot.set_dir_servo_angle(0)


class TestHardwareSensors:
    def test_ultrasonic_returns_valid_reading(self, px):
        distance = px.get_distance()
        # Should get a positive number in a normal room
        assert distance > 0, f"Ultrasonic returned {distance}"
        assert distance < 400, f"Ultrasonic reading implausible: {distance}"

    def test_grayscale_returns_three_channels(self, px):
        data = px.get_grayscale_data()
        assert len(data) == 3
        for channel in data:
            assert 0 <= channel <= 4095


class TestHardwareMotors:
    def test_forward_and_stop(self, px):
        """Drive forward briefly at minimum speed, then stop."""
        px.forward(10)
        time.sleep(0.5)
        px.stop()
        # Visual verification: robot moved slightly forward

    def test_steering_range(self, px):
        """Sweep steering servo across range."""
        for angle in [-30, -15, 0, 15, 30]:
            px.set_dir_servo_angle(angle)
            time.sleep(0.3)
        px.set_dir_servo_angle(0)
```

### Running Tests

```bash
# Run static tests only (no hardware needed)
pytest tests/ -m "not hardware" -v

# Run hardware tests (robot must be set up and ready)
pytest tests/ -m "hardware" -v --timeout=30

# Run all tests with coverage
pytest tests/ -v --cov=behaviors --cov-report=term-missing
```

## Putting It All Together

A complete main program that composes behaviors with full safety wrapping:

```python
from picarx import Picarx
import time


def main():
    px = Picarx()

    # Build behavior layers
    estop = EmergencyStop(min_distance=10)
    avoid = ObstacleAvoidance(caution_distance=40)
    cruise = Cruise(cruise_speed=20)

    robot = SubsumptionSelector([estop, avoid, cruise])
    ramp = SpeedRamp(ramp_rate=5)

    with SafeExecutionContext(px, watchdog_timeout=1.5, max_speed=30) as ctx:
        interval = 1.0 / 20  # 20 Hz

        while True:
            loop_start = time.time()

            # Read sensors
            sensors = SensorSnapshot(
                distance_cm=px.get_distance(),
                grayscale=tuple(px.get_grayscale_data()),
                line_status=tuple(px.get_line_status()),
            )

            # Get command from behavior system
            command = robot.update(sensors)

            # Apply speed ramp for smooth acceleration
            ramped_speed = ramp.apply(command.speed)

            # Apply to hardware
            px.set_dir_servo_angle(command.steering_angle)
            if ramped_speed > 0:
                px.forward(ramped_speed)
            elif ramped_speed < 0:
                px.backward(abs(ramped_speed))
            else:
                px.stop()

            # Refresh watchdog
            ctx._watchdog.refresh()

            # Maintain loop rate
            elapsed = time.time() - loop_start
            sleep_time = interval - elapsed
            if sleep_time > 0:
                time.sleep(sleep_time)


if __name__ == "__main__":
    main()
```
