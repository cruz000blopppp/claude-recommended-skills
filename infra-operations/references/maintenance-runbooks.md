# Maintenance Runbooks

Step-by-step procedures for routine infrastructure maintenance. Each runbook follows a consistent structure: pre-conditions, procedure, verification, rollback, and estimated time.

---

## 1. Dependency Updates

### Pre-Conditions

- Clean git state (`git status` shows no uncommitted changes)
- CI pipeline passing on the current branch
- Team notified that dependency updates are in progress
- Rollback plan: `git revert` the update commit(s)

### Procedure

**Phase 1: Audit**

```bash
# Node.js
npm audit
npm outdated

# Python
pip audit
pip list --outdated

# Go
go list -m -u all
govulncheck ./...

# Rust
cargo audit
cargo outdated
```

Record all findings. Categorize updates:

- **Patch** (1.2.3 -> 1.2.4): Bug fixes, safe to batch
- **Minor** (1.2.3 -> 1.3.0): New features, backward compatible, batch with caution
- **Major** (1.2.3 -> 2.0.0): Breaking changes, update individually

**Phase 2: Update Patch Versions**

```bash
# Node.js
npx npm-check-updates --target patch -u
npm install
npm test

# Python
# Update pinned versions in requirements.txt for patch bumps
pip install -r requirements.txt
pytest

# Commit if tests pass
git add -A && git commit -m "chore: update patch dependencies"
```

**Phase 3: Update Minor Versions**

```bash
# Update minor versions one category at a time
# (e.g., all testing deps, then all build deps, then runtime deps)
npx npm-check-updates --target minor -u
npm install
npm test

git add -A && git commit -m "chore: update minor dependencies"
```

**Phase 4: Update Major Versions (individually)**

```bash
# Update ONE major version at a time
npm install package-name@latest
npm test

# Check for migration guides and breaking changes
# Read the CHANGELOG.md for the package

git add -A && git commit -m "chore: update package-name to vX.0.0"
```

### Verification

- [ ] Full test suite passes
- [ ] Build succeeds
- [ ] No new vulnerabilities introduced (`npm audit` / `pip audit`)
- [ ] Application starts and serves requests
- [ ] No deprecation warnings in logs (unless pre-existing)

### Rollback

```bash
git revert <commit-hash>
npm install   # or pip install -r requirements.txt
```

### Estimated Time

- Patch updates: 15-30 minutes
- Minor updates: 30-60 minutes
- Major update (per package): 30 minutes to several hours depending on breaking changes

---

## 2. Database Maintenance (PostgreSQL)

### Pre-Conditions

- Identify low-traffic window (maintenance does not require downtime, but reduces load impact)
- Monitoring active (query latency, connection count, lock wait time)
- Application connection pool configured (not creating unbounded connections)

### Procedure

**Step 1: Check Table Bloat**

```sql
-- Tables with significant dead tuple ratio
SELECT schemaname, relname,
       n_live_tup, n_dead_tup,
       ROUND(n_dead_tup::numeric / NULLIF(n_live_tup + n_dead_tup, 0) * 100, 2) AS dead_pct,
       last_vacuum, last_autovacuum,
       last_analyze, last_autoanalyze
FROM pg_stat_user_tables
WHERE n_dead_tup > 1000
ORDER BY n_dead_tup DESC;
```

**Step 2: VACUUM ANALYZE Bloated Tables**

```sql
-- Regular VACUUM (does NOT lock the table)
VACUUM ANALYZE schema_name.table_name;

-- For all tables (routine maintenance)
VACUUM ANALYZE;
```

Do NOT use `VACUUM FULL` unless dead tuple ratio exceeds 50% and you have a maintenance window. `VACUUM FULL` rewrites the table and acquires an exclusive lock.

**Step 3: Check Index Health**

