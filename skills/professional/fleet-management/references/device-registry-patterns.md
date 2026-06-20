# Device Registry Patterns for Edge Fleets

## Overview

A device registry is the authoritative inventory of all devices in an edge fleet. It tracks what devices exist, what capabilities they have, what software they run, and what state they are in. Without an accurate registry, fleet deployments are blind -- you cannot deploy to what you cannot track, and you cannot roll back what you do not know is deployed.

This reference covers device inventory management, capability tagging, group-based deployment targeting, heartbeat monitoring, and offline device handling.

---

## Device Registry Data Model

### Core Device Record

Every device in the fleet must have a registry entry with at minimum these fields:

```yaml
device:
  # Identity
  id: "edge-jetson-prod-042"           # Unique, immutable device ID
  hostname: "jetson-042.factory-a.local"
  serial_number: "1425000012345"
  mac_address: "00:04:4b:e6:a3:12"

  # Hardware
  hardware:
    type: "jetson-orin-nano"            # Device type identifier
    architecture: "aarch64"             # CPU architecture
    cpu_cores: 6
    ram_mb: 8192
    gpu: "NVIDIA Orin (1024 CUDA cores)"
    disk_total_mb: 65536
    has_gpu: true

  # Software
  software:
    os: "Ubuntu 22.04"
    kernel: "5.15.136-tegra"
    jetpack_version: "6.0"
    cuda_version: "12.2"
    container_runtime: "docker"
    container_runtime_version: "24.0.7"

  # Deployment
  deployment:
    current_version: "2.3.0"
    previous_version: "2.2.1"
    last_deployed: "2025-01-15T14:30:00Z"
    deployment_slot: "blue"             # For blue-green deployments
    rollback_available: true
    rollback_version: "2.2.1"

  # Status
  status:
    state: "healthy"                    # healthy | degraded | failed | offline | maintenance
    last_heartbeat: "2025-01-16T10:45:00Z"
    uptime_seconds: 72000
    connectivity: "online"              # online | offline | intermittent

  # Tags and Groups
  tags:
    environment: "production"
    region: "factory-a"
    line: "assembly-3"
    role: "quality-inspection"
    priority: "high"
  groups:
    - "production-fleet"
    - "factory-a-devices"
    - "gpu-capable"
    - "jetson-devices"

  # Metadata
  metadata:
    registered: "2024-06-01T09:00:00Z"
    last_updated: "2025-01-16T10:45:00Z"
    notes: "Installed on assembly line 3, camera mount position B"
    physical_location: "Building 4, Floor 2, Rack 7, Slot 3"
```

### Device State Machine

```
                    +-- register ---> PROVISIONING
                    |                      |
                    |                 provision complete
                    |                      |
                    |                      v
                    |                   HEALTHY <--------+
                    |                   /  |  \          |
                    |         degrade  /   |   \ recover |
                    |                v     |    v        |
                    |          DEGRADED    |  MAINTENANCE |
                    |                \     |    /        |
                    |          fail   \    |   / restore |
                    |                  v   v  v          |
                    |                  FAILED            |
                    |                    |               |
                    |              recover/repair -------+
                    |
                    |              heartbeat timeout
        HEALTHY/DEGRADED ---------------------> OFFLINE
                    ^                              |
                    |          heartbeat resume     |
                    +------------------------------+

        ANY STATE ---------> DECOMMISSIONED (terminal)
```

### Device Status Definitions

```
PROVISIONING:
  Device is registered but not yet ready for deployments.
  First-time setup, OS installation, or initial configuration in progress.
  NOT eligible for deployment targeting.

HEALTHY:
  Device is online, all health checks pass, application is functional.
  Eligible for deployment targeting.

DEGRADED:
  Device is online, some health checks show warnings but no failures.
  Examples: high CPU usage, low disk space, elevated temperature.
  Eligible for deployment targeting (with caution).
  May be excluded from canary selection.

FAILED:
  Device is online but application is non-functional.
  Examples: crash loop, health endpoint returning errors, OOM kills.
  NOT eligible for new deployments.
  Candidate for rollback or manual intervention.

OFFLINE:
  Device has not sent a heartbeat within the timeout period.
  May be powered off, disconnected, or experiencing network issues.
  NOT eligible for deployment targeting.
  Queued for catch-up deployment when it comes back online.

MAINTENANCE:
  Device is intentionally taken offline for maintenance.
  Hardware repair, OS upgrade, or physical relocation.
  NOT eligible for deployment targeting.
  Must be manually returned to HEALTHY when maintenance is complete.

DECOMMISSIONED:
  Device is permanently removed from the fleet.
  Terminal state -- cannot be targeted or deployed to.
  Retained in registry for audit trail purposes.
```

