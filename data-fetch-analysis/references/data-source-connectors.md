# Data Source Connectors

Connection patterns, read-only enforcement, timeout configuration, and common gotchas for each data source.

## 1. PostgreSQL

### Connection via psql CLI

```bash
# Basic connection
psql -h hostname -p 5432 -U readonly_user -d database_name

# With connection string
psql "postgresql://readonly_user@hostname:5432/database_name?sslmode=require"

# With explicit timeout (connect timeout in seconds)
psql "postgresql://readonly_user@hostname:5432/database_name?connect_timeout=10&sslmode=require"
```

### Read-Only User Setup

```sql
-- Create a read-only role for investigation queries
CREATE ROLE readonly_analyst LOGIN PASSWORD 'secure_password';
GRANT CONNECT ON DATABASE mydb TO readonly_analyst;
GRANT USAGE ON SCHEMA public TO readonly_analyst;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO readonly_analyst;

-- Ensure future tables are also readable
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT SELECT ON TABLES TO readonly_analyst;
```

### Statement Timeout

```sql
-- Set per-session timeout (prevents runaway queries)
SET statement_timeout = '30s';

-- Set per-transaction timeout
BEGIN;
SET LOCAL statement_timeout = '10s';
SELECT ...;
COMMIT;

-- Check current timeout
SHOW statement_timeout;
```

### SSL Configuration

```bash
# Require SSL (recommended for production)
psql "sslmode=require host=prod-db.example.com ..."

# Verify server certificate
psql "sslmode=verify-full sslrootcert=/path/to/ca.pem ..."
```

### Common Gotchas

- **Idle connections**: PostgreSQL has a connection limit. Always disconnect when done.
- **search_path**: Queries may hit unexpected schemas. Run `SHOW search_path` and set explicitly.
- **Timezone**: Check `SHOW timezone`. Convert with `AT TIME ZONE` for consistent results.
- **NULL handling**: PostgreSQL treats NULL != NULL. Use `IS NOT DISTINCT FROM` for null-safe comparisons.

## 2. MySQL

### Connection via mysql CLI

```bash
# Basic connection
mysql -h hostname -P 3306 -u readonly_user -p database_name

# With explicit timeout and SSL
mysql -h hostname -u readonly_user -p \
    --connect-timeout=10 \
    --ssl-mode=REQUIRED \
    database_name

# Read from a specific replica
mysql -h replica-hostname -u readonly_user -p database_name
```

### Read-Only Enforcement

```sql
-- Create read-only user
CREATE USER 'readonly_analyst'@'%' IDENTIFIED BY 'secure_password';
GRANT SELECT ON mydb.* TO 'readonly_analyst'@'%';
FLUSH PRIVILEGES;

-- Session-level read-only mode
SET SESSION TRANSACTION READ ONLY;
```

### Timeout Settings

```sql
-- Query execution timeout (milliseconds)
SET SESSION MAX_EXECUTION_TIME = 30000;

-- Connection wait timeout (seconds)
SET SESSION wait_timeout = 300;

-- Net read/write timeout (seconds)
SET SESSION net_read_timeout = 30;
```

### Common Gotchas

- **sql_mode**: Different modes change behavior (e.g., strict mode, ONLY_FULL_GROUP_BY). Check with `SELECT @@sql_mode`.
- **Character set**: Ensure client and server agree. Use `SET NAMES 'utf8mb4'`.
- **No LATERAL joins**: Use correlated subqueries or window functions instead.
- **LIMIT without ORDER BY**: Results are nondeterministic. Always pair LIMIT with ORDER BY.
- **GROUP BY behavior**: Without `ONLY_FULL_GROUP_BY`, MySQL silently picks arbitrary values for non-grouped columns.

## 3. Redis

### Connection via redis-cli

```bash
# Basic connection
redis-cli -h hostname -p 6379 -a password

# With TLS
redis-cli -h hostname -p 6380 --tls --cert /path/to/cert --key /path/to/key

# Select specific database
redis-cli -h hostname -n 2
```

