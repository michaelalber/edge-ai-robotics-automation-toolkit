# Rolling Deployment Strategies for Edge Fleets

## Overview

Rolling deployment strategies control how software updates propagate across a fleet of edge devices. Unlike cloud deployments where servers are fungible and replaceable, edge devices are physically distributed, resource-constrained, and often difficult to access. A bad deployment to a cloud server means spinning up a replacement. A bad deployment to a field-deployed edge device might mean sending a technician to a remote site.

This reference covers canary deployments, blue-green patterns, rolling updates, percentage-based rollouts, health gate criteria, and automatic rollback triggers -- all adapted for edge fleet constraints.

---

## Canary Deployment Pattern

### Concept

Deploy the new version to a small representative subset of the fleet (the "canary") before deploying to anyone else. The canary devices absorb the risk. If they fail, only a tiny fraction of the fleet is affected.

### Canary Sizing

```
Fleet Size    Recommended Canary Size    Rationale
----------    -----------------------    ---------
< 10          1 device                   Minimum viable canary
10-50         2-3 devices                One per device type
50-200        3-5 devices                Coverage across types and regions
200-1000      5-10 devices (2-5%)        Statistical significance
1000+         10-50 devices (1-2%)       Diminishing returns above 2%
```

### Canary Selection Algorithm

```
Given:
  fleet: list of all target devices
  device_types: set of unique hardware types in fleet
  regions: set of unique deployment regions in fleet

Select canary set:
  1. For each device_type in device_types:
     - Select 1 device of that type with best monitoring coverage
  2. For each region in regions:
     - If not already represented in canary, select 1 device from region
  3. Exclude from canary selection:
     - Devices marked as single point of failure
     - Devices currently in maintenance or quarantine
     - Devices with known hardware issues
     - Devices with connectivity problems in the last 24 hours
  4. If canary size < minimum (1), select the most representative device
  5. If canary size > maximum (5% of fleet), reduce to most representative subset
```

### Canary Health Evaluation

The canary evaluation period has three phases:

**Immediate (0-5 minutes):**
- Application starts without crash
- Health endpoint responds with 200
- Version reported matches deployed version
- No error logs in first 5 minutes

**Short-term (5-30 minutes):**
- Error rate does not exceed baseline + 2%
- P95 latency does not exceed baseline + 20%
- Memory usage is stable (not trending upward)
- CPU utilization is within expected bounds
- No restarts detected

**Soak (30-60 minutes):**
- All short-term metrics remain stable
- No memory leak detected (memory usage growth < 1% per 10 minutes)
- No thermal throttling events (for GPU-equipped devices)
- Output quality metrics (accuracy, confidence scores) match baseline
- No disk space consumption anomalies

```
Canary Verdict Decision:

  ALL immediate checks pass AND
  ALL short-term checks pass AND
  ALL soak checks pass
  -> CANARY PASS: proceed to fleet rollout

  ANY immediate check fails
  -> CANARY FAIL: rollback immediately, investigate

  ANY short-term check fails
  -> CANARY FAIL: rollback, extend monitoring period on investigation

  ANY soak check shows degradation trend
  -> CANARY CAUTION: extend soak period, do not proceed yet
```

---

## Percentage-Based Rollout

### Wave Configuration

Define rollout waves as percentages of the fleet rather than absolute device counts. This scales automatically as the fleet grows.

```yaml
# Example rollout configuration
rollout:
  canary:
    percentage: 3
    min_devices: 1
    max_devices: 10
    soak_minutes: 30
    require_human_approval_after: true

  waves:
    - name: wave-1
      percentage: 15
      soak_minutes: 15
      failure_threshold_percent: 5
      auto_rollback: true

    - name: wave-2
      percentage: 35
      soak_minutes: 10
      failure_threshold_percent: 5
      auto_rollback: true

    - name: wave-3
      percentage: 100    # remaining devices
      soak_minutes: 10
      failure_threshold_percent: 3
      auto_rollback: true

  global:
    max_parallel_deploys: 50
    deploy_timeout_minutes: 10
    health_check_interval_seconds: 30
    health_check_retries: 3
    offline_device_policy: skip_and_queue
```