```sql
-- Unused indexes (candidates for removal)
SELECT schemaname, relname, indexrelname, idx_scan,
       pg_size_pretty(pg_relation_size(indexrelid)) AS index_size
FROM pg_stat_user_indexes
WHERE idx_scan = 0
  AND indexrelname NOT LIKE '%_pkey'
ORDER BY pg_relation_size(indexrelid) DESC;

-- Index bloat estimation
SELECT tablename, indexname,
       pg_size_pretty(pg_relation_size(indexname::regclass)) AS index_size
FROM pg_indexes
WHERE schemaname = 'public'
ORDER BY pg_relation_size(indexname::regclass) DESC
LIMIT 20;
```

**Step 4: REINDEX Degraded Indexes**

```sql
-- REINDEX CONCURRENTLY (PostgreSQL 12+, does not lock reads/writes)
REINDEX INDEX CONCURRENTLY index_name;

-- Or reindex an entire table's indexes
REINDEX TABLE CONCURRENTLY table_name;
```

**Step 5: Check Connection Pool**

```sql
-- Active connections by state
SELECT state, count(*)
FROM pg_stat_activity
WHERE datname = current_database()
GROUP BY state;

-- Long-running queries (> 5 minutes)
SELECT pid, now() - pg_stat_activity.query_start AS duration, query, state
FROM pg_stat_activity
WHERE (now() - pg_stat_activity.query_start) > interval '5 minutes'
  AND state != 'idle'
ORDER BY duration DESC;

-- Check against max_connections
SHOW max_connections;
SELECT count(*) FROM pg_stat_activity;
```

**Step 6: Check Database Size**

```sql
-- Database size
SELECT pg_size_pretty(pg_database_size(current_database()));

-- Largest tables
SELECT schemaname, relname,
       pg_size_pretty(pg_total_relation_size(relid)) AS total_size,
       pg_size_pretty(pg_relation_size(relid)) AS table_size,
       pg_size_pretty(pg_total_relation_size(relid) - pg_relation_size(relid)) AS index_size
FROM pg_stat_user_tables
ORDER BY pg_total_relation_size(relid) DESC
LIMIT 20;
```

### Verification

- [ ] Query performance stable (compare p95 latency before/after)
- [ ] No long-held locks (`SELECT * FROM pg_locks WHERE NOT granted;`)
- [ ] Connection pool healthy (idle count reasonable, no waiting connections)
- [ ] Dead tuple counts reduced

### Rollback

VACUUM and ANALYZE are safe operations and do not require rollback. REINDEX CONCURRENTLY creates a new index alongside the old one before swapping. If interrupted, drop the invalid index (`_ccnew` suffix) and retry.

### Estimated Time

- Small database (< 10 GB): 15-30 minutes
- Medium database (10-100 GB): 30-60 minutes
- Large database (> 100 GB): 1-3 hours (plan accordingly)

---

## 3. Log Management

### Pre-Conditions

- Know where logs are written (application logs, system logs, web server logs)
- Understand log rotation mechanism (logrotate, application-native, container stdout)

### Procedure

**Step 1: Check Log Volume**

```bash
# Find large log files
du -sh /var/log/* | sort -rh | head -20

# Check log directory total size
du -sh /var/log/

# Application-specific logs
du -sh /app/logs/ /var/log/nginx/ /var/log/postgresql/ 2>/dev/null
```

**Step 2: Configure Rotation (logrotate)**

```
# /etc/logrotate.d/myapp
/var/log/myapp/*.log {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    copytruncate       # Use if app cannot handle SIGHUP
    # OR
    postrotate
        systemctl reload myapp  # Use if app supports graceful reload
    endscript
}
```

Key decision: `copytruncate` vs `postrotate` reload. `copytruncate` is simpler but can lose log lines written between copy and truncate. `postrotate` with SIGHUP is cleaner but requires application support.

**Step 3: Archive Old Logs**

```bash
# Compress logs older than 7 days
find /var/log/myapp/ -name "*.log" -mtime +7 -exec gzip {} \;

# Move compressed logs to archive
mv /var/log/myapp/*.gz /archive/logs/myapp/

# Upload to long-term storage (S3, GCS)
aws s3 sync /archive/logs/ s3://my-log-archive/ --storage-class GLACIER
```

**Step 4: Enforce Retention**