### Key Scanning Patterns

```bash
# NEVER use KEYS in production (blocks server). Use SCAN instead.
# Scan for keys matching a pattern
redis-cli -h hostname SCAN 0 MATCH "session:*" COUNT 100

# Get key type
redis-cli -h hostname TYPE "session:abc123"

# Get TTL
redis-cli -h hostname TTL "session:abc123"

# Inspect value by type
redis-cli -h hostname GET "cache:user:123"           # string
redis-cli -h hostname HGETALL "user:123"              # hash
redis-cli -h hostname LRANGE "queue:emails" 0 9       # list (first 10)
redis-cli -h hostname SMEMBERS "tags:post:456"        # set
redis-cli -h hostname ZRANGE "leaderboard" 0 9 WITHSCORES  # sorted set
```

### Memory Analysis

```bash
# Overall memory usage
redis-cli -h hostname INFO memory

# Memory usage for a specific key
redis-cli -h hostname MEMORY USAGE "large:key:name"

# Find biggest keys (samples from keyspace)
redis-cli -h hostname --bigkeys

# Key count per database
redis-cli -h hostname INFO keyspace
```

### Slow Log

```bash
# View recent slow queries (default threshold: 10ms)
redis-cli -h hostname SLOWLOG GET 10

# Check slow log threshold
redis-cli -h hostname CONFIG GET slowlog-log-slower-than
```

### Common Gotchas

- **KEYS command**: Blocks the entire server. Always use SCAN with COUNT for production.
- **Single-threaded**: Long-running commands block all other operations.
- **Memory limits**: Check `maxmemory` and `maxmemory-policy` to understand eviction behavior.
- **Persistence**: Check if AOF/RDB is enabled. Data may not survive restarts.

## 4. MongoDB

### Connection via mongosh

```bash
# Basic connection
mongosh "mongodb://hostname:27017/database_name"

# With authentication
mongosh "mongodb://readonly_user:password@hostname:27017/database_name?authSource=admin"

# With replica set and read preference
mongosh "mongodb://host1,host2,host3/database_name?replicaSet=rs0&readPreference=secondaryPreferred"
```

### Read Preference

```javascript
// In mongosh: read from secondary (replica) for analytics
db.getMongo().setReadPref("secondaryPreferred")

// Per-query read preference
db.collection.find({}).readPref("secondary")
```

### Query Profiling

```javascript
// Check current profiling level
db.getProfilingStatus()

// View slow queries (> 100ms)
db.system.profile.find({ millis: { $gt: 100 } }).sort({ ts: -1 }).limit(10)

// Explain a query
db.collection.find({ status: "active" }).explain("executionStats")
```

### Safe Query Patterns

```javascript
// Always limit exploratory queries
db.orders.find({ status: "failed" }).limit(10)

// Use projection to fetch only needed fields
db.orders.find(
    { status: "failed" },
    { customer_id: 1, amount: 1, created_at: 1, _id: 0 }
).limit(20)

// Aggregation with limits
db.orders.aggregate([
    { $match: { created_at: { $gte: new Date(Date.now() - 86400000) } } },
    { $group: { _id: "$status", count: { $sum: 1 } } },
    { $sort: { count: -1 } },
    { $limit: 20 }
])
```

### Common Gotchas

- **No schema enforcement by default**: Fields may be missing, misspelled, or have inconsistent types.
- **ObjectId contains timestamp**: Extract creation time with `ObjectId.getTimestamp()` instead of a separate field.
- **Aggregation memory limit**: Pipeline stages are limited to 100MB by default. Use `{ allowDiskUse: true }` for large aggregations.
- **Index usage**: Use `.explain()` to verify index usage. Without indexes, queries scan the entire collection.

## 5. Application Logs

### Structured JSON Log Parsing with jq

