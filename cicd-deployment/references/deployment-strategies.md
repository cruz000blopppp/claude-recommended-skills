# Deployment Strategies

A guide to choosing and implementing the right deployment strategy based on risk tolerance, team size, and infrastructure constraints.

---

## 1. Rolling Update

### How It Works

Instances are updated incrementally. Old instances are replaced with new ones a few at a time until all instances run the new version. At any point during the rollout, both old and new versions are serving traffic simultaneously.

### Implementation

```yaml
# Kubernetes rolling update
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  replicas: 4
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1        # At most 1 extra pod during update
      maxUnavailable: 0   # Never reduce below desired count
  template:
    spec:
      containers:
        - name: my-app
          image: my-app:v2.1.0
          readinessProbe:
            httpGet:
              path: /health
              port: 8080
            initialDelaySeconds: 5
            periodSeconds: 10
```

```yaml
# AWS ECS rolling update
resource "aws_ecs_service" "app" {
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }
}
```

### When to Use

- Stateless applications with backward-compatible changes
- Services that can tolerate mixed-version traffic during rollout
- Teams without complex traffic routing infrastructure

### Risks

- **Mixed-version state**: During rollout, both v1 and v2 serve traffic. API changes must be backward-compatible.
- **Slow rollback**: Rolling back requires another full rolling update in reverse.
- **Database migrations**: Schema changes must be compatible with both old and new code simultaneously.
- **Session affinity**: Users may hit different versions on consecutive requests unless sticky sessions are configured.

---

## 2. Blue-Green Deployment

### How It Works

Two identical environments (blue and green) run in parallel. One serves production traffic while the other is idle or serves as staging. Deploy the new version to the idle environment, run validation, then switch traffic all at once.

### Architecture

```
                    ┌──────────────┐
                    │  Load        │
                    │  Balancer    │
                    └──────┬───────┘
                           │
              ┌────────────┼────────────┐
              │            │            │
        ┌─────▼─────┐           ┌─────▼─────┐
        │  Blue      │           │  Green     │
        │  (v1.0)    │           │  (v2.0)    │
        │  ACTIVE    │           │  STANDBY   │
        └───────────┘           └────────────┘
```

Traffic switch is instantaneous:
1. Deploy v2.0 to green (standby)
2. Run smoke tests against green
3. Switch load balancer to point to green
4. Green becomes active, blue becomes standby
5. Keep blue running for quick rollback

### Implementation (Vercel-style)

Vercel and similar platforms implement blue-green natively:

```bash
# Deploy creates a new "green" environment with a preview URL
vercel deploy --prod

# Atomic switch -- the production URL points to the new deployment
# Rollback is instant -- point back to previous deployment
vercel rollback
```

### When to Use

- Applications where zero-downtime switching is critical
- When you need instant rollback capability
- Teams with budget for running two full environments

### Risks

- **Cost**: Two full environments running simultaneously doubles infrastructure cost during transition.
- **Database migrations**: The hardest part. Both environments share the same database. Migrations must be forward-compatible so the blue environment continues working after green's migration runs.
- **Stateful services**: In-memory sessions, WebSocket connections, and background jobs do not transfer during the switch.
- **DNS propagation**: If using DNS-based switching, propagation delay means some users hit the old environment for minutes. Use load balancer switching instead.

---

## 3. Canary Deployment

### How It Works

Route a small percentage of traffic to the new version. Monitor error rates, latency, and business metrics. Gradually increase the percentage if metrics look healthy. Roll back instantly if anomalies are detected.

### Traffic Progression

```
Time 0:   v1 [████████████████████] 100%    v2 [] 0%
Time 1:   v1 [███████████████████ ] 95%     v2 [█] 5%
Time 2:   v1 [████████████████    ] 80%     v2 [████] 20%
Time 3:   v1 [██████████          ] 50%     v2 [██████████] 50%
Time 4:   v1 [                    ] 0%      v2 [████████████████████] 100%
```

### Implementation (Kubernetes with Argo Rollouts)

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: my-app
spec:
  strategy:
    canary:
      steps:
        - setWeight: 5
        - pause: { duration: 5m }
        - analysis:
            templates:
              - templateName: error-rate-check
        - setWeight: 20
        - pause: { duration: 10m }
        - analysis:
            templates:
              - templateName: error-rate-check
        - setWeight: 50
        - pause: { duration: 10m }
        - setWeight: 100
      canaryService: my-app-canary
      stableService: my-app-stable
