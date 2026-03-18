# Rollback Procedures

Structured procedures for rolling back deployments across platforms. When something goes wrong in production, speed and clarity matter. Follow these procedures to minimize downtime and user impact.

---

## 1. General Rollback Protocol

### Decision Criteria

Initiate a rollback when any of these conditions are met:

- **Error rate spike**: 5xx error rate exceeds 1% of total requests (or 2x baseline)
- **Latency degradation**: p95 response time exceeds 2x the pre-deploy baseline
- **Health check failure**: More than 50% of instances failing health checks
- **Critical functionality broken**: Core user flows (login, checkout, data access) are non-functional
- **Data integrity risk**: Evidence of data corruption or inconsistent writes

Do NOT rollback for:
- Minor UI issues that do not affect functionality
- Performance degradation within acceptable thresholds
- Issues isolated to a single non-critical endpoint

### Communication

1. **Announce** in the incident channel: "Rolling back [service] from v2.1.0 to v2.0.0 due to [brief reason]"
2. **Assign roles**: One person executes the rollback, one person monitors metrics
3. **Update status page** if user-facing impact is occurring
4. **Post-rollback**: Confirm success in the incident channel with metrics evidence

### Execution Sequence

```
1. DECIDE    → Confirm rollback is the right action (not a hotfix)
2. ANNOUNCE  → Notify team in incident channel
3. EXECUTE   → Run the platform-specific rollback procedure
4. VERIFY    → Confirm services are healthy (health checks, smoke tests)
5. MONITOR   → Watch metrics for 15 minutes post-rollback
6. DOCUMENT  → Create incident ticket with timeline and root cause
```

### Verification Checklist

After every rollback, confirm:

- [ ] Health check endpoints return 200
- [ ] Error rate has returned to pre-deploy baseline
- [ ] Latency has returned to pre-deploy baseline
- [ ] Core user flows work (manual smoke test or automated)
- [ ] No data integrity issues (check recent writes)
- [ ] Background jobs and queues are processing normally
- [ ] External integrations are functional (webhooks, API partners)

---

## 2. Platform-Specific Rollbacks

### Vercel

Vercel deployments are immutable. Every deploy creates a new deployment with a unique URL. Rollback is instantaneous.

```bash
# List recent deployments
vercel ls --limit 10

# Rollback to previous production deployment via CLI
vercel rollback

# Rollback to a specific deployment
vercel rollback <deployment-url-or-id>

# Via dashboard:
# 1. Go to project > Deployments
# 2. Find the last known good deployment
# 3. Click "..." > "Promote to Production"
```

**Domain reassignment**: When you rollback, Vercel reassigns the production domain to the previous deployment. This is atomic -- there is no gap in service.

**Edge cases**:
- Environment variables changed between deploys: rollback restores the code but keeps current env vars. If the old code depends on old env vars, update them manually.
- Serverless function cold starts may occur immediately after rollback.

### AWS ECS (Fargate / EC2)

ECS uses task definitions with revision numbers. Rollback by updating the service to use a previous revision.

```bash
# List recent task definition revisions
aws ecs list-task-definitions \
  --family-prefix my-app \
  --sort DESC \
  --max-items 5

# Update service to use previous task definition revision
aws ecs update-service \
  --cluster my-cluster \
  --service my-service \
  --task-definition my-app:41 \
  --force-new-deployment

# Monitor rollback progress
aws ecs wait services-stable \
  --cluster my-cluster \
  --services my-service

# Verify
aws ecs describe-services \
  --cluster my-cluster \
  --services my-service \
  --query 'services[0].deployments'
```

**Circuit breaker**: If enabled, ECS automatically rolls back when new tasks fail health checks:

```json
{
  "deploymentCircuitBreaker": {
    "enable": true,
    "rollback": true
  }
}
```

**Gotchas**:
- Rolling updates take time (minutes). `--force-new-deployment` accelerates by draining old tasks faster.
- If the task definition references a Docker image tag (like `latest`), ensure the ECR image at that tag has not been overwritten. Use immutable tags.

