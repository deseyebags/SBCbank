-- SBCbank Compliance Dashboard SQL Pack (PostgreSQL)
--
-- Purpose:
--   Starter SQL queries for a compliance-oriented dashboard aligned to
--   MAS TRM / PDPA-style controls and your current local data model.
--
-- Current tables used:
--   accounts, payments, orchestration_executions, ledger, statements
--
-- Notes:
--   1) Run each query separately in Metabase as its own Question/Card.
--   2) Thresholds (high-value amount, velocity rules) are intentionally
--      configurable via CTE "settings" blocks.
--   3) Cloud-security metrics (IAM/MFA/encryption/public exposure) require
--      external AWS feeds not present in this local transactional database.

/* -------------------------------------------------------------------------
   Query 01: Compliance KPI Snapshot (Last 30 Days)
   Why: Executive summary of reliability + fraud-proxy + audit signals.
--------------------------------------------------------------------------- */
WITH settings AS (
  SELECT
    10000.0::double precision AS high_value_threshold,
    NOW() - INTERVAL '30 days' AS window_start
),
payment_window AS (
  SELECT p.*
  FROM payments p
  CROSS JOIN settings s
  WHERE p.created_at >= s.window_start
),
workflow_window AS (
  SELECT o.*
  FROM orchestration_executions o
  CROSS JOIN settings s
  WHERE o.created_at >= s.window_start
)
SELECT
  (SELECT COUNT(*) FROM payment_window) AS total_payments_30d,
  ROUND(
    100.0 * (SELECT COUNT(*) FROM payment_window WHERE UPPER(status) = 'SUCCESS')
    / NULLIF((SELECT COUNT(*) FROM payment_window), 0),
    2
  ) AS payment_success_rate_pct_30d,
  (SELECT COUNT(*) FROM payment_window WHERE UPPER(status) = 'FAILED') AS failed_payments_30d,
  (SELECT COUNT(*) FROM payment_window pw CROSS JOIN settings s WHERE pw.amount >= s.high_value_threshold) AS high_value_payments_30d,
  ROUND((SELECT COALESCE(AVG(amount), 0.0) FROM payment_window)::numeric, 2) AS avg_payment_amount_30d,
  (SELECT COUNT(*) FROM workflow_window WHERE UPPER(status) = 'FAILED') AS failed_workflows_30d,
  (SELECT COUNT(*) FROM workflow_window WHERE UPPER(status) = 'RUNNING') AS running_workflows_30d;


/* -------------------------------------------------------------------------
   Query 02: Daily Payment Success / Failure Trend (Last 30 Days)
   Why: Monitors operational stability and incident patterns.
--------------------------------------------------------------------------- */
SELECT
  DATE(created_at) AS day,
  COUNT(*) AS total_payments,
  SUM(CASE WHEN UPPER(status) = 'SUCCESS' THEN 1 ELSE 0 END) AS success_count,
  SUM(CASE WHEN UPPER(status) = 'FAILED' THEN 1 ELSE 0 END) AS failed_count,
  ROUND(
    100.0 * SUM(CASE WHEN UPPER(status) = 'FAILED' THEN 1 ELSE 0 END)
    / NULLIF(COUNT(*), 0),
    2
  ) AS failure_rate_pct
FROM payments
WHERE created_at >= NOW() - INTERVAL '30 days'
GROUP BY DATE(created_at)
ORDER BY day;


/* -------------------------------------------------------------------------
   Query 03: Workflow Reliability by Day (Last 30 Days)
   Why: Tracks orchestration control effectiveness and run outcomes.
--------------------------------------------------------------------------- */
SELECT
  DATE(created_at) AS day,
  COUNT(*) AS total_workflows,
  SUM(CASE WHEN UPPER(status) = 'COMPLETED' THEN 1 ELSE 0 END) AS completed_count,
  SUM(CASE WHEN UPPER(status) = 'FAILED' THEN 1 ELSE 0 END) AS failed_count,
  SUM(CASE WHEN UPPER(status) = 'RUNNING' THEN 1 ELSE 0 END) AS running_count,
  ROUND(
    100.0 * SUM(CASE WHEN UPPER(status) = 'FAILED' THEN 1 ELSE 0 END)
    / NULLIF(COUNT(*), 0),
    2
  ) AS workflow_failure_rate_pct
