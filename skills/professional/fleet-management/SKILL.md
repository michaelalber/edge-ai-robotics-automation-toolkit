---
name: fleet-management
audience: professional
description: Rolling deployment strategies, multi-device coordination, and rollback triggers for edge device fleets. Use when managing fleet-wide deployments, configuring rollout strategies, building device registries, or implementing rollback automation.
---

# Fleet Management for Edge Device Deployments

> "In a fleet of a thousand devices, you do not fear the one that fails -- you fear the nine hundred and ninety-nine that fail silently."
> -- Kelsey Hightower, Principal Engineer, Google

## Core Philosophy

This skill provides the operational knowledge for managing deployments across fleets of heterogeneous edge devices. It covers rolling deployment strategies, device registry management, health-gated rollouts, and automatic rollback triggers. Every pattern assumes edge devices are remote, resource-constrained, and potentially unreliable.

**Non-Negotiable Constraints:**
1. **Never deploy to the entire fleet at once** -- Staged rollouts are mandatory. A bad deployment to an entire distributed fleet can take weeks to recover from.
2. **Rollback must be independent of the new version** -- If the new version crashes on startup, the rollback mechanism must still function.
3. **Device state is the source of truth** -- The registry says what you expect; the device says what is real. When they disagree, trust the device.
4. **Offline devices are not failed devices** -- Edge devices go offline for legitimate reasons. Handle them gracefully and catch them up later.
5. **Health checks must be application-aware** -- A device that responds to ping but serves garbage results is not healthy.

## Domain Principles Table

| Principle | Description | Priority |
|-----------|-------------|----------|
| **Canary First** | Every deployment begins with a canary subset; never skip canary even for hotfixes | Critical |
| **Health-Gated Waves** | Each rollout wave must pass health checks before the next wave begins | Critical |
| **Rollback Independence** | Rollback mechanism must work even if the new version is completely non-functional | Critical |
| **Device Registry Accuracy** | Maintain up-to-date inventory of device capabilities, versions, and health status | High |
| **Offline Tolerance** | Gracefully handle devices offline during deployment; catch them up later | High |
| **Percentage-Based Rollout** | Define rollout stages as fleet percentages, not absolute device counts | High |
| **Automatic Rollback Triggers** | Define measurable failure thresholds that trigger rollback without human intervention | High |
| **Deployment Atomicity** | A deployment to a single device either fully succeeds or fully rolls back; no partial states | Medium |
| **Heterogeneous Fleet Support** | Support mixed device types (Jetson, RPi, gateways) in a single coordinated deployment | Medium |
| **Audit Trail** | Every deployment action must be logged with timestamp, device ID, actor, and outcome | Medium |

## Knowledge Base Lookups

| Query | When to Call |
|-------|--------------|
| `search_knowledge("rolling deployment canary staged rollout")` | During PREPARE/CANARY — selecting and sizing deployment waves |
| `search_knowledge("health check liveness readiness probe")` | During VALIDATE — designing application-aware health checks |
| `search_knowledge("blue-green deployment rollback strategy")` | During CANARY/ROLLOUT — choosing and configuring rollback mechanisms |
| `search_knowledge("edge device fleet OTA update")` | During PREPARE — understanding OTA update constraints for embedded devices |
| `search_knowledge("device registry inventory management")` | During PREPARE — structuring the device registry schema |
| `search_code_examples("Docker container rollback Python")` | Before writing rollback automation |
| `search_code_examples("health endpoint Flask FastAPI")` | Before implementing health endpoints |

Search `automation` and `architecture` collections for fleet coordination patterns; `edge_ai` for Jetson-specific deployment notes.

## Workflow

The deployment lifecycle flows: **PREPARE → VALIDATE → CANARY → (human approval) → WAVE 1 → WAVE 2 → WAVE 3 → CONFIRM**. Health gates between every wave. Rollback at any phase returns to PREPARE.

### Deployment Strategy Selection

| Strategy | Best For | Tradeoff | Risk Level |
|----------|----------|----------|------------|
| **Canary + Rolling** | Most edge fleets | Balanced speed and safety | Low |
| **Blue-Green** | Fleets with hot-standby capacity | Fast rollback, double resources | Low |
| **Rolling Update** | Homogeneous fleets with stateless apps | Simple, no extra resources | Medium |
| **A/B Deploy** | Feature testing across device subsets | Complex routing, useful metrics | Medium |
| **Big Bang** | Never for edge fleets | — | Unacceptable |

### Pre-Deployment Checklist

- [ ] Artifact built, tested, and checksummed
- [ ] Deployment manifest validated against device registry
- [ ] Architecture compatibility confirmed for all device groups
- [ ] Resource requirements fit within device constraints
- [ ] Rollback artifact available and tested
- [ ] Canary devices selected with coverage across device types
- [ ] Health check endpoints defined and baseline metrics captured
- [ ] Soak periods defined for canary and each wave
- [ ] Failure thresholds defined for automatic rollback
- [ ] Network connectivity verified to fleet (heartbeat check)
- [ ] Disk space verified on target devices

If ANY item is unchecked — STOP. Resolve before deploying.

### Canary + Staged Rolling Deployment

**Canary (1–5% of fleet):**
- Select at least one device per hardware type and geographic region
- Prefer devices with highest monitoring fidelity
- Never select single points of failure or devices with known issues
- Deploy, run smoke tests immediately, enter soak period (15–60 min)
- Compare metrics against pre-deployment baseline; declare PASS or FAIL

**Staged Waves:**
- Wave 1: 10–25% of remaining fleet (catch issues missed by canary)
- Wave 2: 25–50% (build confidence at scale)
- Wave 3: remaining (complete the rollout)
- Between waves: health check ALL deployed devices, compare fleet-wide error rate, verify resource trends, wait for inter-wave soak period (5–15 min)

