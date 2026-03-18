# Capacity Planning

Methods for projecting resource needs before they become emergencies. The goal: never be surprised by resource exhaustion. If you can project it 30 days out, you can plan instead of panic.

---

## 1. Disk Capacity

### Measurement

Collect weekly snapshots over at least 4 weeks to establish a growth rate:

```bash
# Record current usage (run weekly, store in a log)
date_tag=$(date +%Y-%m-%d)
df -h --output=source,size,used,avail,pcent | tee -a /var/log/disk_capacity.log

# Calculate daily growth rate from snapshots
# Example: If usage grew from 120 GB to 140 GB over 28 days:
# daily_growth = (140 - 120) / 28 = 0.71 GB/day
```

### Projection Formula

```
days_until_full = free_space_gb / daily_growth_gb

# Example:
# Total: 500 GB, Used: 350 GB, Free: 150 GB
# Daily growth: 0.71 GB/day
# days_until_full = 150 / 0.71 = 211 days
```

### Seasonal Adjustment

Growth is rarely linear. Factor in:

- **Traffic seasonality**: E-commerce spikes during holidays, SaaS spikes at month-end
- **Feature launches**: New features generating more data (uploads, logs, analytics)
- **Data retention changes**: New compliance requirements retaining more data
- **Log volume**: Deploy activity and debugging sessions generate more logs

Apply a safety factor of 1.5x to the projected growth rate to account for variability.

```
conservative_days = free_space_gb / (daily_growth_gb * 1.5)
```

### Action Thresholds

| Usage | Action | Timeline |
|-------|--------|----------|
| < 70% | Monitor | Continue weekly tracking |
| 70-80% | Plan | Evaluate expansion options, estimate cost, get approval |
| 80-90% | Warn | Create ticket, schedule expansion, increase monitoring to daily |
| > 90% | Act | Expand immediately, clean up temp/old data, consider emergency measures |

### Quick Wins for Disk Pressure

Before expanding storage, check for easy savings:

```bash
# Large files
find / -type f -size +100M -exec ls -lh {} \; 2>/dev/null | sort -k5 -rh | head -20

# Old log files
find /var/log -name "*.log.*" -mtime +30 -exec du -sh {} \; | sort -rh

# Docker overhead
docker system df

# Package manager caches
du -sh ~/.npm/ ~/.cache/pip/ /var/cache/apt/ 2>/dev/null

# Core dumps
find / -name "core.*" -o -name "*.core" 2>/dev/null | head -10
```

---

## 2. Database Capacity

### Table Growth Tracking

```sql
-- PostgreSQL: Record table sizes weekly
SELECT
    schemaname || '.' || relname AS table_name,
    pg_size_pretty(pg_total_relation_size(relid)) AS total_size,
    pg_total_relation_size(relid) AS total_bytes,
    n_live_tup AS row_count,
    now() AS measured_at
FROM pg_stat_user_tables
ORDER BY pg_total_relation_size(relid) DESC;
```

Store these results in a tracking table or spreadsheet. After 4 weeks:

```
weekly_growth_bytes = (week4_bytes - week1_bytes) / 4
daily_growth_bytes = weekly_growth_bytes / 7
days_until_limit = (max_db_size - current_size) / daily_growth_bytes
```

### Index Overhead Estimation

Indexes typically add 20-50% overhead on top of table data:

```sql
-- Index to table size ratio
SELECT
    schemaname || '.' || relname AS table_name,
    pg_size_pretty(pg_relation_size(relid)) AS table_size,
    pg_size_pretty(pg_total_relation_size(relid) - pg_relation_size(relid)) AS index_size,
    ROUND(
        (pg_total_relation_size(relid) - pg_relation_size(relid))::numeric
        / NULLIF(pg_relation_size(relid), 0) * 100, 1
    ) AS index_overhead_pct
FROM pg_stat_user_tables
ORDER BY pg_total_relation_size(relid) DESC
LIMIT 20;
```