---

## Capability Tagging

### Tag Taxonomy

Tags enable flexible device grouping and deployment targeting. Use a consistent taxonomy:

```yaml
tag_categories:
  # Hardware capabilities
  hardware:
    - gpu-capable           # Device has a GPU
    - gpu-jetson-orin       # Specific GPU type
    - gpu-none              # CPU-only device
    - camera-usb            # Has USB camera attached
    - camera-csi            # Has CSI camera attached
    - camera-none           # No camera
    - sensor-imu            # Has IMU sensor
    - sensor-lidar          # Has LiDAR sensor
    - memory-8gb            # RAM tier
    - memory-4gb
    - memory-2gb
    - storage-ssd           # Storage type
    - storage-sdcard
    - storage-emmc

  # Environment
  environment:
    - production            # Production device
    - staging               # Staging / pre-production
    - development           # Development / testing
    - canary                # Designated canary device

  # Location
  location:
    - region-us-east
    - region-us-west
    - region-eu-west
    - site-factory-a
    - site-factory-b
    - site-warehouse-1

  # Role
  role:
    - inference-server      # Runs inference workloads
    - data-collector        # Collects and forwards sensor data
    - gateway               # Edge gateway / aggregator
    - controller            # Controls actuators / robotics
    - monitor               # Monitoring and alerting

  # Fleet management
  fleet:
    - priority-high         # Critical device, deploy carefully
    - priority-normal       # Standard deployment priority
    - priority-low          # Low priority, deploy last
    - canary-eligible       # Can be selected as canary
    - single-point-failure  # Cannot be selected as canary
```

### Tag-Based Deployment Targeting

Use tags to define which devices receive a deployment:

```yaml
# Deploy to all production Jetson devices in factory-a
deployment_target:
  include:
    all_of:
      - production
      - gpu-jetson-orin
      - site-factory-a
  exclude:
    any_of:
      - maintenance
      - single-point-failure

# Deploy to all inference servers except canary-eligible (canary handled separately)
deployment_target:
  include:
    all_of:
      - production
      - inference-server
  exclude:
    any_of:
      - canary-eligible
```

### Tag Query Language

```
Syntax for querying devices by tags:

  Simple match:
    tag:production                     -> all devices tagged "production"

  AND (all tags required):
    tag:production AND tag:gpu-capable -> devices with BOTH tags

  OR (any tag matches):
    tag:site-factory-a OR tag:site-factory-b

  NOT (exclude tag):
    tag:production AND NOT tag:maintenance

  Combined:
    (tag:production AND tag:gpu-jetson-orin AND tag:site-factory-a)
    AND NOT (tag:maintenance OR tag:single-point-failure)
```

---

## Group-Based Deployment Targeting

### Device Groups

Groups are named collections of devices. Unlike tags (which are attributes), groups are explicit memberships.

```yaml
groups:
  production-fleet:
    description: "All production devices"
    membership: dynamic
    query: "tag:production AND NOT tag:decommissioned"

  factory-a-gpu:
    description: "GPU-capable devices at factory A"
    membership: dynamic
    query: "tag:production AND tag:gpu-capable AND tag:site-factory-a"

  canary-pool:
    description: "Devices eligible for canary deployment"
    membership: dynamic
    query: "tag:canary-eligible AND tag:production AND status:healthy"

  critical-devices:
    description: "High-priority devices requiring careful deployment"
    membership: static
    devices:
      - "edge-jetson-prod-001"
      - "edge-jetson-prod-002"
      - "edge-gateway-prod-001"
    deploy_policy: "canary-only-first-wave"

  jetson-orin-fleet:
    description: "All Jetson Orin Nano devices"
    membership: dynamic
    query: "tag:gpu-jetson-orin"
```

### Dynamic vs Static Groups

```
Dynamic Groups:
  - Membership determined by tag query at query time
  - Automatically includes new devices that match criteria
  - Automatically excludes devices that no longer match
  - Best for: environment-based groups, capability-based groups
  - Risk: membership can change between planning and execution

Static Groups:
  - Membership is an explicit list of device IDs
  - Only changes when manually updated
  - Best for: critical devices, compliance-sensitive groups
  - Risk: can become stale if devices are added/removed from fleet

Recommendation:
  - Use dynamic groups for most deployment targeting
  - Use static groups for critical device lists and compliance
  - Always resolve group membership at deployment time (not planning time)
```

### Deployment Targeting with Groups

