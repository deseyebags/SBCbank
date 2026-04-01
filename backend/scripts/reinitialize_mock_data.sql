-- Reinitialize and seed mock data for local analytics/compliance dashboards.
-- Target database: PostgreSQL (scbbank)

BEGIN;

-- Deterministic pseudo-random seed for reproducible demo data.
SELECT setseed(0.4581);

TRUNCATE TABLE
  statements,
  orchestration_executions,
  payments,
  ledger,
  accounts
RESTART IDENTITY CASCADE;

-- 1) Accounts
INSERT INTO accounts (name, email, balance, created_at)
SELECT
  'User ' || LPAD(gs::text, 3, '0') AS name,
  'user' || gs::text || '@example.com' AS email,
  CASE
    WHEN random() < 0.03
      THEN ROUND((-1 * random() * 200)::numeric, 2)::double precision
    ELSE ROUND((100 + random() * 20000)::numeric, 2)::double precision
  END AS balance,
  NOW()
    - ((random() * 220)::int || ' days')::interval
    - ((random() * 86400)::int || ' seconds')::interval AS created_at
FROM generate_series(1, 150) AS gs;

-- 2) Payments
WITH generated AS (
  SELECT
    gs AS seq,
    (1 + floor(random() * 150))::int AS payer_id,
    (1 + floor(random() * 150))::int AS raw_recipient_id,
    random() AS status_rand,
    random() AS recipient_null_rand,
    random() AS amount_rand,
    random() AS ts_day_rand,
    random() AS ts_sec_rand
  FROM generate_series(1, 2500) AS gs
)
INSERT INTO payments (
  account_id,
  recipient_account_id,
  amount,
  status,
  execution_id,
  created_at
)
SELECT
  g.payer_id,
  CASE
    WHEN g.recipient_null_rand < 0.02 THEN NULL
    WHEN g.raw_recipient_id = g.payer_id THEN ((g.raw_recipient_id % 150) + 1)
    ELSE g.raw_recipient_id
  END AS recipient_account_id,
  ROUND((10 + g.amount_rand * 25000)::numeric, 2)::double precision AS amount,
  CASE
    WHEN g.status_rand < 0.86 THEN 'SUCCESS'
    WHEN g.status_rand < 0.97 THEN 'FAILED'
    ELSE 'PENDING'
  END AS status,
  'exec-' || g.seq::text || '-' || SUBSTRING(md5((g.seq::text || clock_timestamp()::text)) FROM 1 FOR 12) AS execution_id,
  NOW()
    - ((g.ts_day_rand * 120)::int || ' days')::interval
    - ((g.ts_sec_rand * 86400)::int || ' seconds')::interval AS created_at
FROM generated g;

-- 3) Orchestration executions mapped from payments
INSERT INTO orchestration_executions (
  execution_id,
  payment_id,
  workflow_type,
  status,
  retry_count,
  error_message,
  created_at,
  updated_at,
  completed_at
)
SELECT
  p.execution_id,
  p.id,
  'P2P_PAYMENT' AS workflow_type,
  CASE
    WHEN UPPER(p.status) = 'SUCCESS' THEN 'COMPLETED'
    WHEN UPPER(p.status) = 'FAILED' THEN 'FAILED'
    ELSE 'RUNNING'
  END AS status,
  CASE
    WHEN UPPER(p.status) = 'FAILED' THEN (1 + floor(random() * 3))::int
    ELSE 0
  END AS retry_count,
  CASE
    WHEN UPPER(p.status) <> 'FAILED' THEN NULL
    ELSE
      CASE (1 + floor(random() * 4))::int
        WHEN 1 THEN 'Service call failed after retries'
        WHEN 2 THEN 'Insufficient balance'
        WHEN 3 THEN 'Recipient credit failed; payer refunded'
        ELSE 'Timeout contacting account-service'
      END
  END AS error_message,
  p.created_at AS created_at,
  CASE
    WHEN UPPER(p.status) IN ('SUCCESS', 'FAILED')
      THEN p.created_at + ((10 + floor(random() * 1200))::int || ' seconds')::interval
    ELSE p.created_at + ((10 + floor(random() * 300))::int || ' seconds')::interval
  END AS updated_at,
  CASE
    WHEN UPPER(p.status) IN ('SUCCESS', 'FAILED')
      THEN p.created_at + ((30 + floor(random() * 1800))::int || ' seconds')::interval
    ELSE NULL
  END AS completed_at
FROM payments p;

-- 4) Ledger: include most completed payment flows + some manual adjustments
WITH completed AS (
  SELECT
    oe.payment_id,
    oe.completed_at,
    p.account_id,
    p.recipient_account_id,
    p.amount
  FROM orchestration_executions oe
  JOIN payments p ON p.id = oe.payment_id
  WHERE UPPER(oe.status) = 'COMPLETED'
)
INSERT INTO ledger (description, amount, created_at)
SELECT
  'P2P payment ' || c.payment_id::text || ': '
  || c.account_id::text || ' -> '
  || COALESCE(c.recipient_account_id::text, 'UNKNOWN') AS description,
  c.amount,
  COALESCE(c.completed_at, NOW())
FROM completed c
WHERE random() < 0.92;

INSERT INTO ledger (description, amount, created_at)
SELECT
  'Manual adjustment ' || gs::text,
  ROUND(((random() * 500) - 250)::numeric, 2)::double precision,
  NOW() - ((random() * 90)::int || ' days')::interval
FROM generate_series(1, 120) gs;

-- 5) Statements: historical + current month coverage for active accounts
INSERT INTO statements (account_id, period, created_at)
SELECT
  a.id,
  TO_CHAR(date_trunc('month', NOW()) - (m::text || ' month')::interval, 'YYYY-MM') AS period,
  (date_trunc('month', NOW()) - (m::text || ' month')::interval)
    + ((1 + floor(random() * 25))::int || ' days')::interval AS created_at
FROM accounts a
CROSS JOIN generate_series(1, 5) AS m
WHERE random() < 0.72;

WITH active_accounts AS (
  SELECT DISTINCT a.id
  FROM accounts a
  LEFT JOIN payments p
    ON p.account_id = a.id OR p.recipient_account_id = a.id
  WHERE a.created_at >= NOW() - INTERVAL '30 days'
     OR p.created_at >= NOW() - INTERVAL '30 days'
)
INSERT INTO statements (account_id, period, created_at)
SELECT
  aa.id,
  TO_CHAR(date_trunc('month', NOW()), 'YYYY-MM') AS period,
  date_trunc('month', NOW())
    + ((1 + floor(random() * 20))::int || ' days')::interval AS created_at
FROM active_accounts aa
WHERE random() < 0.82;

COMMIT;

-- Summary checks after seed
SELECT 'accounts' AS table_name, COUNT(*) AS row_count FROM accounts
UNION ALL SELECT 'payments', COUNT(*) FROM payments
UNION ALL SELECT 'orchestration_executions', COUNT(*) FROM orchestration_executions
UNION ALL SELECT 'ledger', COUNT(*) FROM ledger
UNION ALL SELECT 'statements', COUNT(*) FROM statements
ORDER BY table_name;
