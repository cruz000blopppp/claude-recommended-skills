# Query Patterns for Data Investigation

Reusable query templates for common data analysis tasks. All examples use PostgreSQL syntax. MySQL differences are noted where relevant.

## 1. Aggregation & Grouping

Use aggregation to summarize large datasets into actionable numbers.

### Basic Aggregation

```sql
-- Count, sum, and average with grouping
SELECT
    status,
    COUNT(*) AS total_count,
    SUM(amount) AS total_amount,
    AVG(amount) AS avg_amount,
    MIN(amount) AS min_amount,
    MAX(amount) AS max_amount
FROM orders
WHERE created_at >= NOW() - INTERVAL '7 days'
GROUP BY status
ORDER BY total_count DESC;
```

### Filtering Groups with HAVING

```sql
-- Find customers with more than 10 failed orders
SELECT
    customer_id,
    COUNT(*) AS failed_count,
    MAX(created_at) AS last_failure
FROM orders
WHERE status = 'failed'
    AND created_at >= NOW() - INTERVAL '30 days'
GROUP BY customer_id
HAVING COUNT(*) > 10
ORDER BY failed_count DESC
LIMIT 20;
```

### Multiple Dimensions

```sql
-- Error rates by endpoint and status code
SELECT
    endpoint,
    status_code,
    COUNT(*) AS request_count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (PARTITION BY endpoint), 2) AS pct_of_endpoint
FROM http_requests
WHERE created_at >= NOW() - INTERVAL '1 hour'
GROUP BY endpoint, status_code
ORDER BY endpoint, request_count DESC;
```

**When to use each aggregate:**
- `COUNT(*)` — total rows, including nulls
- `COUNT(column)` — non-null values only
- `COUNT(DISTINCT column)` — unique values
- `SUM` / `AVG` — numeric totals and averages (watch for null skew in AVG)
- `PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY value)` — percentile calculations

## 2. Time-Series Analysis

### Bucketing by Time Period

```sql
-- Request count per hour for the last 24 hours
SELECT
    date_trunc('hour', created_at) AS hour_bucket,
    COUNT(*) AS request_count,
    COUNT(*) FILTER (WHERE status_code >= 500) AS error_count,
    ROUND(
        COUNT(*) FILTER (WHERE status_code >= 500) * 100.0 / NULLIF(COUNT(*), 0),
        2
    ) AS error_rate_pct
FROM http_requests
WHERE created_at >= NOW() - INTERVAL '24 hours'
GROUP BY hour_bucket
ORDER BY hour_bucket;
```

**MySQL equivalent:** Use `DATE_FORMAT` instead of `date_trunc`:
```sql
DATE_FORMAT(created_at, '%Y-%m-%d %H:00:00') AS hour_bucket
```

### Moving Averages

```sql
-- 7-day moving average of daily revenue
WITH daily_revenue AS (
    SELECT
        date_trunc('day', created_at)::date AS day,
        SUM(amount) AS revenue
    FROM orders
    WHERE status = 'completed'
        AND created_at >= NOW() - INTERVAL '30 days'
    GROUP BY day
)
SELECT
    day,
    revenue,
    ROUND(AVG(revenue) OVER (
        ORDER BY day
        ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ), 2) AS moving_avg_7d
FROM daily_revenue
ORDER BY day;
```

### Year-over-Year Comparison

```sql
-- Compare this week's metrics to the same week last year
WITH current_period AS (
    SELECT
        date_trunc('day', created_at)::date AS day,
        COUNT(*) AS orders,
        SUM(amount) AS revenue
    FROM orders
    WHERE created_at >= date_trunc('week', NOW())
        AND created_at < date_trunc('week', NOW()) + INTERVAL '7 days'
    GROUP BY day
),
prior_year AS (
    SELECT
        date_trunc('day', created_at)::date AS day,
        COUNT(*) AS orders,
        SUM(amount) AS revenue
    FROM orders
    WHERE created_at >= date_trunc('week', NOW()) - INTERVAL '1 year'
        AND created_at < date_trunc('week', NOW()) - INTERVAL '1 year' + INTERVAL '7 days'
    GROUP BY day
)
SELECT
    c.day AS current_day,
    c.orders AS current_orders,
    p.orders AS prior_year_orders,
    ROUND((c.orders - p.orders) * 100.0 / NULLIF(p.orders, 0), 1) AS orders_change_pct,
    c.revenue AS current_revenue,
    p.revenue AS prior_year_revenue
FROM current_period c
LEFT JOIN prior_year p
    ON EXTRACT(DOW FROM c.day) = EXTRACT(DOW FROM p.day)
ORDER BY c.day;
```