```bash
# Parse JSON logs for errors in the last hour
cat /var/log/app/application.log | jq 'select(.level == "error")'

# Count errors by type
cat /var/log/app/application.log \
    | jq -r 'select(.level == "error") | .error_type' \
    | sort | uniq -c | sort -rn | head -20

# Extract specific fields from JSON logs
cat /var/log/app/application.log \
    | jq -r 'select(.level == "error") | [.timestamp, .error_type, .message] | @tsv'

# Filter by time range (ISO 8601 timestamps)
cat /var/log/app/application.log \
    | jq 'select(.timestamp >= "2026-03-17T00:00:00Z" and .timestamp < "2026-03-17T01:00:00Z")'
```

### Grep Patterns for Common Log Formats

```bash
# Nginx access log: find 5xx errors
grep ' 5[0-9][0-9] ' /var/log/nginx/access.log | tail -50

# Apache combined log format: extract slow responses (>5s)
awk '$NF > 5000000' /var/log/apache2/access.log | tail -20

# Syslog: find OOM killer events
grep -i 'out of memory\|oom-killer' /var/log/syslog

# Application logs: find stack traces
grep -A 20 'Exception\|Traceback\|panic:' /var/log/app/error.log | tail -100
```

### Log Aggregation Patterns

```bash
# Requests per minute from access logs
awk '{print $4}' /var/log/nginx/access.log \
    | cut -d: -f1-3 \
    | sort | uniq -c | sort -rn | head -30

# Error rate by response code
awk '{print $9}' /var/log/nginx/access.log \
    | sort | uniq -c | sort -rn

# Top IP addresses by request count
awk '{print $1}' /var/log/nginx/access.log \
    | sort | uniq -c | sort -rn | head -20
```

### Common Gotchas

- **Log rotation**: Recent logs may be in `application.log.1` or compressed as `.gz`. Check rotated files.
- **Buffer flushing**: Recent events may not be on disk yet. Check application flush settings.
- **Multi-line entries**: Stack traces span multiple lines. Use `grep -A` or jq for structured logs.
- **Disk space**: Piping large logs through multiple commands uses memory. Use `head` or time-based filters early in the pipeline.

## 6. HTTP APIs

### Curl Patterns with Authentication

```bash
# Bearer token authentication
curl -s -H "Authorization: Bearer ${API_TOKEN}" \
    "https://api.example.com/v1/metrics?period=1h" | jq .

# Basic authentication
curl -s -u "${API_USER}:${API_PASSWORD}" \
    "https://api.example.com/v1/data" | jq .

# API key in header
curl -s -H "X-API-Key: ${API_KEY}" \
    "https://api.example.com/v1/stats" | jq .

# With timeout (connect and max time)
curl -s --connect-timeout 10 --max-time 30 \
    -H "Authorization: Bearer ${API_TOKEN}" \
    "https://api.example.com/v1/data" | jq .
```

### Pagination Handling

```bash
# Offset-based pagination
PAGE=1
while true; do
    RESPONSE=$(curl -s -H "Authorization: Bearer ${API_TOKEN}" \
        "https://api.example.com/v1/items?page=${PAGE}&per_page=100")

    COUNT=$(echo "$RESPONSE" | jq '.items | length')
    echo "$RESPONSE" | jq '.items[]'

    [ "$COUNT" -lt 100 ] && break
    PAGE=$((PAGE + 1))
    sleep 1  # respect rate limits
done

# Cursor-based pagination
CURSOR=""
while true; do
    RESPONSE=$(curl -s -H "Authorization: Bearer ${API_TOKEN}" \
        "https://api.example.com/v1/items?cursor=${CURSOR}&limit=100")

    echo "$RESPONSE" | jq '.items[]'

    CURSOR=$(echo "$RESPONSE" | jq -r '.next_cursor // empty')
    [ -z "$CURSOR" ] && break
    sleep 1
done
```

### Rate Limit Handling

