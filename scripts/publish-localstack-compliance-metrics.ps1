Param(
    [string]$LocalstackEndpoint = "http://localhost:4566"
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$terraformDir = Join-Path $repoRoot "terraform"
$backendDir = Join-Path $repoRoot "backend"

$env:AWS_ACCESS_KEY_ID = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"
$env:AWS_DEFAULT_REGION = "ap-southeast-1"

Push-Location $terraformDir
$outputs = (terraform output -json | ConvertFrom-Json)
Pop-Location

if (-not $outputs.compliance_metrics_bucket_name -or -not $outputs.compliance_metrics_log_group_name) {
    throw "Missing Terraform outputs for compliance metrics resources. Run terraform apply first."
}

$metricsBucket = $outputs.compliance_metrics_bucket_name.value
$logGroupName = $outputs.compliance_metrics_log_group_name.value

$sql = @"
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
),
ledger_stats AS (
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
    ROUND(
      100.0 * (
        SELECT COUNT(*)
        FROM ledger_linked_payments llp
        JOIN completed_payments cp ON cp.payment_id = llp.payment_id
      ) / NULLIF((SELECT COUNT(*) FROM completed_payments), 0),
      2
    ) AS ledger_coverage_pct
),
statement_stats AS (
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
    ROUND(
      100.0 * (
        SELECT COUNT(*)
        FROM accounts_with_statement aws
        JOIN active_accounts aa ON aa.account_id = aws.account_id
      ) / NULLIF((SELECT COUNT(*) FROM active_accounts), 0),
      2
    ) AS statement_coverage_pct
)
SELECT
  COALESCE((SELECT COUNT(*) FROM payment_window), 0) AS total_payments_30d,
  COALESCE(ROUND(
    100.0 * (SELECT COUNT(*) FROM payment_window WHERE UPPER(status) = 'SUCCESS')
    / NULLIF((SELECT COUNT(*) FROM payment_window), 0),
    2
  ), 0) AS payment_success_rate_pct_30d,
  COALESCE((SELECT COUNT(*) FROM payment_window WHERE UPPER(status) = 'FAILED'), 0) AS failed_payments_30d,
  COALESCE((SELECT COUNT(*) FROM payment_window pw CROSS JOIN settings s WHERE pw.amount >= s.high_value_threshold), 0) AS high_value_payments_30d,
  COALESCE(ROUND((SELECT COALESCE(AVG(amount), 0.0) FROM payment_window)::numeric, 2), 0) AS avg_payment_amount_30d,
  COALESCE((SELECT COUNT(*) FROM workflow_window WHERE UPPER(status) = 'FAILED'), 0) AS failed_workflows_30d,
  COALESCE((SELECT COUNT(*) FROM workflow_window WHERE UPPER(status) = 'RUNNING'), 0) AS running_workflows_30d,
  COALESCE((SELECT ledger_coverage_pct FROM ledger_stats), 0) AS ledger_coverage_pct,
  COALESCE((SELECT statement_coverage_pct FROM statement_stats), 0) AS statement_coverage_pct;
"@

Push-Location $backendDir
$row = docker compose exec -T postgres psql -U scbbank -d scbbank -t -A -F "," -c $sql
Pop-Location

$values = ($row.Trim() -split ",")
if ($values.Count -ne 9) {
    throw "Unexpected SQL output format while building compliance metrics payload."
}

$snapshot = [ordered]@{
    snapshot_time                 = (Get-Date).ToUniversalTime().ToString("o")
    total_payments_30d           = [int]$values[0]
    payment_success_rate_pct_30d = [double]$values[1]
    failed_payments_30d          = [int]$values[2]
    high_value_payments_30d      = [int]$values[3]
    avg_payment_amount_30d       = [double]$values[4]
    failed_workflows_30d         = [int]$values[5]
    running_workflows_30d        = [int]$values[6]
    ledger_coverage_pct          = [double]$values[7]
    statement_coverage_pct       = [double]$values[8]
}

$snapshotJson = $snapshot | ConvertTo-Json -Compress
$timestamp = [int64]([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())
$streamName = "snapshot-$timestamp"

aws --endpoint-url $LocalstackEndpoint logs create-log-stream --log-group-name $logGroupName --log-stream-name $streamName | Out-Null

$logPayload = [ordered]@{
    logGroupName  = $logGroupName
    logStreamName = $streamName
    logEvents     = @(
        [ordered]@{
            timestamp = $timestamp
            message   = $snapshotJson
        }
    )
}

$tempLogPayload = [System.IO.Path]::GetTempFileName()
$logPayload | ConvertTo-Json -Depth 6 | Set-Content -Path $tempLogPayload
aws --endpoint-url $LocalstackEndpoint logs put-log-events --cli-input-json "file://$tempLogPayload" | Out-Null

$tempSnapshot = [System.IO.Path]::GetTempFileName()
Set-Content -Path $tempSnapshot -Value $snapshotJson
aws --endpoint-url $LocalstackEndpoint s3 cp $tempSnapshot "s3://$metricsBucket/snapshots/compliance_snapshot_$timestamp.json" | Out-Null

Remove-Item $tempLogPayload -ErrorAction SilentlyContinue
Remove-Item $tempSnapshot -ErrorAction SilentlyContinue

Write-Host "Published compliance snapshot to CloudWatch Logs and S3."
Write-Host "Log group: $logGroupName"
Write-Host "S3 path: s3://$metricsBucket/snapshots/compliance_snapshot_$timestamp.json"
Write-Host "Snapshot payload: $snapshotJson"