### Wave Device Assignment

```
Algorithm: Assign devices to waves

Input:
  devices: sorted list of target devices (canary already deployed)
  waves: list of wave configurations with percentages

Process:
  1. Remove canary devices from the pool
  2. Shuffle remaining devices (randomize wave assignment)
  3. For each wave:
     a. Calculate wave size: ceil(remaining_count * wave.percentage / 100)
     b. Assign next N devices from shuffled pool
     c. Ensure each wave has at least 1 device per device type (if possible)
  4. Last wave gets all remaining devices regardless of percentage

Output:
  wave_assignments: map of wave_name -> list of device IDs
```

### Inter-Wave Health Verification

Between each wave, the system must verify the health of ALL deployed devices, not just the current wave.

```
Inter-wave verification protocol:

1. Wait for soak period to elapse
2. Query health endpoint on ALL previously deployed devices
   (canary + all completed waves)
3. Calculate aggregate metrics:
   - Overall error rate across all deployed devices
   - P50, P95, P99 latency across all deployed devices
   - Average resource utilization
   - Count of healthy / degraded / failed devices
4. Compare against baseline:
   - Error rate delta < threshold
   - Latency delta < threshold
   - No new failed devices since last check
5. Decision:
   - ALL metrics within bounds -> proceed to next wave
   - ANY metric degrading -> extend soak, recheck
   - ANY metric exceeding threshold -> HALT, assess rollback
```

---

## Blue-Green Deployment for Edge

### Architecture

Each edge device maintains two deployment slots. Only one is active at a time.

```
Device Storage Layout:

  /opt/deployments/
    blue/                    # Slot A
      app/                   # Application code
      models/                # ML models
      config/                # Configuration
      .version               # Version metadata
    green/                   # Slot B
      app/
      models/
      config/
      .version
    active -> blue/          # Symlink to active slot
    router.conf              # Traffic routing config
```

### Deployment Flow

```
Current state: BLUE is active, GREEN is standby

Step 1: Deploy to GREEN slot
  - Transfer new artifact to GREEN directory
  - Verify artifact integrity on device
  - Start new version in GREEN (not yet receiving traffic)
  - Run smoke test against GREEN's internal port

Step 2: Switch traffic
  - Update symlink: active -> green
  - Reload reverse proxy / service router
  - GREEN now receives all traffic

Step 3: Verify
  - Monitor GREEN under live traffic
  - If healthy: deployment complete
  - If unhealthy: switch back to BLUE (instant rollback)

Step 4: Cleanup
  - BLUE remains untouched as rollback target
  - BLUE is only overwritten in the NEXT deployment cycle
```

### Blue-Green Resource Requirements

```
Resource overhead per device:

  Disk:
    Active slot: [application size]
    Standby slot: [application size]
    Total: 2x application size
    Typical: 500MB - 5GB additional per device

  Memory (during transition):
    Brief period where both versions are running
    Requires: current app memory + new app memory + OS overhead
    Mitigation: stop old version before starting new (brief downtime)

  Network:
    Full artifact transfer for each deployment
    Mitigation: delta transfers (rsync, container layer caching)
```

### When Blue-Green is Not Feasible

- Devices with less than 2x application size in free disk
- Devices where brief downtime is acceptable (rolling update is simpler)
- Fleets larger than 500 devices (coordination overhead)
- When models are very large (> 2GB) and disk is constrained

---

## Rolling Update Pattern

### Configuration Parameters