FROM orchestration_executions
WHERE created_at >= NOW() - INTERVAL '30 days'
GROUP BY DATE(created_at)
ORDER BY day;


/* -------------------------------------------------------------------------
   Query 04: Workflow Latency SLA (Completed Runs, Last 30 Days)
   Why: Supports availability/performance objective tracking.
--------------------------------------------------------------------------- */
WITH durations AS (
  SELECT
    EXTRACT(EPOCH FROM (completed_at - created_at)) AS duration_seconds
  FROM orchestration_executions
  WHERE completed_at IS NOT NULL
    AND created_at >= NOW() - INTERVAL '30 days'
)
SELECT
  COUNT(*) AS completed_runs_30d,
  ROUND(COALESCE(AVG(duration_seconds), 0)::numeric, 2) AS avg_duration_seconds,
  ROUND(COALESCE(PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY duration_seconds), 0)::numeric, 2) AS p95_duration_seconds,
  ROUND(COALESCE(PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY duration_seconds), 0)::numeric, 2) AS p99_duration_seconds
FROM durations;


/* -------------------------------------------------------------------------
   Query 05: Long-Running Orchestrations (Potential Control Breach)
   Why: Flags stuck workflows that may violate operational controls.
--------------------------------------------------------------------------- */
SELECT
  execution_id,
  payment_id,
  status,
  retry_count,
  created_at,
  NOW() - created_at AS running_for
FROM orchestration_executions
WHERE UPPER(status) = 'RUNNING'
  AND created_at <= NOW() - INTERVAL '10 minutes'
ORDER BY created_at ASC;


/* -------------------------------------------------------------------------
   Query 06: Error Hotspots and Retry Pressure (Last 30 Days)
   Why: Identifies recurring failure classes for remediation.
--------------------------------------------------------------------------- */
SELECT
  COALESCE(NULLIF(TRIM(error_message), ''), 'UNSPECIFIED_ERROR') AS error_class,
  COUNT(*) AS occurrences,
  ROUND(AVG(retry_count)::numeric, 2) AS avg_retry_count,
  MAX(created_at) AS latest_occurrence
FROM orchestration_executions
WHERE created_at >= NOW() - INTERVAL '30 days'
  AND UPPER(status) = 'FAILED'
GROUP BY COALESCE(NULLIF(TRIM(error_message), ''), 'UNSPECIFIED_ERROR')
ORDER BY occurrences DESC, latest_occurrence DESC;


/* -------------------------------------------------------------------------
   Query 07: High-Value Transfers (Fraud Proxy, Last 30 Days)
   Why: Surfaces transactions requiring enhanced scrutiny.
--------------------------------------------------------------------------- */
WITH settings AS (
  SELECT 10000.0::double precision AS high_value_threshold
)
SELECT
  p.id AS payment_id,
  p.account_id AS payer_account_id,
  p.recipient_account_id,
  p.amount,
  p.status,
  p.created_at,
  p.execution_id
FROM payments p
CROSS JOIN settings s
WHERE p.created_at >= NOW() - INTERVAL '30 days'
  AND p.amount >= s.high_value_threshold
ORDER BY p.amount DESC, p.created_at DESC;


/* -------------------------------------------------------------------------
   Query 08: Velocity Rule Breach (Fraud Proxy, Last 24 Hours)
   Why: Detects unusual payment frequency by payer account.
--------------------------------------------------------------------------- */
WITH settings AS (
  SELECT 5::int AS min_payment_count_24h
)
SELECT
  p.account_id AS payer_account_id,
  COUNT(*) AS payments_24h,
  ROUND(SUM(p.amount)::numeric, 2) AS total_amount_24h,
  MIN(p.created_at) AS first_payment_at,
  MAX(p.created_at) AS last_payment_at