```yaml
# Deployment manifest targeting
deployment:
  artifact: "inference-app:v2.3.1"

  target:
    groups:
      - "factory-a-gpu"
    exclude_groups:
      - "critical-devices"    # These get deployed in a later, careful wave

  canary:
    source_group: "canary-pool"
    count: 3
    selection: "one-per-device-type"

  waves:
    - name: "critical"
      groups: ["critical-devices"]
      percentage: 100
      soak_minutes: 30
      require_approval: true

    - name: "main-fleet"
      groups: ["factory-a-gpu"]
      exclude_groups: ["critical-devices"]
      percentage: 100
      soak_minutes: 15
```

---

## Heartbeat Monitoring

### Heartbeat Protocol

Each device periodically sends a heartbeat to the fleet management system.

```
Heartbeat payload:

{
  "device_id": "edge-jetson-prod-042",
  "timestamp": "2025-01-16T10:45:00Z",
  "status": "healthy",
  "app_version": "2.3.0",
  "metrics": {
    "cpu_percent": 45.2,
    "memory_used_mb": 4200,
    "memory_total_mb": 8192,
    "disk_free_mb": 32000,
    "gpu_percent": 72.1,
    "temperature_cpu_c": 52.3,
    "temperature_gpu_c": 55.1,
    "uptime_seconds": 72000,
    "error_count_last_hour": 0,
    "inference_latency_p95_ms": 12.4
  }
}
```

### Heartbeat Configuration

```yaml
heartbeat:
  interval_seconds: 60          # Send heartbeat every 60 seconds
  timeout_seconds: 180          # Mark offline after 3 missed heartbeats
  retry_on_failure: true        # Retry if heartbeat send fails
  retry_count: 3
  retry_backoff_seconds: 5

  # Escalation thresholds
  offline_warning_minutes: 5    # Warn after 5 minutes offline
  offline_alert_minutes: 15     # Alert after 15 minutes offline
  offline_critical_minutes: 60  # Critical after 1 hour offline
```

### Heartbeat-Based State Transitions

```
Heartbeat received with status "healthy":
  If device state is OFFLINE -> transition to HEALTHY
  If device state is HEALTHY -> remain HEALTHY, update last_heartbeat
  If device state is DEGRADED -> evaluate: if metrics improved, -> HEALTHY
  If device state is FAILED -> do NOT auto-transition; require manual review

Heartbeat received with status "degraded":
  If device state is HEALTHY -> transition to DEGRADED
  If device state is DEGRADED -> remain DEGRADED, update metrics
  Log degradation reason from heartbeat payload

Heartbeat received with status "failed":
  Any state -> transition to FAILED
  Alert fleet operators
  If deployment in progress: quarantine device, continue fleet deployment

Heartbeat missed (timeout exceeded):
  If device state is HEALTHY or DEGRADED -> transition to OFFLINE
  If deployment in progress: skip device, queue for catch-up
  Log last known state for investigation
```

---

## Offline Device Handling

### Offline During Deployment

When a device is offline during a fleet deployment:

```
Offline device protocol:

1. During deployment planning:
   - Query registry for offline devices in target set
   - If offline count > 20% of target: warn operator
   - Do not delay deployment for offline devices

2. During deployment execution:
   - Skip offline devices in each wave
   - Log: "[device_id] skipped: offline (last heartbeat: [timestamp])"
   - Do not count offline devices in wave success/failure metrics

3. After deployment completes:
   - Add offline devices to catch-up queue
   - Queue entry: {device_id, target_version, deployment_id}

4. When offline device comes back online (heartbeat received):
   - Check catch-up queue for pending deployments
   - If pending:
     a. Verify device health
     b. Deploy queued version (skip canary, device-level only)
     c. Run health checks
     d. Update registry
     e. Remove from catch-up queue
   - If multiple versions queued: deploy only the latest
```

### Catch-Up Queue

```yaml
catch_up_queue:
  - device_id: "edge-jetson-prod-042"
    target_version: "2.3.1"
    deployment_id: "deploy-20250116-001"
    queued_at: "2025-01-16T14:30:00Z"
    reason: "device offline during deployment"
    attempts: 0
    max_attempts: 3
    priority: "normal"

  - device_id: "edge-rpi-prod-017"
    target_version: "2.3.1"
    deployment_id: "deploy-20250116-001"
    queued_at: "2025-01-16T14:30:00Z"
    reason: "device offline during deployment"
    attempts: 1
    max_attempts: 3
    priority: "normal"
    last_attempt: "2025-01-16T15:00:00Z"
    last_failure: "device still offline"
```

### Long-Term Offline Handling

```
If a device remains offline for an extended period:

  1-24 hours:
    - Remain in catch-up queue
    - No action required beyond monitoring

  1-7 days:
    - Escalate to fleet operators
    - Investigate: power issue? network issue? hardware failure?
    - Keep in catch-up queue

  7-30 days:
    - Move from catch-up queue to investigation queue
    - May indicate hardware failure or decommissioning
    - Require manual resolution

  30+ days:
    - Flag for decommissioning review
    - Remove from active fleet counts
    - Retain in registry with "offline-extended" tag
```