If index overhead exceeds 100%, review for unused or redundant indexes.

### Connection Pool Sizing

```sql
-- Current connection usage
SELECT
    count(*) AS total_connections,
    count(*) FILTER (WHERE state = 'active') AS active,
    count(*) FILTER (WHERE state = 'idle') AS idle,
    count(*) FILTER (WHERE state = 'idle in transaction') AS idle_in_txn,
    (SELECT setting::int FROM pg_settings WHERE name = 'max_connections') AS max_connections
FROM pg_stat_activity;
```

**Sizing formula:**

```
pool_size = (active_connections_at_peak * 1.5) + headroom

# Headroom: 10-20% of max for admin connections, monitoring, migrations
# Example: Peak active = 40, pool_size = 40 * 1.5 + 10 = 70
```

Warning signs:
- Active connections > 80% of pool size at peak
- Any `idle in transaction` connections lasting > 30 seconds
- Connection wait time appearing in application logs

### Read Replica Lag

```sql
-- PostgreSQL streaming replication lag
SELECT
    client_addr,
    state,
    sent_lsn,
    write_lsn,
    flush_lsn,
    replay_lsn,
    pg_wal_lsn_diff(sent_lsn, replay_lsn) AS replay_lag_bytes
FROM pg_stat_replication;
```

- Healthy: lag < 1 MB
- Warning: lag > 10 MB or growing
- Critical: lag > 100 MB (replica falling behind, may need rebuild)

---

## 3. Traffic / Compute Capacity

### Request Rate Analysis

Track these metrics over time (minimum 4 weeks, ideally with monthly and seasonal data):

```
Metric               | Average | P50  | P95    | P99    | Peak
---------------------|---------|------|--------|--------|------
Requests/sec         | 150     | 140  | 280    | 450    | 600
Response time (ms)   | 45      | 30   | 120    | 350    | 1200
Error rate (%)       | 0.1     | 0.05 | 0.3    | 1.2    | 3.0
CPU utilization (%)  | 35      | 30   | 55     | 72     | 88
Memory utilization   | 60      | 58   | 65     | 70     | 78
```

### Scaling Trigger Analysis

Review historical auto-scaling events:

```bash
# AWS Auto Scaling history
aws autoscaling describe-scaling-activities \
    --auto-scaling-group-name my-asg \
    --max-items 20

# Kubernetes HPA events
kubectl describe hpa my-app-hpa
```

Questions to answer:
- At what request rate does auto-scaling trigger?
- How long between trigger and new capacity available?
- Does scaling out happen fast enough to prevent degradation?
- Are there traffic patterns that outpace scaling speed?

### Horizontal vs Vertical Scaling Decision

| Factor | Horizontal (add instances) | Vertical (bigger instance) |
|--------|---------------------------|---------------------------|
| Stateless service | Preferred | Acceptable |
| Stateful service | Complex (requires sharding) | Simpler (has limits) |
| Cost at scale | Linear | Superlinear (bigger = disproportionately expensive) |
| Failure domain | Resilient (one instance down is N-1) | Single point of failure |
| Implementation | Requires load balancer, session handling | Change instance type, restart |
| Latency | No improvement per request | May improve if CPU-bound |
| Max capacity | Near-unlimited | Hard ceiling per instance |

**Decision framework:**

1. If CPU-bound and parallelizable: horizontal
2. If memory-bound with shared state: vertical (or re-architect)
3. If IO-bound: fix the IO bottleneck first
4. If already at largest instance type: must go horizontal
5. Default preference: horizontal (better resilience, linear cost)

---

## 4. Cost Optimization

### Right-Sizing Instances

```bash
# AWS: Check CPU/memory utilization over 14 days
aws cloudwatch get-metric-statistics \
    --namespace AWS/EC2 \
    --metric-name CPUUtilization \
    --dimensions Name=InstanceId,Value=i-xxxx \
    --start-time $(date -u -v-14d +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 3600 --statistics Average Maximum
```

