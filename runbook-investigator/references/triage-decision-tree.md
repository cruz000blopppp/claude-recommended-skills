# Triage Decision Tree

A structured decision tree for classifying incident severity and determining the appropriate response. Work through each level sequentially.

---

## Level 1: Impact Assessment

### Is production affected?

```bash
# Check application error rates
# (substitute your monitoring tool's CLI or dashboard)
curl -s https://status.yourapp.com/api/status | jq '.status'

# Check recent error rate in logs
grep -c "ERROR\|FATAL\|CRITICAL" /var/log/app/app.log | tail -1

# Check HTTP error rates (if accessible)
# 5xx rate in last 5 minutes from access logs
awk '$9 >= 500 {count++} END {print count}' /var/log/nginx/access.log
```

If production is affected, proceed to data integrity check.
If production is not affected, skip to "Is it blocking development?"

### Is data being lost or corrupted?

```bash
# Check database replication lag
# PostgreSQL
SELECT now() - pg_last_xact_replay_timestamp() AS replication_lag;

# Check for failed writes in application logs
grep -c "write failed\|insert failed\|update failed\|constraint violation" /var/log/app/app.log

# Check transaction log for rollbacks
grep -c "ROLLBACK\|transaction aborted" /var/log/postgresql/postgresql.log
```

- Data loss confirmed → **CRITICAL**
- No data loss → **HIGH**

### How many users are affected?

```bash
# Check unique affected users in error logs (last 30 minutes)
grep "ERROR" /var/log/app/app.log | grep -oP 'user_id=\K\w+' | sort -u | wc -l

# Check error rate as percentage of total requests
# Compare error count vs total request count in your metrics system
```

- All users (complete outage) → **CRITICAL**
- Significant subset (>10%) → **HIGH**
- Small subset (<10%) → **MEDIUM** (unless data loss, then **HIGH**)
- Single user with specific edge case → **LOW**

### Is it blocking development?

- CI/CD pipeline broken, entire team blocked → **MEDIUM**
- Single developer blocked, workaround exists → **LOW**
- Cosmetic issue, no functional impact → **LOW**

---

## Level 2: Urgency Classification

### CRITICAL

- Complete production outage
- Active data loss or corruption
- Security breach (unauthorized access, data exfiltration)
- Payment processing failure
- Compliance violation in progress

**Response time: Immediate (within 5 minutes)**

### HIGH

- Degraded production service (slow but functional)
- Partial outage (some features down, core path working)
- Error rate elevated but not total
- Key integration broken (affecting downstream consumers)

**Response time: Within 15 minutes**

### MEDIUM

- Non-critical feature broken in production
- CI/CD pipeline broken, blocking deploys
- Staging/preview environment down
- Performance regression caught in monitoring but not yet user-visible

**Response time: Within 1 hour**

### LOW

- Cosmetic issues
- Development environment issues with known workaround
- Flaky test (not blocking CI)
- Non-urgent technical debt discovered during investigation

**Response time: Next business day**

---

## Level 3: Initial Response Actions

### CRITICAL Response

**First 5 Minutes:**

1. **Acknowledge.** Confirm you are responding. Post in the incident channel.
   ```
   @here Investigating [brief description]. I am the Incident Commander.
   ```

2. **Assess blast radius.** Who and what is affected right now?
   ```bash
   # Check which services are reporting errors
   # Check status of dependent services
   # Check geographic scope of impact
   ```

3. **Mitigate immediately.** Stop the bleeding before diagnosing.
   - Can you rollback the last deploy?
     ```bash
     # Check last deploy time vs incident start time
     # If they correlate, rollback
     git log --oneline -5
     # Use your deployment tool's rollback mechanism
     ```
   - Can you toggle a feature flag?
   - Can you scale up to absorb load?
   - Can you failover to a secondary?

4. **Preserve evidence.** Before any further changes:
   ```bash
   # Capture current logs
   cp /var/log/app/app.log /tmp/incident-$(date +%Y%m%d-%H%M%S).log

   # Capture current process state
   ps aux > /tmp/incident-ps-$(date +%Y%m%d-%H%M%S).txt

   # Capture current connections
   ss -tlnp > /tmp/incident-connections-$(date +%Y%m%d-%H%M%S).txt
   ```