---

## Registry Operations

### Adding a New Device

```
New device registration protocol:

1. Generate unique device ID:
   Format: edge-{type}-{environment}-{sequence}
   Example: edge-jetson-prod-043

2. Collect device information:
   - Hardware specs (auto-detected where possible)
   - Network identity (hostname, MAC, IP)
   - Physical location
   - Assigned role and tags

3. Register in registry:
   - Create device record with PROVISIONING state
   - Assign tags based on hardware and role
   - Add to appropriate groups

4. Provision device:
   - Install base OS and container runtime
   - Configure monitoring agent (heartbeat)
   - Deploy current fleet version
   - Verify health checks pass

5. Activate:
   - Transition state: PROVISIONING -> HEALTHY
   - Device is now eligible for fleet deployments
```

### Removing a Device

```
Device decommissioning protocol:

1. Pre-decommission:
   - Verify device is not a single point of failure
   - Verify workload has been migrated (if applicable)
   - Notify fleet operators

2. Transition state: [current] -> MAINTENANCE
   - Device excluded from deployments

3. Clean device:
   - Remove application data
   - Remove credentials and certificates
   - Wipe sensitive configuration

4. Transition state: MAINTENANCE -> DECOMMISSIONED
   - Retain registry record for audit trail
   - Remove from all active groups
   - Add "decommissioned" tag with timestamp

5. Physical:
   - Power off device
   - Remove from rack/mount
   - Update physical location records
```

### Registry Synchronization

```
Periodic registry sync protocol (run daily):

1. Send heartbeat query to all non-decommissioned devices
2. For each response:
   a. Compare reported hardware specs against registry
   b. Compare reported software versions against registry
   c. Update any discrepancies
   d. Log changes for audit trail
3. For each non-response:
   a. If already OFFLINE: no change
   b. If HEALTHY/DEGRADED: transition to OFFLINE
4. Generate sync report:
   - Devices synced: N
   - Discrepancies found: N (list)
   - Newly offline: N (list)
   - Newly online: N (list)
```

---

## Registry Storage Patterns

### File-Based Registry (Small Fleets)

For fleets under 100 devices, a file-based registry is sufficient:

```
fleet-registry/
  devices/
    edge-jetson-prod-001.yaml
    edge-jetson-prod-002.yaml
    edge-rpi-prod-001.yaml
    ...
  groups/
    production-fleet.yaml
    factory-a-devices.yaml
    ...
  deployments/
    deploy-20250116-001.yaml
    deploy-20250115-001.yaml
    ...
  catch-up-queue.yaml
```

Stored in version control (git) for audit trail and change history.

### Database Registry (Medium Fleets)

For fleets of 100-10,000 devices, use a lightweight database:

```
Tables:
  devices:         Device records with all fields
  device_tags:     Tag assignments (device_id, tag)
  device_groups:   Group memberships (device_id, group_id)
  groups:          Group definitions
  heartbeats:      Heartbeat history (time-series)
  deployments:     Deployment records
  deployment_log:  Per-device deployment actions
  catch_up_queue:  Pending catch-up deployments

Recommended: PostgreSQL or SQLite (for single-node management)
```

### Cloud Registry (Large Fleets)

For fleets exceeding 10,000 devices:

```
Options:
  - AWS IoT Device Registry
  - Azure IoT Hub Device Twin
  - Google Cloud IoT Core Device Registry
  - Custom service with time-series database

Requirements:
  - Sub-second query for device lookup
  - Efficient tag-based filtering
  - Time-series storage for heartbeat history
  - Event-driven state transitions
  - API access for deployment automation
```

---

## Best Practices Summary

```
DEVICE REGISTRY BEST PRACTICES
+------------------------------------------------------------------+
| [ ] Every device has a unique, immutable ID                       |
| [ ] Device records include hardware, software, and status fields  |
| [ ] Tags follow a consistent taxonomy                             |
| [ ] Groups are defined for common deployment targets              |
| [ ] Heartbeat monitoring detects offline devices within 3 minutes |
| [ ] Device state machine transitions are logged                   |
| [ ] Offline devices are queued for catch-up, not marked as failed |
| [ ] Registry is synced with actual device state daily             |
| [ ] Decommissioned devices are retained for audit trail           |
| [ ] Registry is the input for all deployment targeting decisions  |
| [ ] Tag queries resolve at deployment time, not planning time     |
| [ ] Physical location is recorded for every device                |
| [ ] Registry changes are version-controlled or audited            |
| [ ] Capability tags are auto-detected where possible              |
+------------------------------------------------------------------+
```