### Gap Detection

```sql
-- Find missing hours in time-series data (gaps in reporting)
WITH expected_hours AS (
    SELECT generate_series(
        date_trunc('hour', NOW() - INTERVAL '24 hours'),
        date_trunc('hour', NOW()),
        '1 hour'::interval
    ) AS hour_bucket
),
actual_hours AS (
    SELECT DISTINCT date_trunc('hour', created_at) AS hour_bucket
    FROM events
    WHERE created_at >= NOW() - INTERVAL '24 hours'
)
SELECT e.hour_bucket AS missing_hour
FROM expected_hours e
LEFT JOIN actual_hours a ON e.hour_bucket = a.hour_bucket
WHERE a.hour_bucket IS NULL
ORDER BY e.hour_bucket;
```

## 3. Anomaly Detection

### Comparing to Baseline with Standard Deviation

```sql
-- Find hours with error rates more than 2 standard deviations above the mean
WITH hourly_errors AS (
    SELECT
        date_trunc('hour', created_at) AS hour_bucket,
        COUNT(*) FILTER (WHERE status_code >= 500) * 100.0 / COUNT(*) AS error_rate
    FROM http_requests
    WHERE created_at >= NOW() - INTERVAL '7 days'
    GROUP BY hour_bucket
),
baseline AS (
    SELECT
        AVG(error_rate) AS mean_rate,
        STDDEV(error_rate) AS stddev_rate
    FROM hourly_errors
)
SELECT
    h.hour_bucket,
    ROUND(h.error_rate, 2) AS error_rate,
    ROUND(b.mean_rate, 2) AS baseline_mean,
    ROUND((h.error_rate - b.mean_rate) / NULLIF(b.stddev_rate, 0), 2) AS z_score
FROM hourly_errors h
CROSS JOIN baseline b
WHERE h.error_rate > b.mean_rate + (2 * b.stddev_rate)
ORDER BY h.hour_bucket DESC;
```

### Spike and Drop Detection

```sql
-- Detect >50% changes between consecutive periods
WITH hourly_counts AS (
    SELECT
        date_trunc('hour', created_at) AS hour_bucket,
        COUNT(*) AS event_count
    FROM events
    WHERE created_at >= NOW() - INTERVAL '48 hours'
    GROUP BY hour_bucket
)
SELECT
    hour_bucket,
    event_count,
    LAG(event_count) OVER (ORDER BY hour_bucket) AS prev_count,
    ROUND(
        (event_count - LAG(event_count) OVER (ORDER BY hour_bucket)) * 100.0
        / NULLIF(LAG(event_count) OVER (ORDER BY hour_bucket), 0),
        1
    ) AS pct_change
FROM hourly_counts
ORDER BY hour_bucket DESC
LIMIT 48;
```

### Percentile Analysis

```sql
-- Response time percentiles by endpoint
SELECT
    endpoint,
    COUNT(*) AS total_requests,
    ROUND(PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY response_time_ms)::numeric, 1) AS p50,
    ROUND(PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY response_time_ms)::numeric, 1) AS p90,
    ROUND(PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY response_time_ms)::numeric, 1) AS p95,
    ROUND(PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY response_time_ms)::numeric, 1) AS p99
FROM http_requests
WHERE created_at >= NOW() - INTERVAL '1 hour'
GROUP BY endpoint
HAVING COUNT(*) >= 100
ORDER BY p95 DESC
LIMIT 20;
```

**MySQL equivalent:** MySQL lacks `PERCENTILE_CONT`. Use `PERCENT_RANK` with subqueries or approximate with sorted LIMIT offsets.