```bash
# Delete logs older than 90 days
find /var/log/myapp/ -name "*.log.gz" -mtime +90 -delete
find /archive/logs/ -name "*.gz" -mtime +365 -delete
```

### Verification

- [ ] New logs are being written (application still logging after rotation)
- [ ] Old logs are compressed and archived
- [ ] Disk space freed matches expectations
- [ ] No error messages about log rotation in syslog

### Rollback

Log rotation is not destructive if archives are preserved. If an application stops logging after rotation, send SIGHUP or restart the service.

### Estimated Time

- Initial setup: 30-60 minutes
- Routine rotation: 5-10 minutes (should be automated)

---

## 4. Cache Operations

### Pre-Conditions

- Access to cache system (Redis, Memcached, CDN, application cache)
- Monitoring for cache hit/miss rates in place

### Procedure

**Step 1: Check Cache Size and Memory**

```bash
# Redis
redis-cli INFO memory | grep -E "used_memory_human|maxmemory_human|mem_fragmentation_ratio"
redis-cli DBSIZE

# Memcached
echo "stats" | nc localhost 11211 | grep -E "bytes|curr_items|limit_maxbytes"
```

**Step 2: Analyze Hit/Miss Rates**

```bash
# Redis
redis-cli INFO stats | grep -E "keyspace_hits|keyspace_misses"
# Calculate: hit_rate = hits / (hits + misses)

# Memcached
echo "stats" | nc localhost 11211 | grep -E "get_hits|get_misses"
```

Target hit rate: > 80%. Below 60% indicates a caching strategy problem (wrong TTLs, wrong data cached, cache too small).

**Step 3: Identify Stale or Oversized Entries**

```bash
# Redis: Find large keys (sample-based, non-blocking)
redis-cli --bigkeys

# Redis: Memory usage of specific key
redis-cli MEMORY USAGE key_name

# Redis: TTL check (keys without TTL grow forever)
redis-cli --scan --pattern "*" | head -100 | while read key; do
    ttl=$(redis-cli TTL "$key")
    if [ "$ttl" = "-1" ]; then
        echo "NO TTL: $key"
    fi
done
```

**Step 4: Selective Invalidation**

```bash
# Invalidate by pattern (use SCAN, never KEYS in production)
redis-cli --scan --pattern "user:cache:*" | xargs -L 100 redis-cli DEL

# Flush a specific database (not all databases)
redis-cli -n 2 FLUSHDB
```

Never run `FLUSHALL` in production without explicit confirmation. It clears all databases.

**Step 5: Verify Cold Start Behavior**

After significant cache invalidation, monitor:

- Response time increase (expected, temporary)
- Database load spike (cache misses hit the DB)
- Error rates (timeouts if DB cannot handle the load)

Consider warming the cache for critical paths before invalidating.

### Verification

- [ ] Hit rate improves or remains stable
- [ ] Response times stable (after warm-up period)
- [ ] Memory usage within configured limits
- [ ] No evictions due to memory pressure (unless expected)

### Rollback

Cache invalidation is not reversible. If response times spike, the cache will naturally repopulate. For critical paths, pre-warm the cache from the database.

### Estimated Time

- Routine check: 10-15 minutes
- Selective invalidation: 15-30 minutes
- Full cache strategy review: 1-2 hours

---

## 5. Certificate Management

### Pre-Conditions

- Inventory of all certificates (domains, issuers, locations)
- Access to DNS or web server for challenge verification
- Knowledge of where certs are deployed (load balancer, web server, CDN, application)

### Procedure

**Step 1: List All Certificates with Expiry**

```bash
# Check a specific domain
echo | openssl s_client -servername example.com -connect example.com:443 2>/dev/null \
    | openssl x509 -noout -dates -subject

# Check local certificate file
openssl x509 -in /etc/ssl/certs/myapp.crt -noout -dates -subject

# Check all certs in a directory
for cert in /etc/ssl/certs/*.crt; do
    expiry=$(openssl x509 -in "$cert" -noout -enddate 2>/dev/null | cut -d= -f2)
    echo "$cert: $expiry"
done
```