FROM payments p
CROSS JOIN settings s
WHERE p.created_at >= NOW() - INTERVAL '24 hours'
GROUP BY p.account_id, s.min_payment_count_24h
HAVING COUNT(*) >= s.min_payment_count_24h
ORDER BY payments_24h DESC, total_amount_24h DESC;


/* -------------------------------------------------------------------------
   Query 09: Ledger Coverage for Completed Workflows
   Why: Proxy for audit completeness / traceability.
--------------------------------------------------------------------------- */
WITH completed_payments AS (
  SELECT DISTINCT o.payment_id
  FROM orchestration_executions o
  WHERE UPPER(o.status) = 'COMPLETED'
),
ledger_linked_payments AS (
  SELECT DISTINCT
    ((regexp_match(l.description, '^P2P payment ([0-9]+):'))[1])::int AS payment_id
  FROM ledger l
  WHERE l.description ~ '^P2P payment [0-9]+:'
)
SELECT
  (SELECT COUNT(*) FROM completed_payments) AS completed_workflows,
  (SELECT COUNT(*) FROM ledger_linked_payments llp JOIN completed_payments cp ON cp.payment_id = llp.payment_id) AS completed_with_ledger_record,
  ROUND(
    100.0 * (
      SELECT COUNT(*)
      FROM ledger_linked_payments llp
      JOIN completed_payments cp ON cp.payment_id = llp.payment_id
    ) / NULLIF((SELECT COUNT(*) FROM completed_payments), 0),
    2
  ) AS ledger_coverage_pct;


/* -------------------------------------------------------------------------
   Query 10: Missing Ledger Records for Completed Workflows
   Why: Finds traceability gaps for reconciliation and audit review.
--------------------------------------------------------------------------- */
WITH completed_payments AS (
  SELECT DISTINCT o.payment_id
  FROM orchestration_executions o
  WHERE UPPER(o.status) = 'COMPLETED'
),
ledger_linked_payments AS (
  SELECT DISTINCT
    ((regexp_match(l.description, '^P2P payment ([0-9]+):'))[1])::int AS payment_id
  FROM ledger l
  WHERE l.description ~ '^P2P payment [0-9]+:'
)
SELECT
  cp.payment_id
FROM completed_payments cp
LEFT JOIN ledger_linked_payments llp
  ON llp.payment_id = cp.payment_id
WHERE llp.payment_id IS NULL
ORDER BY cp.payment_id;


/* -------------------------------------------------------------------------
   Query 11: Statement Coverage for Current Period
   Why: Monitors statement generation control for active accounts.
--------------------------------------------------------------------------- */
WITH period_ref AS (
  SELECT TO_CHAR(CURRENT_DATE, 'YYYY-MM') AS current_period
),
active_accounts AS (
  SELECT DISTINCT a.id AS account_id
  FROM accounts a
  LEFT JOIN payments p
    ON p.account_id = a.id OR p.recipient_account_id = a.id
  WHERE a.created_at >= NOW() - INTERVAL '30 days'
     OR p.created_at >= NOW() - INTERVAL '30 days'
),
accounts_with_statement AS (
  SELECT DISTINCT s.account_id
  FROM statements s
  JOIN period_ref pr
    ON s.period = pr.current_period
)
SELECT
  (SELECT current_period FROM period_ref) AS period,
  (SELECT COUNT(*) FROM active_accounts) AS active_accounts_30d,
  (SELECT COUNT(*) FROM accounts_with_statement aws JOIN active_accounts aa ON aa.account_id = aws.account_id) AS active_accounts_with_statement,
  ROUND(
    100.0 * (
      SELECT COUNT(*)
      FROM accounts_with_statement aws
      JOIN active_accounts aa ON aa.account_id = aws.account_id
    ) / NULLIF((SELECT COUNT(*) FROM active_accounts), 0),
    2
  ) AS statement_coverage_pct;