**Right-sizing rules:**

| Peak CPU | Peak Memory | Recommendation |
|----------|-------------|----------------|
| < 20% | < 30% | Downsize 2 tiers |
| 20-40% | 30-50% | Downsize 1 tier |
| 40-70% | 50-80% | Correct size |
| > 70% | > 80% | Consider upsizing |

### Reserved vs On-Demand Break-Even

```
monthly_on_demand = hourly_rate * 730 hours
monthly_reserved = (upfront / 12 months) + hourly_reserved * 730
break_even_utilization = monthly_reserved / monthly_on_demand

# Example (m5.xlarge, us-east-1):
# On-demand: $0.192/hr * 730 = $140.16/mo
# 1yr reserved (no upfront): $0.124/hr * 730 = $90.52/mo
# Savings: 35%
# Break-even: 65% utilization (if used < 65% of the time, on-demand is cheaper)
```

### Idle Resource Identification

```bash
# AWS: Unattached EBS volumes
aws ec2 describe-volumes --filters Name=status,Values=available \
    --query 'Volumes[].{ID:VolumeId,Size:Size,Created:CreateTime}'

# AWS: Idle load balancers (zero active connections)
aws elbv2 describe-load-balancers --query 'LoadBalancers[].LoadBalancerArn' --output text | \
while read arn; do
    conns=$(aws cloudwatch get-metric-statistics \
        --namespace AWS/ApplicationELB \
        --metric-name ActiveConnectionCount \
        --dimensions Name=LoadBalancer,Value="${arn##*/}" \
        --start-time $(date -u -v-7d +%Y-%m-%dT%H:%M:%S) \
        --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
        --period 86400 --statistics Sum \
        --query 'Datapoints[].Sum' --output text)
    echo "$arn: $conns connections in 7d"
done

# AWS: Old snapshots
aws ec2 describe-snapshots --owner-ids self \
    --query 'Snapshots[?StartTime<`2025-01-01`].{ID:SnapshotId,Size:VolumeSize,Date:StartTime}'
```

### Data Transfer Cost Analysis

Data transfer is often the hidden cost. Check:

- Cross-AZ traffic (charged per GB in most clouds)
- NAT gateway throughput (expensive at scale)
- CloudFront/CDN cache hit rate (misses = origin fetch = data transfer)
- S3 request costs (many small requests vs fewer large requests)

---

## 5. Capacity Planning Template

Use this template for periodic (monthly or quarterly) capacity reviews.