**Automatic Rollback Triggers:**
- Error rate increases >5% above baseline → rollback current wave
- P95 latency increases >50% above baseline → rollback current wave
- Any device enters crash loop (3+ restarts in 5 min) → rollback current wave
- Memory usage exceeds 90% on any deployed device → rollback current wave
- Health endpoint unreachable on >10% of wave devices → rollback current wave
- Error rate >10% above baseline across all deployed devices → full fleet rollback

### Blue-Green Deployment

Requires two deployment slots per device (BLUE = active, GREEN = standby). Deploy new artifact to GREEN on canary devices → verify → switch canary traffic BLUE→GREEN → deploy GREEN to remaining fleet in waves → switch traffic after each wave verification. **Rollback:** switch traffic back from GREEN to BLUE — seconds, no file transfer needed. Use when: devices have sufficient resources for two slots, zero-downtime deployment is required, instant rollback is a hard requirement.

### Health Check Layers

```
Layer 1 Connectivity  — ICMP ping, SSH port open, deployment agent heartbeat
Layer 2 System Health — CPU/memory/disk below thresholds, temperature below thermal limit
Layer 3 Application   — Health endpoint 200, version matches expected, no crash loops
Layer 4 Functional    — Correct inference output on test input, E2E latency within bounds
```

Health endpoint response: `{"status": "healthy|degraded|unhealthy", "version": "...", "checks": {...}}`

### Rollback Patterns

**Snapshot-based:** Snapshot filesystem/image before deploy → store locally with checksum → on failure: stop new app, restore snapshot, verify health.

**Dual-slot:** `/opt/app/active` symlink → `slot-a` (previous known-good) or `slot-b` (new version). Rollback = update symlink to `slot-a`, restart. Seconds to complete, no transfer needed.

**Container-based:** `docker tag app-current app-rollback` before deploy. Rollback: `docker stop && docker rm app-current && docker run app-rollback`.

## State Block

```
<fleet-deploy-state>
phase: [PREPARE | CANARY | VERIFY | ROLLOUT | CONFIRM]
strategy: [canary-rolling | blue-green | rolling-update]
artifact: [name and version]
fleet_total: N
deployed_count: N
healthy_count: N
quarantined_count: N
skipped_count: N
rollback_available: [true | false]
current_wave: [N/M]
last_action: [description]
next_action: [description]
blockers: [any issues]
</fleet-deploy-state>
```

## Output Templates

```markdown
## Fleet Deployment Report: [Artifact] v[version]
**Strategy**: [strategy] | **Duration**: [start] to [end]

| Status | Count | % |
|--------|-------|---|
| Deployed (healthy) | N | % |
| Skipped (unreachable) | N | % |
| Quarantined (failed) | N | % |

| Wave | Devices | Failed | Soak | Verdict |
|------|---------|--------|------|---------|
| Canary | N | N | [duration] | PASS/FAIL |
| Wave 1/2/3 | N | N | [duration] | PASS/FAIL |

**Health Delta**: Error rate [+/-], P95 latency [+/-], CPU [+/-], Memory [+/-]
```

## Anti-Patterns Table

| Anti-Pattern | Why It's Wrong | Correct Approach |
|--------------|----------------|------------------|
| Deploying to all devices at once | A single bug bricks the entire fleet; recovery takes weeks | Use canary + staged waves with health gates |
| Skipping canary for "small" changes | Small changes cause production incidents too; one-line bugs exist | Always canary, regardless of change size |
| Health checks that only ping | A device can respond to ping while serving garbage results | Implement application-aware health checks |
| No soak period between waves | Issues that take minutes to manifest (memory leaks, thermal) are missed | Enforce minimum soak periods |
| Rollback that depends on the new version | If the new version crashes on startup, rollback fails too | Rollback must be independent of application health |
| Treating offline devices as failed | Edge devices go offline legitimately | Track offline devices separately; catch them up later |
| Manual rollback procedures | Under pressure, humans skip steps | Define automatic rollback triggers with measurable thresholds |
| Deploying without a device registry | Cannot track what is deployed where, making rollback and auditing impossible | Maintain an accurate, up-to-date device registry |

## Error Recovery

**Wave exceeds failure threshold**: HALT current wave immediately. Rollback ALL devices in the failed wave. Verify rollback restores healthy state. Analyze failure pattern: same failure on all devices (artifact issue), specific device type (compatibility issue), random failures (infrastructure issue). Do NOT proceed until root cause is identified.

**Canary shows gradual degradation**: Extend soak period to confirm the trend. Capture detailed metrics (1-second intervals). If degradation continues: rollback canary, verify metrics return to baseline, report the pattern. Common causes: memory leak, resource contention, thermal throttling. Do NOT proceed to fleet rollout with gradual degradation.

**Device registry out of sync**: Run fleet-wide heartbeat scan. Compare against registry. Device in registry but not responding → mark OFFLINE. Device responding but not in registry → add to registry. Capability mismatch → update registry from device report. Do NOT deploy to devices with unresolved discrepancies.

## Integration with Other Skills

- **`jetson-deploy`** -- Use for Jetson-specific device-level configuration (TensorRT engine building, power mode, JetPack verification). Fleet management handles coordination; `jetson-deploy` handles device-level execution.
- **`sensor-integration`** -- When the fleet includes sensor payloads, coordinate sensor configuration alongside application deployment and re-validate calibration after software updates.
- **`edge-cv-pipeline`** -- Health checks for CV pipeline deployments should include inference accuracy validation, not just application liveness. Use `edge-cv-pipeline` patterns for functional health check definition.