/* -------------------------------------------------------------------------
   Query 12: Account Balance Hygiene
   Why: Flags anomalous balances relevant to control checks.
--------------------------------------------------------------------------- */
SELECT
  COUNT(*) AS total_accounts,
  SUM(CASE WHEN balance < 0 THEN 1 ELSE 0 END) AS negative_balance_accounts,
  ROUND(COALESCE(MIN(balance), 0)::numeric, 2) AS minimum_balance,
  ROUND(COALESCE(MAX(balance), 0)::numeric, 2) AS maximum_balance,
  ROUND(COALESCE(AVG(balance), 0)::numeric, 2) AS average_balance
FROM accounts;


/* -------------------------------------------------------------------------
   Query 13: Dormant Accounts with Non-Zero Balance (90 Days)
   Why: Supports monitoring for inactive-but-funded accounts.
--------------------------------------------------------------------------- */
WITH account_activity AS (
  SELECT
    a.id AS account_id,
    a.name,
    a.email,
    a.balance,
    GREATEST(
      a.created_at,
      COALESCE(MAX(p.created_at), a.created_at)
    ) AS last_activity_at
  FROM accounts a
  LEFT JOIN payments p
    ON p.account_id = a.id OR p.recipient_account_id = a.id
  GROUP BY a.id, a.name, a.email, a.balance, a.created_at
)
SELECT
  account_id,
  name,
  email,
  ROUND(balance::numeric, 2) AS balance,
  last_activity_at
FROM account_activity
WHERE balance <> 0
  AND last_activity_at <= NOW() - INTERVAL '90 days'
ORDER BY last_activity_at ASC;


/* -------------------------------------------------------------------------
   Query 14: Identity Data Quality (PDPA Hygiene Proxy)
   Why: Basic quality checks over customer identifiers/contacts.
--------------------------------------------------------------------------- */
WITH normalized AS (
  SELECT
    id,
    LOWER(TRIM(email)) AS normalized_email,
    name
  FROM accounts
)
SELECT
  (SELECT COUNT(*) FROM accounts) AS total_accounts,
  (SELECT COUNT(*) FROM accounts WHERE email IS NULL OR TRIM(email) = '') AS missing_email_count,
  (SELECT COUNT(*) FROM accounts WHERE name IS NULL OR TRIM(name) = '') AS missing_name_count,
  (
    SELECT COALESCE(SUM(dup_count), 0)
    FROM (
      SELECT (COUNT(*) - 1) AS dup_count
      FROM normalized
      WHERE normalized_email IS NOT NULL AND normalized_email <> ''
      GROUP BY normalized_email
      HAVING COUNT(*) > 1
    ) d
  ) AS duplicate_email_overage_count;


/* -------------------------------------------------------------------------
   Query 15: Cloud Security Compliance Placeholder Metrics
   Why: These are required by your infra spec but need external security feeds.

   Expected source systems in requirements:
     - AWS Config
     - Security Hub
     - GuardDuty
     - CloudTrail
     - IAM Access Analyzer

   Action:
     Land those feeds into warehouse tables (example names below), then adapt.
--------------------------------------------------------------------------- */
-- Example placeholder query (commented out intentionally until data exists):
-- SELECT
--   ROUND(100.0 * SUM(CASE WHEN encrypted = true THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0), 2) AS encryption_compliance_percentage,
--   SUM(CASE WHEN is_public = true THEN 1 ELSE 0 END) AS public_resource_exposure,
--   SUM(CASE WHEN policy_violation = true THEN 1 ELSE 0 END) AS iam_policy_violations,
--   ROUND(100.0 * SUM(CASE WHEN mfa_enabled = true THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0), 2) AS mfa_enforcement_rate,
--   SUM(CASE WHEN severity = 'CRITICAL' THEN 1 ELSE 0 END) AS critical_security_findings
-- FROM compliance_asset_posture_snapshot;