**Step 2: Renew Approaching Expiry (< 30 days)**

```bash
# Certbot (Let's Encrypt)
certbot renew --dry-run   # Test first
certbot renew             # Actual renewal

# Manual renewal (if not using automation)
certbot certonly --webroot -w /var/www/html -d example.com -d www.example.com
```

**Step 3: Verify Renewal**

```bash
# Check the new certificate
openssl x509 -in /etc/letsencrypt/live/example.com/fullchain.pem -noout -dates -subject

# Verify the chain is complete
openssl verify -CAfile /etc/ssl/certs/ca-certificates.crt \
    /etc/letsencrypt/live/example.com/fullchain.pem

# Test HTTPS connection
curl -vI https://example.com 2>&1 | grep -E "expire date|subject|issuer"
```

**Step 4: Distribute Updated Certificate**

```bash
# Nginx
sudo nginx -t && sudo systemctl reload nginx

# HAProxy
cat /etc/letsencrypt/live/example.com/{fullchain.pem,privkey.pem} > /etc/haproxy/certs/example.com.pem
sudo systemctl reload haproxy

# AWS ACM (managed certificates auto-renew, but verify)
aws acm describe-certificate --certificate-arn arn:aws:acm:... \
    --query 'Certificate.{Status:Status,NotAfter:NotAfter}'
```

### Verification

- [ ] SSL Labs test: A or A+ rating (https://www.ssllabs.com/ssltest/)
- [ ] No mixed content warnings on the site
- [ ] Certificate chain is complete (no intermediate cert warnings)
- [ ] All services using the cert have been reloaded
- [ ] HSTS header present if applicable

### Rollback

Keep the previous certificate files before renewal. If the new cert causes issues, restore the old files and reload the web server. Old certs remain valid until their original expiry.

### Estimated Time

- Automated renewal (certbot): 5 minutes
- Manual renewal and distribution: 30-60 minutes
- Full certificate audit: 1-2 hours

---

## 6. Cleanup Operations

### Pre-Conditions

- Understand what is safe to remove (never delete without understanding the contents)
- Backups current before aggressive cleanup
- Disk usage monitored so you can measure the impact

### Procedure

**Docker Cleanup**

```bash
# Check Docker disk usage
docker system df

# Remove stopped containers
docker container prune -f

# Remove dangling images (untagged, unreferenced)
docker image prune -f

# Remove unused images (not referenced by any container) -- more aggressive
docker image prune -a -f --filter "until=168h"  # Older than 7 days

# Remove unused networks
docker network prune -f

# Remove build cache
docker builder prune -f --filter "until=168h"

# DANGER: Remove unused volumes (may contain data!)
# Only run after confirming no persistent data in volumes
# docker volume prune -f
```

**File Cleanup**

```bash
# Temp directories
du -sh /tmp/ /var/tmp/
find /tmp -type f -mtime +7 -delete
find /var/tmp -type f -mtime +30 -delete

# Orphaned uploads (application-specific path)
find /app/uploads/tmp -type f -mtime +1 -delete

# Build artifacts
find /home -name "node_modules" -type d -prune -exec du -sh {} \;
# Selectively remove node_modules from inactive projects
# rm -rf /path/to/inactive-project/node_modules

# Package manager caches
npm cache clean --force
pip cache purge
```

**Git Cleanup**

```bash
# List merged branches (safe to delete)
git branch --merged main | grep -v "main\|master\|develop"

# Delete merged branches
git branch --merged main | grep -v "main\|master\|develop" | xargs git branch -d

# Prune remote tracking branches
git fetch --prune

# Check repository size
git count-objects -vH
```

### Verification

- [ ] Disk space freed matches expectations (`df -h` before and after)
- [ ] Applications still running correctly
- [ ] No missing files or broken references
- [ ] Docker containers that should be running are still running

### Rollback

File deletion is not reversible. For Docker images, they can be re-pulled. For application files, restore from backup.

### Estimated Time

- Docker cleanup: 10-15 minutes
- File cleanup: 15-30 minutes
- Git cleanup: 10 minutes