```bash
# Check rate limit headers
curl -s -I -H "Authorization: Bearer ${API_TOKEN}" \
    "https://api.example.com/v1/status" \
    | grep -i 'x-ratelimit\|retry-after'

# Common rate limit headers:
# X-RateLimit-Limit: 100
# X-RateLimit-Remaining: 42
# X-RateLimit-Reset: 1710633600
# Retry-After: 30
```

### Common Gotchas

- **Rate limits**: Always check response headers. Back off on 429 responses.
- **Pagination completeness**: Do not assume a single page returns all results.
- **API versioning**: Pin to a specific API version in the URL or Accept header.
- **Response size**: Some APIs return megabytes per request. Use `jq` to filter early.
- **Authentication expiry**: Tokens expire. Check for 401 responses and refresh.

## 7. Prometheus / Grafana

### PromQL Basics

```promql
# Instant query: current value
http_requests_total{job="api-server", status="500"}

# Range query: values over time
http_requests_total{job="api-server"}[5m]

# Rate: per-second average over a window
rate(http_requests_total{job="api-server"}[5m])

# Increase: total increase over a window
increase(http_requests_total{job="api-server"}[1h])
```

### Rate vs Increase

```promql
# rate(): per-second average rate of increase (use for dashboards and alerts)
rate(http_requests_total[5m])

# increase(): total increase over the window (use for "how many in the last hour")
increase(http_requests_total[1h])

# irate(): instant rate using the last two data points (use for spiky, high-resolution data)
irate(http_requests_total[5m])
```

### Histogram Queries

```promql
# P95 response time from a histogram
histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))

# P95 grouped by endpoint
histogram_quantile(0.95,
    sum(rate(http_request_duration_seconds_bucket[5m])) by (le, handler)
)

# Average from histogram
rate(http_request_duration_seconds_sum[5m])
/
rate(http_request_duration_seconds_count[5m])
```

### Querying via API

```bash
# Instant query
curl -s -G "http://prometheus:9090/api/v1/query" \
    --data-urlencode "query=rate(http_requests_total{status='500'}[5m])" \
    | jq '.data.result'

# Range query (last hour, 1-minute steps)
curl -s -G "http://prometheus:9090/api/v1/query_range" \
    --data-urlencode "query=rate(http_requests_total[5m])" \
    --data-urlencode "start=$(date -d '1 hour ago' +%s)" \
    --data-urlencode "end=$(date +%s)" \
    --data-urlencode "step=60" \
    | jq '.data.result'

# Grafana API: query a specific dashboard
curl -s -H "Authorization: Bearer ${GRAFANA_TOKEN}" \
    "https://grafana.example.com/api/dashboards/uid/abc123" \
    | jq '.dashboard.panels[] | {title: .title, type: .type}'
```

### Useful Diagnostic Queries

```promql
# Error rate as a percentage
sum(rate(http_requests_total{status=~"5.."}[5m]))
/
sum(rate(http_requests_total[5m]))
* 100

# Top 5 endpoints by request rate
topk(5, sum(rate(http_requests_total[5m])) by (handler))

# Memory usage percentage
(node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes)
/ node_memory_MemTotal_bytes * 100

# Disk space remaining
node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"} * 100

# CPU usage per core
1 - rate(node_cpu_seconds_total{mode="idle"}[5m])
```

### Common Gotchas

- **rate() needs a range**: `rate(metric)` is invalid; must be `rate(metric[5m])`.
- **Counter resets**: `rate()` and `increase()` handle counter resets automatically. Do not use `delta()` on counters.
- **Staleness**: Prometheus marks series stale after 5 minutes of no samples. Gaps in scraping cause gaps in graphs.
- **Label cardinality**: High-cardinality labels (user IDs, request IDs) cause memory explosion. Query by bounded labels only.
- **Recording rules**: Complex queries that run frequently should be recording rules, not ad-hoc queries.
- **Grafana variable interpolation**: When querying the API directly, you must substitute Grafana template variables (`$interval`, `$__rate_interval`) yourself.