## 4. Top-N Analysis

### Simple Top-N

```sql
-- Top 10 customers by revenue this month
SELECT
    customer_id,
    COUNT(*) AS order_count,
    SUM(amount) AS total_revenue,
    AVG(amount) AS avg_order_value
FROM orders
WHERE status = 'completed'
    AND created_at >= date_trunc('month', NOW())
GROUP BY customer_id
ORDER BY total_revenue DESC
LIMIT 10;
```

### Partitioned Top-N with Window Functions

```sql
-- Top 3 products per category by sales
WITH ranked AS (
    SELECT
        p.category,
        p.name AS product_name,
        SUM(oi.quantity) AS units_sold,
        SUM(oi.quantity * oi.unit_price) AS revenue,
        ROW_NUMBER() OVER (
            PARTITION BY p.category
            ORDER BY SUM(oi.quantity * oi.unit_price) DESC
        ) AS rank_in_category
    FROM order_items oi
    JOIN products p ON oi.product_id = p.id
    WHERE oi.created_at >= NOW() - INTERVAL '30 days'
    GROUP BY p.category, p.name
)
SELECT category, product_name, units_sold, revenue, rank_in_category
FROM ranked
WHERE rank_in_category <= 3
ORDER BY category, rank_in_category;
```

### Top Contributors to a Total

```sql
-- Which error types account for 80% of all errors?
WITH error_counts AS (
    SELECT
        error_type,
        COUNT(*) AS error_count
    FROM application_errors
    WHERE created_at >= NOW() - INTERVAL '24 hours'
    GROUP BY error_type
),
running_total AS (
    SELECT
        error_type,
        error_count,
        SUM(error_count) OVER (ORDER BY error_count DESC) AS cumulative_count,
        SUM(error_count) OVER () AS total_count
    FROM error_counts
)
SELECT
    error_type,
    error_count,
    ROUND(error_count * 100.0 / total_count, 1) AS pct_of_total,
    ROUND(cumulative_count * 100.0 / total_count, 1) AS cumulative_pct
FROM running_total
WHERE cumulative_count - error_count < total_count * 0.8
ORDER BY error_count DESC;
```

## 5. Funnel Analysis

### Multi-Step Conversion Tracking

```sql
-- User signup funnel: landing -> signup form -> email verify -> first purchase
WITH funnel AS (
    SELECT
        date_trunc('day', e.created_at)::date AS day,
        COUNT(DISTINCT e.user_id) FILTER (
            WHERE e.event_type = 'page_view' AND e.page = '/landing'
        ) AS step1_landing,
        COUNT(DISTINCT e.user_id) FILTER (
            WHERE e.event_type = 'form_submit' AND e.page = '/signup'
        ) AS step2_signup,
        COUNT(DISTINCT e.user_id) FILTER (
            WHERE e.event_type = 'email_verified'
        ) AS step3_verified,
        COUNT(DISTINCT e.user_id) FILTER (
            WHERE e.event_type = 'purchase'
        ) AS step4_purchase
    FROM events e
    WHERE e.created_at >= NOW() - INTERVAL '7 days'
    GROUP BY day
)
SELECT
    day,
    step1_landing,
    step2_signup,
    ROUND(step2_signup * 100.0 / NULLIF(step1_landing, 0), 1) AS signup_rate,
    step3_verified,
    ROUND(step3_verified * 100.0 / NULLIF(step2_signup, 0), 1) AS verify_rate,
    step4_purchase,
    ROUND(step4_purchase * 100.0 / NULLIF(step3_verified, 0), 1) AS purchase_rate,
    ROUND(step4_purchase * 100.0 / NULLIF(step1_landing, 0), 1) AS overall_conversion
FROM funnel
ORDER BY day;
```

### Sequential Funnel (Ordered Steps)