5. **Start the investigation log.** Record everything from this point forward.

### HIGH Response

**First 5 Minutes:**

1. **Acknowledge.** Notify the team you are investigating.

2. **Quantify impact.** What percentage of requests/users are affected?
   ```bash
   # Error rate trend over last 30 minutes
   # Latency percentiles (p50, p95, p99)
   # Affected endpoints or features
   ```

3. **Check recent changes.**
   ```bash
   git log --oneline --since="4 hours ago"
   # Check deployment history in CI/CD
   # Check recent config changes, feature flag toggles
   ```

4. **Start investigation log.** Begin recording observations and hypotheses.

5. **Set a timebox.** If no progress in 30 minutes, consider rollback or escalation.

### MEDIUM Response

**First 5 Minutes:**

1. **Create a ticket.** Document the issue with reproduction steps.

2. **Assess workarounds.** Can work continue while this is investigated?
   ```bash
   # For CI failures: can you skip the failing step temporarily?
   # For feature bugs: is there a manual workaround?
   ```

3. **Check if it is a known issue.**
   ```bash
   # Search issue tracker
   # Check recent Slack/Teams messages
   # Check monitoring for similar past incidents
   ```

4. **Assign and schedule.** Pick up now if available, or assign for prompt investigation.

5. **Begin investigation.** Work through the appropriate template from `investigation-templates.md`.

### LOW Response

**First 5 Minutes:**

1. **Document.** Record the issue with clear reproduction steps.

2. **Check if it is already tracked.** Search the issue tracker for duplicates.

3. **Triage.** Add to the backlog with appropriate labels and priority.

4. **Note workaround.** If there is one, document it in the ticket.

5. **Move on.** Return to higher-priority work.

---

## Level 4: Investigation Strategy Selection

After initial response, choose an investigation strategy based on the pattern of the failure.

### Known error signature?

```bash
# Search for the error message in your runbooks/wiki
# Search past incidents for the same error
grep -r "ExactErrorMessage" /path/to/runbooks/
```

If found → follow the existing runbook.
If not found → continue below.

### Recent deploy?

```bash
# Compare last deploy time with incident start time
git log --oneline --format="%h %ai %s" -10

# Diff the deploy
git diff <previous-release-tag>...<current-release-tag> --stat
git diff <previous-release-tag>...<current-release-tag>
```

If deploy correlates with incident onset → investigate the deploy diff.
If no recent deploy → continue below.

### Gradual degradation?

Check if the issue worsened over time rather than starting suddenly.

```bash
# Check resource trends
# Memory usage over time
# CPU usage over time
# Disk usage trend
df -h
# Connection count trend
ss -s
```

If gradual → check for resource leaks, traffic growth, data growth.
If sudden → continue below.

### Sudden onset?

Check for external triggers.

```bash
# Check external dependency status pages
# Check DNS resolution
dig <dependency-hostname> +short

# Check network connectivity
curl -w "%{time_total}\n" -o /dev/null -s https://dependency.example.com/health

# Check for infrastructure events (cloud provider status)
```

If external dependency is down → monitor their status, implement fallback.
If external dependencies are healthy → continue below.

### Random occurrence?

No obvious pattern, no clear trigger.

- Review the intermittent failure checklist in `investigation-templates.md`
- Increase logging and monitoring around the failure path
- Set up alerts to capture the next occurrence with better instrumentation
- Consider: race conditions, resource exhaustion under specific load patterns, edge cases in input data

---

## Quick Reference Summary

| Severity | Data Loss | Production | Response | First Action |
|----------|-----------|------------|----------|--------------|
| CRITICAL | Yes/Security | Down | Immediate | Mitigate, then investigate |
| HIGH | No | Degraded | 15 min | Investigate with urgency |
| MEDIUM | No | No | 1 hour | Investigate promptly |
| LOW | No | No | Next day | Document and backlog |
