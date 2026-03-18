# Health Check Patterns

Platform-specific health check implementations. For each platform: commands to run, what "healthy" looks like, and red flags to investigate.

---

## 1. Bare Metal / VM

### System Resources

```bash
# Disk usage (all mounted filesystems)
df -h
# Healthy: All volumes < 80%
# Red flag: Any volume > 90%, rapid growth since last check

# Inode usage (often overlooked)
df -i
# Healthy: All volumes < 80% inode usage
# Red flag: High inode usage with low disk usage = millions of small files

# Memory
free -m                    # Linux
vm_stat && sysctl hw.memsize  # macOS
# Healthy: Available memory > 15% of total, swap usage < 10%
# Red flag: Swap actively used, available near zero

# CPU load average
uptime
# Healthy: 1-min load average < number of CPU cores
# Red flag: Load average consistently > 2x core count

# Top processes by resource usage
ps aux --sort=-%mem | head -10   # Top memory consumers
ps aux --sort=-%cpu | head -10   # Top CPU consumers
```

### Services

```bash
# Listening ports
ss -tlnp                   # Linux
lsof -iTCP -sTCP:LISTEN    # macOS
# Healthy: Expected ports are listening (80, 443, 5432, 6379, etc.)
# Red flag: Expected port not listening, unexpected port listening

# Service status (systemd)
systemctl status nginx postgresql redis-server
# Healthy: active (running), no recent restarts
# Red flag: activating (auto-restart), failed, frequent restarts

# Recent logs
journalctl -u myservice --since "1 hour ago" --priority=err
# Healthy: No error-level messages
# Red flag: Repeated errors, OOM kills, segfaults

# Process uptime (detect silent restarts)
ps -eo pid,etime,comm | grep -E "nginx|postgres|redis"
# Healthy: Uptime matches expected (no unexpected restarts)
# Red flag: Process uptime of seconds/minutes when it should be days
```

### Network

```bash
# DNS resolution
dig example.com +short
nslookup example.com
# Healthy: Resolves quickly (< 50ms)
# Red flag: Timeouts, SERVFAIL, unexpected IP

# Connectivity to dependencies
curl -sS -o /dev/null -w "%{http_code} %{time_total}s" https://api.example.com/health
# Healthy: 200 response in < 1s
# Red flag: Non-200, response time > 5s, connection refused

# Latency to critical services
ping -c 3 database-host
# Healthy: < 1ms for same-datacenter, < 50ms for same-region
# Red flag: Packet loss, jitter, latency spikes
```

---

## 2. Docker

### Container Health

```bash
# Running containers and their status
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
# Healthy: All expected containers are "Up", health status is "(healthy)"
# Red flag: Restarting, unhealthy, exited

# Container resource usage (live)
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.NetIO}}\t{{.BlockIO}}"
# Healthy: Memory usage well below limits, CPU reasonable
# Red flag: Memory at limit (OOM risk), CPU pegged at 100%

# Recent logs (last 100 lines, errors only)
docker logs --tail 100 container_name 2>&1 | grep -iE "error|fatal|panic|exception"
# Healthy: No error lines
# Red flag: Repeated errors, connection failures, OOM messages
```

### Resource Limits

```bash
# Check memory limits vs usage
docker inspect --format='{{.Name}}: Memory Limit={{.HostConfig.Memory}} Swap={{.HostConfig.MemorySwap}}' $(docker ps -q)
# Healthy: Limits set and usage well below
# Red flag: No limits set (container can consume all host memory)

# OOM detection
docker inspect --format='{{.Name}}: OOMKilled={{.State.OOMKilled}}' $(docker ps -aq) | grep true
# Healthy: No OOM kills
# Red flag: Any OOM kill indicates memory limit too low or memory leak

# Restart count (detect crash loops)
docker inspect --format='{{.Name}}: Restarts={{.RestartCount}}' $(docker ps -q)
# Healthy: Restart count is 0 or very low
# Red flag: High restart count, especially if recent
```

### Networking

```bash
# Container connectivity to other containers
docker exec app_container ping -c 1 db_container
# Healthy: Responds
# Red flag: Name resolution failure, timeout

# Port mapping verification
docker port container_name
# Healthy: Expected ports mapped
# Red flag: Missing port mapping

# DNS resolution inside container
docker exec container_name nslookup external-service.com
# Healthy: Resolves correctly
# Red flag: DNS failure inside container (Docker DNS issue)
```

### Storage

```bash
# Docker disk usage summary
docker system df
# Healthy: Reasonable image count, no excessive build cache
# Red flag: Build cache > 10 GB, hundreds of dangling images

# Volume usage
docker system df -v | grep -A 100 "VOLUME NAME"
# Healthy: Volumes within expected size
# Red flag: Unexpectedly large volumes, orphaned volumes

# Image layer analysis
docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}" | sort -k3 -h
# Healthy: Images reasonably sized for their purpose
# Red flag: Application images > 1 GB (likely not multi-stage)
```

---

## 3. Kubernetes

### Cluster Health

```bash
# Node status
kubectl get nodes -o wide
# Healthy: All nodes Ready, version consistent
# Red flag: NotReady nodes, version skew

# Resource allocation
kubectl top nodes
kubectl describe nodes | grep -A 5 "Allocated resources"
# Healthy: CPU and memory requests < 80% of allocatable
# Red flag: > 90% allocated (scheduling failures imminent)

# System pods
kubectl get pods -n kube-system
# Healthy: All Running, 0 restarts
# Red flag: CrashLoopBackOff, Pending, frequent restarts
```

### Workloads