```yaml
rolling_update:
  max_unavailable: 10%      # Max devices being updated at once
  min_available: 90%         # Minimum healthy devices at all times
  health_check:
    path: /health
    port: 8080
    interval_seconds: 30
    timeout_seconds: 10
    success_threshold: 3     # Consecutive successes to mark healthy
    failure_threshold: 3     # Consecutive failures to mark unhealthy
  min_ready_seconds: 60      # Must be healthy for 60s before proceeding
  progress_deadline: 300     # Seconds before declaring wave stuck
  rollback_on_failure: true
```

### Execution Flow

```
For each batch of devices (up to max_unavailable):

  1. DRAIN
     - Mark devices as "updating" in registry
     - If applicable, stop accepting new work / connections
     - Wait for in-flight work to complete (grace period)

  2. STOP
     - Stop current application version
     - Verify process is fully stopped

  3. DEPLOY
     - Transfer new artifact to device
     - Verify artifact integrity (checksum)
     - Install / extract artifact

  4. START
     - Start new application version
     - Begin health check monitoring

  5. VERIFY
     - Wait for success_threshold consecutive healthy checks
     - Verify minimum min_ready_seconds of continuous health
     - Mark device as "deployed" in registry

  6. PROCEED or ROLLBACK
     - If healthy: move to next batch
     - If unhealthy after progress_deadline: rollback batch
```

---

## Health Gate Criteria

### Defining Health Gates

Health gates are checkpoints between deployment stages. A gate must be explicitly passed before the next stage can begin.

```yaml
health_gates:
  canary_gate:
    description: "Canary devices healthy after soak period"
    checks:
      - type: error_rate
        threshold: baseline + 2%
        window: 15m
      - type: latency_p95
        threshold: baseline + 20%
        window: 15m
      - type: memory_trend
        threshold: growth < 1% per 10m
        window: 30m
      - type: application_health
        threshold: all_healthy
      - type: crash_count
        threshold: 0
        window: 30m
    verdict: all_checks_pass

  wave_gate:
    description: "All deployed devices healthy"
    checks:
      - type: error_rate
        threshold: baseline + 5%
        window: 10m
      - type: latency_p95
        threshold: baseline + 30%
        window: 10m
      - type: device_health
        threshold: healthy_percentage >= 95%
      - type: crash_count
        threshold: 0
        window: 10m
    verdict: all_checks_pass

  completion_gate:
    description: "Full fleet healthy post-deployment"
    checks:
      - type: error_rate
        threshold: baseline + 2%
        window: 30m
      - type: fleet_coverage
        threshold: deployed_percentage >= 95%
      - type: device_health
        threshold: healthy_percentage >= 98%
    verdict: all_checks_pass
```

### Baseline Metrics Collection

Before any deployment, capture baseline metrics:

```
Baseline collection protocol:

1. Select time window: last 24 hours of normal operation
2. Exclude anomalous periods (known incidents, maintenance)
3. Calculate for each metric:
   - Mean value
   - P50, P95, P99 values
   - Standard deviation
   - Trend (stable / increasing / decreasing)
4. Store baseline per device group (not fleet-wide average)
5. Use group-specific baselines for health comparison
```

---

## Automatic Rollback Triggers

### Trigger Definitions

```yaml
rollback_triggers:
  # Immediate rollback -- no waiting
  immediate:
    - name: crash_loop
      condition: device restarts > 3 in 5 minutes
      scope: single_device
      action: rollback_device

    - name: health_endpoint_down
      condition: health endpoint unreachable for > 2 minutes
      scope: single_device
      action: rollback_device

    - name: wave_failure_rate
      condition: failed devices > 20% of wave
      scope: current_wave
      action: rollback_wave

  # Threshold rollback -- based on metric comparison
  threshold:
    - name: error_rate_spike
      condition: error_rate > baseline + 10%
      window: 5m
      scope: all_deployed
      action: rollback_all

    - name: latency_spike
      condition: p95_latency > baseline * 2.0
      window: 5m
      scope: current_wave
      action: halt_and_assess

    - name: memory_leak
      condition: memory_growth > 5% per 10 minutes
      window: 30m
      scope: affected_devices
      action: rollback_affected

  # Trend rollback -- based on degradation patterns
  trend:
    - name: gradual_degradation
      condition: error_rate increasing for 3 consecutive checks
      scope: all_deployed
      action: halt_and_assess

    - name: thermal_escalation
      condition: temperature trending toward thermal limit
      scope: affected_devices
      action: halt_and_assess
```