```
CAPACITY PLANNING REPORT
========================
Date: [timestamp]
Period: [current month/quarter]
Next review: [date]

1. CURRENT STATE
================

Resource        | Total   | Used    | Available | Usage %
----------------|---------|---------|-----------|--------
Disk (vol-A)    | 500 GB  | 350 GB  | 150 GB    | 70%
Disk (vol-B)    | 200 GB  | 120 GB  | 80 GB     | 60%
Database        | 100 GB  | 45 GB   | 55 GB     | 45%
Memory (avg)    | 16 GB   | 10 GB   | 6 GB      | 63%
CPU (avg peak)  |         |         |           | 55%
Connections     | 100     | 65      | 35        | 65%

2. GROWTH RATE
==============

Resource        | 30d ago | Today   | Daily Growth | Monthly Growth
----------------|---------|---------|--------------|---------------
Disk (vol-A)    | 330 GB  | 350 GB  | 0.67 GB/day  | 20 GB/mo
Database        | 40 GB   | 45 GB   | 0.17 GB/day  | 5 GB/mo
Requests/sec    | 120 avg | 150 avg | +1/day       | +30/mo

3. PROJECTIONS (at current growth rate)
=======================================

Resource        | 30-day  | 60-day  | 90-day  | Days to Threshold
----------------|---------|---------|---------|-------------------
Disk (vol-A)    | 370 GB  | 390 GB  | 410 GB  | 224 days to 80%
Database        | 50 GB   | 55 GB   | 60 GB   | 323 days to 80%
Connections     | 70      | 75      | 80      | 175 days to 80%

(Conservative estimate uses 1.5x growth factor)

Resource        | Conservative days to 80%
----------------|-------------------------
Disk (vol-A)    | 149 days
Database        | 215 days
Connections     | 117 days

4. RECOMMENDATIONS
==================

Priority | Resource     | Action              | Cost Impact  | Timeline
---------|-------------|---------------------|--------------|----------
LOW      | Disk vol-A  | Monitor, plan at 80%| $0 now       | 5 months
LOW      | Database    | Monitor             | $0 now       | 7 months
MEDIUM   | Connections | Increase pool size  | $0           | Next sprint
HIGH     | [example]   | Expand volume       | $XX/month    | This week

5. COST OPTIMIZATION OPPORTUNITIES
===================================

Opportunity              | Current Cost | Optimized  | Savings
------------------------|-------------|------------|--------
Right-size web instances | $X/mo       | $Y/mo      | $Z/mo
Reserved DB instance     | $X/mo       | $Y/mo      | $Z/mo
Delete old snapshots     | $X/mo       | $0         | $X/mo
CDN cache improvement    | $X/mo       | $Y/mo      | $Z/mo

TOTAL POTENTIAL SAVINGS: $ZZZ/month

6. ACTION ITEMS
===============

- [ ] [Action] - Owner: [name] - Due: [date]
- [ ] [Action] - Owner: [name] - Due: [date]
- [ ] [Action] - Owner: [name] - Due: [date]
```

### Projection Calculation Examples

**Example 1: Disk Growth Projection**

```
Week 1: 320 GB used
Week 2: 325 GB used
Week 3: 331 GB used
Week 4: 338 GB used

Total growth over 4 weeks: 338 - 320 = 18 GB
Weekly growth: 18 / 4 = 4.5 GB/week
Daily growth: 4.5 / 7 = 0.64 GB/day

Total disk: 500 GB
Free space: 500 - 338 = 162 GB
Days until 80% (400 GB): (400 - 338) / 0.64 = 97 days
Days until 90% (450 GB): (450 - 338) / 0.64 = 175 days
Days until full: 162 / 0.64 = 253 days

Conservative (1.5x): 97 / 1.5 = 65 days to 80%
```

**Example 2: Database Connection Pool**

```
Peak active connections: 45
Current pool max: 60
max_connections (PostgreSQL): 100
Admin/monitoring reserved: 10

Available for application: 100 - 10 = 90
Current utilization at peak: 45 / 60 = 75%

If traffic grows 10%/month:
  Month 1 peak: 50 connections (83% of pool)
  Month 2 peak: 55 connections (92% of pool) -- WARNING
  Month 3 peak: 60 connections (100% of pool) -- CRITICAL

Action: Increase pool to 80 within 30 days.
Consider: pgBouncer for connection pooling if max_connections is the limit.
```

**Example 3: Cost Right-Sizing**

```
Instance: m5.2xlarge (8 vCPU, 32 GB RAM)
Cost: $0.384/hr = $280/month

Observed utilization (14-day average):
  CPU: 22% average, 45% peak
  Memory: 38% average, 52% peak

Both metrics suggest m5.xlarge (4 vCPU, 16 GB RAM) would suffice:
  CPU headroom: 45% peak on 8 vCPU = 3.6 vCPU needed, 4 available
  Memory headroom: 52% of 32 GB = 16.6 GB needed, 16 GB tight

Recommendation: m5.xlarge for non-critical workloads ($140/month, 50% savings)
              : m5.2xlarge is correct for production with memory safety margin
Alternative   : r5.xlarge (4 vCPU, 32 GB) if memory-heavy ($0.252/hr = $184/mo, 34% savings)
```