```bash
# Deployment status
kubectl get deployments -A --field-selector metadata.namespace!=kube-system
# Healthy: READY matches DESIRED for all deployments
# Red flag: READY < DESIRED, unavailable replicas

# Pod health across all namespaces
kubectl get pods -A | grep -v Running | grep -v Completed
# Healthy: Only Running and Completed pods (completed = finished jobs)
# Red flag: CrashLoopBackOff, ImagePullBackOff, Pending, OOMKilled

# Recent pod restarts
kubectl get pods -A --sort-by='.status.containerStatuses[0].restartCount' | tail -10
# Healthy: Low restart counts
# Red flag: High restart counts, especially increasing

# OOMKilled detection
kubectl get pods -A -o json | jq -r '.items[] | select(.status.containerStatuses[]?.lastState.terminated.reason == "OOMKilled") | .metadata.namespace + "/" + .metadata.name'
# Healthy: No results
# Red flag: Any OOMKilled pods (increase memory limits or fix leak)

# Events (recent issues)
kubectl get events -A --sort-by='.lastTimestamp' | tail -20
# Healthy: No Warning events
# Red flag: FailedScheduling, FailedMount, Unhealthy, BackOff
```

### Networking

```bash
# Service endpoints
kubectl get endpoints -A | awk '$2 == "<none>" || $2 == ""'
# Healthy: All services have endpoints
# Red flag: Service with no endpoints = no healthy pods matching selector

# Ingress status
kubectl get ingress -A
# Healthy: All ingresses have an ADDRESS assigned
# Red flag: Missing ADDRESS, incorrect backends

# cert-manager certificates
kubectl get certificates -A
# Healthy: All True in READY column
# Red flag: False = certificate issuance failed
```

### Storage

```bash
# PVC status
kubectl get pvc -A
# Healthy: All Bound
# Red flag: Pending = storage class unavailable or capacity exhausted

# PVC usage (requires metrics-server or exec into pods)
kubectl exec -it pod-name -- df -h /data
# Healthy: Usage < 80%
# Red flag: > 90%, especially for databases
```

---

## 4. Serverless

### Function Health (AWS Lambda)

```bash
# Function configuration
aws lambda get-function-configuration --function-name my-function \
    --query '{Memory:MemorySize,Timeout:Timeout,Runtime:Runtime,CodeSize:CodeSize}'

# Recent invocations (CloudWatch)
aws cloudwatch get-metric-statistics \
    --namespace AWS/Lambda \
    --metric-name Invocations \
    --dimensions Name=FunctionName,Value=my-function \
    --start-time $(date -u -v-1H +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 --statistics Sum

# Error rate
aws cloudwatch get-metric-statistics \
    --namespace AWS/Lambda \
    --metric-name Errors \
    --dimensions Name=FunctionName,Value=my-function \
    --start-time $(date -u -v-1H +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 --statistics Sum
# Healthy: Error count is 0 or very low relative to invocations
# Red flag: Error rate > 1%, increasing trend

# Duration percentiles
aws cloudwatch get-metric-statistics \
    --namespace AWS/Lambda \
    --metric-name Duration \
    --dimensions Name=FunctionName,Value=my-function \
    --start-time $(date -u -v-1H +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 --statistics Average Maximum
# Healthy: Average well below timeout, max not hitting timeout
# Red flag: Max duration = timeout (function is timing out)
```

### Limits and Quotas

```bash
# Concurrent execution
aws lambda get-account-settings --query 'AccountLimit.ConcurrentExecutions'

# Reserved concurrency per function
aws lambda get-function-concurrency --function-name my-function

# Throttling check
aws cloudwatch get-metric-statistics \
    --namespace AWS/Lambda \
    --metric-name Throttles \
    --dimensions Name=FunctionName,Value=my-function \
    --start-time $(date -u -v-1H +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 --statistics Sum
# Healthy: Zero throttles
# Red flag: Any throttles = concurrency limit hit
```

### Cost Signals

```bash
# GB-seconds consumed (proxy for cost)
# Duration (ms) * MemorySize (MB) / 1024 = GB-ms per invocation
# Multiply by invocation count for total

# Over-provisioned functions (low memory utilization)
# Check CloudWatch Insights:
# filter @type = "REPORT"
# | stats max(@memorySize / 1024 / 1024) as provisioned_mb,
#         max(@maxMemoryUsed / 1024 / 1024) as used_mb
#         by @logStream
# Healthy: Used > 50% of provisioned
# Red flag: Used < 25% of provisioned = wasting money

# Cold start frequency
# filter @type = "REPORT" and @initDuration > 0
# | stats count() as cold_starts, count() * 100.0 / (select count()) as cold_pct
# Healthy: Cold starts < 5% of invocations
# Red flag: > 20% cold starts = consider provisioned concurrency
```

---

## General Health Check Summary Format

After running platform-specific checks, compile results into a standardized report:

```
HEALTH CHECK REPORT
===================
Host/Cluster: [identifier]
Date: [timestamp]
Platform: [bare metal / docker / kubernetes / serverless]

System Resources:
  [PASS/WARN/FAIL] Disk: [usage details per volume]
  [PASS/WARN/FAIL] Memory: [usage and swap]
  [PASS/WARN/FAIL] CPU: [load average vs core count]
  [PASS/WARN/FAIL] Inodes: [usage if applicable]

Services:
  [PASS/WARN/FAIL] [service-name]: [status, uptime, port]
  ...

Security:
  [PASS/WARN/FAIL] SSL Certs: [nearest expiry]
  [PASS/WARN/FAIL] Vulnerabilities: [count by severity]

Data:
  [PASS/WARN/FAIL] Database: [size, connections, bloat]
  [PASS/WARN/FAIL] Logs: [volume, rotation status]
  [PASS/WARN/FAIL] Cache: [hit rate, memory usage]

Summary: X pass, Y warn, Z fail
Next check due: [date based on cadence]
```