### Rollback Execution Order

```
Single Device Rollback:
  1. Stop current application on the device
  2. Restore previous version from local snapshot
  3. Start restored application
  4. Verify health
  5. Update registry: mark device as rolled back
  6. Continue fleet deployment (device is quarantined)

Wave Rollback:
  1. HALT all deployments in the current wave
  2. For each device in the wave (in parallel):
     a. Stop current application
     b. Restore previous version
     c. Start restored application
     d. Verify health
  3. Verify all rolled-back devices are healthy
  4. Update registry: mark wave as rolled back
  5. HALT fleet deployment; require human decision to continue

Full Fleet Rollback:
  1. HALT all deployment activity
  2. Identify all devices running the new version
  3. For each deployed device (in parallel batches of max_parallel):
     a. Stop current application
     b. Restore previous version
     c. Start restored application
     d. Verify health
  4. Verify fleet health returns to pre-deployment baseline
  5. Update registry: mark deployment as rolled back
  6. Generate incident report
```

---

## Deployment Artifact Management

### Artifact Distribution

```
Distribution strategies for edge fleets:

1. Central Registry Pull (recommended for < 500 devices)
   - Devices pull artifact from central registry (Docker registry, S3, etc.)
   - Simple to manage; each device pulls independently
   - Network bandwidth is bottleneck for large fleets
   - Requires reliable network to registry

2. Peer-to-Peer Distribution (recommended for > 500 devices)
   - First wave devices pull from central registry
   - Subsequent devices can pull from already-deployed peers
   - Reduces central bandwidth requirements
   - More complex to implement and debug

3. Local Cache / Satellite (recommended for multi-site fleets)
   - Pre-stage artifacts at local cache per site/region
   - Devices pull from local cache (fast, reliable)
   - Requires infrastructure for local caches
   - Best for fleets with WAN connectivity constraints

4. Physical Media (last resort)
   - USB drives or SD cards for completely disconnected sites
   - Only for air-gapped environments
   - Manual process; does not scale
```

### Artifact Integrity Verification

```
Before deploying any artifact to any device:

1. Verify checksum:
   computed_hash = sha256(artifact_file)
   expected_hash = manifest.artifact.checksum
   assert computed_hash == expected_hash

2. Verify signature (if available):
   gpg --verify artifact.sig artifact_file

3. Verify version metadata:
   assert artifact.version == manifest.target_version
   assert artifact.architecture == device.architecture

4. Verify size:
   assert artifact.size == manifest.artifact.size_bytes
   assert device.free_disk > artifact.size * 2  # Room for rollback copy
```

---

## Best Practices Summary

```
ROLLING DEPLOYMENT BEST PRACTICES
+------------------------------------------------------------------+
| [ ] Always deploy canary first, regardless of change size         |
| [ ] Size canary to cover all device types and regions             |
| [ ] Define health gates with measurable, automated criteria       |
| [ ] Enforce soak periods between every deployment stage           |
| [ ] Define automatic rollback triggers before starting deployment |
| [ ] Keep rollback mechanism independent of application health     |
| [ ] Use percentage-based waves that scale with fleet size         |
| [ ] Health-check ALL deployed devices between waves, not just     |
|     the current wave                                              |
| [ ] Capture baseline metrics before deployment begins             |
| [ ] Verify artifact integrity on every device before deploying    |
| [ ] Log every action with timestamp, device ID, and outcome      |
| [ ] Handle offline devices gracefully -- queue for later          |
| [ ] Generate deployment report with full audit trail              |
| [ ] Never combine waves or skip stages to save time               |
+------------------------------------------------------------------+
```