```

### Metrics to Watch

- **Error rate**: Compare canary error rate to baseline. Alert if > 1% above baseline.
- **Latency**: p50, p95, p99 response times. Alert on significant regression.
- **Saturation**: CPU, memory, connection pool usage on canary instances.
- **Business metrics**: Conversion rate, checkout completion, API success rate.

### Automated Rollback Triggers

```yaml
apiVersion: argoproj.io/v1alpha1
kind: AnalysisTemplate
metadata:
  name: error-rate-check
spec:
  metrics:
    - name: error-rate
      interval: 60s
      failureLimit: 3
      provider:
        prometheus:
          query: |
            sum(rate(http_requests_total{status=~"5.*", app="my-app-canary"}[5m]))
            /
            sum(rate(http_requests_total{app="my-app-canary"}[5m]))
      successCondition: result[0] < 0.01
```

### When to Use

- High-traffic applications where bugs affect many users
- When you have observability infrastructure (metrics, alerting)
- Risk-averse teams deploying to production frequently

### Risks

- **Requires observability**: Without good metrics, canary is just a slow rolling update.
- **Stateful routing**: Users may see inconsistent behavior if they hit canary on one request and stable on the next.
- **Small sample size**: At 5% traffic, low-traffic endpoints may not generate enough data for meaningful analysis.
- **Duration**: A full canary progression takes 30-60 minutes. Not suitable for urgent hotfixes.

---

## 4. Feature Flags

### How It Works

Deploy code with new features disabled behind runtime toggles. Enable features gradually per user segment, percentage, or environment. Decouple deployment from release -- deploy anytime, release when ready.

### Runtime Toggles vs Deploy-Time

| Aspect | Runtime Toggles | Deploy-Time (env vars) |
|--------|----------------|----------------------|
| Granularity | Per-user, percentage | All-or-nothing |
| Speed | Instant, no deploy | Requires deploy |
| Complexity | Higher (flag service) | Lower |
| Cost | Flag service subscription | Free |
| Cleanup | Must remove old flags | Simpler lifecycle |

### Implementation

```typescript
// Using a feature flag service (LaunchDarkly, Unleash, Flagsmith)
import { getFeatureFlag } from './feature-flags'

async function handleCheckout(request: Request): Promise<Response> {
  const useNewPaymentFlow = await getFeatureFlag(
    'new-payment-flow',
    { userId: request.userId, plan: request.plan }
  )

  if (useNewPaymentFlow) {
    return newPaymentHandler(request)
  }
  return legacyPaymentHandler(request)
}
```

### Flag Lifecycle Management

1. **Create**: Define flag with default off, document purpose and owner
2. **Develop**: Code behind flag, deploy to production (flag off)
3. **Test**: Enable for internal users, then beta users
4. **Release**: Gradually increase to 100%
5. **Clean up**: Remove flag and dead code path within 2 weeks of full rollout

Stale flags are technical debt. Track flag age and enforce cleanup.

### When to Use

- Long-running features that take multiple PRs to complete
- A/B testing and gradual rollouts
- Kill switches for risky features in production
- Different behavior per customer tier or region

### Risks

- **Flag debt**: Unreleased or forgotten flags accumulate. Audit regularly.
- **Testing complexity**: Every flag doubles the number of code paths. Test both states.
- **Consistency**: Ensure flag evaluation is deterministic per user (not random per request).
- **Performance**: Flag evaluation on every request adds latency. Cache flag values.

---

## 5. Preview Environments

### How It Works

Automatically deploy a temporary environment for each pull request. Reviewers can see and test changes in a production-like setting before merging. Environments are destroyed when the PR is closed.

### Implementation (GitHub Actions + Vercel)

```yaml
name: Preview Deploy

on:
  pull_request:
    types: [opened, synchronize, reopened]