### AWS Lambda

Lambda versions are immutable. Rollback by updating the alias to point to a previous version.

```bash
# List recent versions
aws lambda list-versions-by-function \
  --function-name my-function \
  --max-items 5

# Get current alias configuration
aws lambda get-alias \
  --function-name my-function \
  --name production

# Rollback: point alias to previous version
aws lambda update-alias \
  --function-name my-function \
  --name production \
  --function-version 41

# Verify
aws lambda invoke \
  --function-name my-function:production \
  --payload '{"test": true}' \
  response.json
```

**Instant**: Alias updates take effect immediately. No rolling update period.

**Gotchas**:
- If the function reads config from SSM Parameter Store or Secrets Manager, and those values changed, the old code version may not work with current config values.
- Provisioned concurrency is tied to the alias, not the version. No reconfiguration needed.

### Kubernetes

Kubernetes tracks deployment revision history. Use `kubectl rollout undo` to revert.

```bash
# Check rollout status
kubectl rollout status deployment/my-app -n production

# View revision history
kubectl rollout history deployment/my-app -n production

# View details of a specific revision
kubectl rollout history deployment/my-app -n production --revision=3

# Rollback to previous revision
kubectl rollout undo deployment/my-app -n production

# Rollback to a specific revision
kubectl rollout undo deployment/my-app -n production --to-revision=3

# Monitor rollback
kubectl rollout status deployment/my-app -n production

# Verify pods are healthy
kubectl get pods -n production -l app=my-app
```

**Revision history**: Kubernetes keeps 10 revisions by default (configurable via `spec.revisionHistoryLimit`). Increase this if you need deeper rollback capability.

**Gotchas**:
- `kubectl rollout undo` only reverts the pod template (image, env vars, resource limits). It does not revert ConfigMaps, Secrets, or other resources.
- If you use Helm, prefer `helm rollback` as it reverts the entire release (including ConfigMaps and Services), not just the Deployment.
- Rollback triggers a new rolling update, which takes time proportional to replica count.

```bash
# Helm rollback
helm history my-app -n production
helm rollback my-app 3 -n production
```

### Docker Compose

For self-hosted applications using Docker Compose, rollback by reverting to the previous image tag.

```bash
# Check current running containers
docker compose ps

# Edit docker-compose.yml to use previous image tag
# image: my-app:v2.1.0  →  image: my-app:v2.0.0

# Pull the previous image and restart
docker compose pull my-app
docker compose up -d my-app

# Verify
docker compose ps
docker compose logs --tail=50 my-app
```

**Volume considerations**:
- Named volumes persist across container restarts. If the new version modified volume data (e.g., file uploads directory structure), reverting the image does not revert volume contents.
- Database volumes: if the new version ran a migration that altered the schema, reverting the app image may cause schema mismatches. See the database section below.

**Quick rollback with image digests**:

```bash
# Use digest instead of tag for guaranteed immutability
docker compose pull my-app@sha256:abc123...
docker compose up -d my-app
```

### Database Rollback

Database rollbacks are the most dangerous type. Approach with extreme caution.

#### Schema-Only Rollback

If the migration only added columns/tables and no data was written to them:

```bash
# Using a migration tool (e.g., Prisma, Knex, Flyway)
npx prisma migrate resolve --rolled-back 20240315_add_payments_table

# Or run a down migration
npx knex migrate:rollback --specific 20240315_add_payments_table.js
```

#### Data + Schema Rollback

If the migration modified existing data:

1. **Restore from backup** (safest):
   ```bash
   # Point-in-time recovery (AWS RDS)
   aws rds restore-db-instance-to-point-in-time \
     --source-db-instance-identifier my-db \
     --target-db-instance-identifier my-db-restored \
     --restore-time "2024-03-15T10:30:00Z"
   ```

2. **Forward-fix** (often faster):
   Write a new migration that reverses the data changes. This is usually safer than restoring a backup because it does not lose data written after the bad migration.

#### When Database Rollback Is Not Possible

See section 4 below for cases where rolling back is not the right approach.