```sql
-- Users who completed steps in order within a session
WITH ordered_events AS (
    SELECT
        session_id,
        user_id,
        event_type,
        created_at,
        ROW_NUMBER() OVER (PARTITION BY session_id ORDER BY created_at) AS step_order
    FROM events
    WHERE created_at >= NOW() - INTERVAL '7 days'
        AND event_type IN ('view_product', 'add_to_cart', 'begin_checkout', 'purchase')
)
SELECT
    COUNT(DISTINCT session_id) FILTER (
        WHERE event_type = 'view_product'
    ) AS viewed,
    COUNT(DISTINCT session_id) FILTER (
        WHERE event_type = 'add_to_cart'
    ) AS added_to_cart,
    COUNT(DISTINCT session_id) FILTER (
        WHERE event_type = 'begin_checkout'
    ) AS began_checkout,
    COUNT(DISTINCT session_id) FILTER (
        WHERE event_type = 'purchase'
    ) AS purchased
FROM ordered_events;
```

## 6. Join Patterns

### INNER JOIN — Matching Records Only

```sql
-- Orders with their customer details (only orders with valid customers)
SELECT o.id, o.amount, c.name, c.email
FROM orders o
INNER JOIN customers c ON o.customer_id = c.id
WHERE o.created_at >= NOW() - INTERVAL '24 hours'
LIMIT 20;
```

Use INNER JOIN when you only want rows that have matches in both tables.

### LEFT JOIN — Preserve All Left-Side Rows

```sql
-- All customers and their order counts (including those with zero orders)
SELECT
    c.id,
    c.name,
    COUNT(o.id) AS order_count,
    COALESCE(SUM(o.amount), 0) AS total_spent
FROM customers c
LEFT JOIN orders o ON c.id = o.customer_id
    AND o.created_at >= NOW() - INTERVAL '90 days'
GROUP BY c.id, c.name
ORDER BY order_count ASC
LIMIT 20;
```

Use LEFT JOIN when you need all rows from the left table regardless of matches.

### LATERAL JOIN — Correlated Subqueries

```sql
-- Latest 3 orders per customer (efficient alternative to window functions)
SELECT c.id, c.name, recent.id AS order_id, recent.amount, recent.created_at
FROM customers c
CROSS JOIN LATERAL (
    SELECT o.id, o.amount, o.created_at
    FROM orders o
    WHERE o.customer_id = c.id
    ORDER BY o.created_at DESC
    LIMIT 3
) recent
WHERE c.created_at >= NOW() - INTERVAL '30 days'
LIMIT 50;
```

Use LATERAL when you need to reference outer query columns in a subquery with LIMIT. Not supported in MySQL (use correlated subqueries or window functions instead).

### Performance Implications

- **INNER JOIN**: Generally fastest; optimizer can choose join order freely
- **LEFT JOIN**: Cannot be reordered as freely; ensure the smaller table drives the join
- **LATERAL JOIN**: Executes subquery per outer row; ensure the inner query uses indexes
- **Always check**: join columns should be indexed on both sides
- **Watch for**: N+1 joins that multiply row counts unexpectedly

## 7. Safe Defaults

Apply these to every query, especially in production environments.

### Always Include LIMIT

```sql
-- Exploratory queries: always limit
SELECT * FROM large_table LIMIT 10;

-- Even with aggregation, limit group cardinality awareness
SELECT status, COUNT(*) FROM orders GROUP BY status;
-- Safe because status has bounded cardinality
```

### Use EXPLAIN Before Executing

```sql
-- Check query plan before running on production
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT ...
```

Look for:
- **Seq Scan** on large tables (missing index)
- **Nested Loop** with high row estimates (potential cartesian product)
- **Sort** with high memory usage (add index or LIMIT)

### Set Statement Timeout

```sql
-- PostgreSQL: per-session timeout
SET statement_timeout = '30s';

-- PostgreSQL: per-transaction timeout
SET LOCAL statement_timeout = '10s';
```

**MySQL equivalent:**
```sql
SET SESSION MAX_EXECUTION_TIME = 30000;  -- milliseconds
```

### Use Read Replicas

For analytics and investigation queries, always prefer read replicas over the primary database. This prevents analytical queries from competing with production writes for resources.

### Transaction Safety

```sql
-- Wrap read queries in read-only transactions for safety
BEGIN READ ONLY;
SELECT ...;
COMMIT;
```

This ensures no accidental writes can occur, even if a query is copy-pasted incorrectly.