jobs:
  deploy-preview:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Deploy to Vercel Preview
        id: deploy
        run: |
          DEPLOY_URL=$(vercel deploy --token=${{ secrets.VERCEL_TOKEN }})
          echo "url=$DEPLOY_URL" >> "$GITHUB_OUTPUT"

      - name: Comment PR with preview URL
        uses: actions/github-script@v7
        with:
          script: |
            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: `Preview deployed: ${{ steps.deploy.outputs.url }}`
            })
```

### Cleanup

```yaml
name: Cleanup Preview

on:
  pull_request:
    types: [closed]

jobs:
  cleanup:
    runs-on: ubuntu-latest
    steps:
      - name: Delete preview environment
        run: |
          vercel rm my-app-pr-${{ github.event.number }} \
            --token=${{ secrets.VERCEL_TOKEN }} \
            --yes
```

### Data Seeding

Preview environments need data to be useful. Options:
- **Seed scripts**: Populate with synthetic test data on creation
- **Database snapshots**: Clone a sanitized copy of staging data
- **Shared staging DB**: All previews share one database (simpler but less isolated)

### When to Use

- Teams with multiple in-flight PRs
- Frontend changes that benefit from visual review
- Features that require stakeholder sign-off before merge

### Risks

- **Cost**: Each preview is a running environment. Set auto-deletion timers.
- **Secrets**: Preview environments need access to services. Use dedicated preview credentials with limited scope.
- **Data isolation**: Shared databases between previews can cause test interference.
- **Stale previews**: PRs that sit open for weeks accumulate cost. Auto-delete after inactivity.

---

## 6. Serverless Deployment

### How It Works

Each deployment creates a new immutable version. Traffic is routed to the latest version. Previous versions remain available for instant rollback. No servers to manage -- the platform handles scaling.

### Implementation (AWS Lambda)

```yaml
# Serverless Framework
service: my-api

provider:
  name: aws
  runtime: nodejs20.x
  stage: ${opt:stage, 'dev'}

functions:
  api:
    handler: src/handler.main
    events:
      - httpApi:
          path: /{proxy+}
          method: ANY
    environment:
      DATABASE_URL: ${ssm:/my-api/${self:provider.stage}/database-url}
```

### Version Aliasing

```bash
# Publish a new version
aws lambda publish-version --function-name my-function

# Point the "production" alias to the new version
aws lambda update-alias \
  --function-name my-function \
  --name production \
  --function-version 42

# Rollback: point alias back to previous version
aws lambda update-alias \
  --function-name my-function \
  --name production \
  --function-version 41
```

### When to Use

- API endpoints, webhooks, scheduled jobs
- Applications with variable traffic patterns
- Teams that want to minimize operational overhead

### Risks

- **Cold starts**: First invocation after idle period is slow. Use provisioned concurrency for latency-sensitive endpoints.
- **Execution limits**: Timeout (15 min on Lambda), memory, payload size. Not suitable for long-running or large-payload workloads.
- **Vendor lock-in**: Platform-specific APIs and deployment tools. Abstract business logic from platform bindings.
- **Local testing**: Serverless functions behave differently locally. Use tools like `serverless-offline` or `sam local`.

---

## Decision Matrix

| Factor | Rolling | Blue-Green | Canary | Feature Flags | Preview | Serverless |
|--------|---------|------------|--------|---------------|---------|------------|
| **Rollback speed** | Slow | Instant | Fast | Instant | N/A | Instant |
| **Infrastructure cost** | Low | High | Medium | Low | Medium | Variable |
| **Complexity** | Low | Medium | High | Medium | Medium | Low |
| **Zero downtime** | Yes | Yes | Yes | Yes | N/A | Yes |
| **Observability needed** | Low | Low | High | Medium | Low | Medium |
| **Best for team size** | Any | Medium+ | Large | Any | Any | Small-Medium |
| **Risk tolerance** | Medium | Low | Very Low | Low | N/A | Low |
| **Database migrations** | Hard | Very Hard | Hard | Easy | Easy | Easy |

### Quick Selection Guide

- **Solo dev / small team, simple app**: Rolling update or serverless
- **Need instant rollback, budget available**: Blue-green
- **High traffic, need gradual rollout**: Canary
- **Long-running features, A/B testing**: Feature flags
- **PR review workflow improvement**: Preview environments
- **Event-driven / variable traffic**: Serverless
- **Most teams, most of the time**: Start with rolling, add canary or feature flags as you grow