---

## 3. Post-Rollback Checklist

Complete this checklist after every rollback, regardless of platform:

### Immediate (within 15 minutes)

- [ ] **Services healthy**: All health checks passing
- [ ] **Error rate normalized**: Back to pre-deploy baseline
- [ ] **Latency normalized**: p50, p95, p99 back to baseline
- [ ] **Core flows functional**: Login, primary user actions, API responses
- [ ] **Data integrity verified**: Spot-check recent records for consistency
- [ ] **Background jobs running**: Queue consumers processing, cron jobs executing
- [ ] **External integrations working**: Webhooks, third-party APIs, partner feeds

### Short-term (within 1 hour)

- [ ] **Status page updated**: Communicate resolution to affected users
- [ ] **Incident channel updated**: Post "all clear" with metrics evidence
- [ ] **Incident ticket created**: Include timeline, impact scope, root cause hypothesis
- [ ] **Failed deployment tagged**: Mark the bad release in your release tracker
- [ ] **CI pipeline updated**: Block re-deploy of the broken version

### Follow-up (within 24 hours)

- [ ] **Root cause analysis**: Identify why the issue was not caught pre-deploy
- [ ] **Post-mortem scheduled**: If impact was significant (> 5 min downtime or > 1% users)
- [ ] **Test gap identified**: Add tests that would have caught this issue
- [ ] **Pipeline improvement**: Add quality gate that would have prevented this deploy
- [ ] **Runbook updated**: Document any new failure modes discovered

### Stakeholder Notification Template

```
Subject: [RESOLVED] Deployment rollback for [service name]

Timeline:
- [HH:MM] Deployed v2.1.0 to production
- [HH:MM] Detected elevated error rates (X% → Y%)
- [HH:MM] Initiated rollback to v2.0.0
- [HH:MM] Rollback complete, services healthy

Impact:
- Duration: X minutes
- Affected users: approximately N
- Data impact: None / [describe]

Root cause: [Brief description]
Next steps: [Post-mortem date, fix timeline]
```

---

## 4. When NOT to Rollback

Sometimes rolling back makes things worse. Recognize these situations and choose a forward-fix instead.

### Forward-Only Database Migrations

If the migration:
- **Dropped a column or table**: The data is gone. Rolling back the app code will cause errors on the missing column. Fix forward by re-adding the column and restoring from backup.
- **Renamed a column**: Both old and new code reference different column names. Fix forward by adding an alias or updating the code.
- **Changed data types**: Existing data was converted. Reverting the schema may lose precision or fail entirely.

**Rule of thumb**: If the migration is destructive (DROP, RENAME, ALTER TYPE), you must fix forward.

### Breaking API Changes Already Consumed

If external clients (mobile apps, partner integrations) have already adapted to the new API:
- Rolling back the API breaks those clients
- Use API versioning and maintain both versions temporarily
- Deprecate the old version with a sunset timeline

### Published Artifacts

If the deployment published artifacts consumed by others:
- **npm packages**: Published versions cannot be unpublished after 72 hours. Publish a patch version with the fix.
- **Mobile app releases**: App store releases cannot be "un-released." Push a hotfix update.
- **Public API changes**: Clients may have already integrated. Maintain backward compatibility.

### Irreversible Side Effects

If the deployment triggered actions that cannot be undone:
- Sent emails or push notifications
- Charged credit cards or processed payments
- Created records in external systems (CRM, analytics, compliance)

In these cases, the rollback only prevents further damage. The already-executed side effects require separate remediation (refunds, correction emails, manual data fixes).

### The "Fix Forward" Decision

Choose fix forward when:
1. The fix is simple and well-understood (< 30 minutes to implement and deploy)
2. The rollback would cause more disruption than the current issue
3. The current issue affects a small percentage of users
4. Data changes make rollback dangerous

Choose rollback when:
1. The fix is complex or uncertain
2. The issue affects a large percentage of users
3. Data integrity is at risk and getting worse over time
4. The deployment is recent and no irreversible side effects have occurred
