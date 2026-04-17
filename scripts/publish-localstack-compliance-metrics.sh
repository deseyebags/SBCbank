#!/usr/bin/env bash

set -euo pipefail

LOCALSTACK_ENDPOINT="http://localhost:4566"
POSTGRES_SERVICE="postgres"
POSTGRES_DATABASE="scbbank"
POSTGRES_USER="scbbank"
COMPOSE_FILE="docker-compose.yml"

usage() {
  cat <<'EOF'
Usage: ./scripts/publish-localstack-compliance-metrics.sh [options]

Options:
  --localstack-endpoint <url>   LocalStack endpoint (default: http://localhost:4566)
  --postgres-service <name>     Docker Compose postgres service name (default: postgres)
  --postgres-database <name>    PostgreSQL database name (default: scbbank)
  --postgres-user <name>        PostgreSQL user (default: scbbank)
  --compose-file <file>         Compose file relative to backend/ (default: docker-compose.yml)
  -h, --help                    Show this help message
EOF
}

require_option_value() {
  local option_name="$1"
  local option_value="${2:-}"

  if [[ -z "$option_value" || "$option_value" == --* ]]; then
    echo "Missing value for $option_name" >&2
    exit 1
  fi
}

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

json_escape() {
  local value="$1"
  value=${value//\\/\\\\}
  value=${value//\"/\\\"}
  value=${value//$'\n'/\\n}
  value=${value//$'\r'/\\r}
  value=${value//$'\t'/\\t}
  printf '%s' "$value"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --localstack-endpoint)
      require_option_value "$1" "${2:-}"
      LOCALSTACK_ENDPOINT="$2"
      shift 2
      ;;
    --postgres-service)
      require_option_value "$1" "${2:-}"
      POSTGRES_SERVICE="$2"
      shift 2
      ;;
    --postgres-database)
      require_option_value "$1" "${2:-}"
      POSTGRES_DATABASE="$2"
      shift 2
      ;;
    --postgres-user)
      require_option_value "$1" "${2:-}"
      POSTGRES_USER="$2"
      shift 2
      ;;
    --compose-file)
      require_option_value "$1" "${2:-}"
      COMPOSE_FILE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

for cmd in aws docker terraform; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "$cmd is required but not installed." >&2
    exit 1
  fi
done

export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-test}"
export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-test}"
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-ap-southeast-1}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TERRAFORM_DIR="$REPO_ROOT/terraform"
BACKEND_DIR="$REPO_ROOT/backend"

if [[ ! -d "$TERRAFORM_DIR" || ! -d "$BACKEND_DIR" ]]; then
  echo "Expected terraform and backend directories under '$REPO_ROOT'." >&2
  exit 1
fi

get_tf_output() {
  local output_name="$1"
  (
    cd "$TERRAFORM_DIR" && terraform output -raw "$output_name" 2>/dev/null || true
  )
}

metrics_bucket="$(get_tf_output compliance_metrics_bucket_name)"
log_group_name="$(get_tf_output compliance_metrics_log_group_name)"

if [[ -z "$metrics_bucket" || -z "$log_group_name" ]]; then
  echo "Missing Terraform outputs for compliance metrics resources. Run terraform apply first." >&2
  exit 1
fi

SQL_QUERY=$(cat <<'SQL'
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
SQL
)

COMPOSE_ARGS=()
if [[ -n "$COMPOSE_FILE" ]]; then
  COMPOSE_ARGS=(-f "$COMPOSE_FILE")
fi

row=$(cd "$BACKEND_DIR" && docker compose "${COMPOSE_ARGS[@]}" exec -T "$POSTGRES_SERVICE" \
  psql -U "$POSTGRES_USER" -d "$POSTGRES_DATABASE" -t -A -F "|" -c "$SQL_QUERY")

row="$(printf '%s\n' "$row" | awk 'NF {print; exit}')"

IFS='|' read -r -a values <<< "$row"
if [[ "${#values[@]}" -ne 9 ]]; then
  echo "Unexpected SQL output format while building compliance metrics payload." >&2
  exit 1
fi

for i in "${!values[@]}"; do
  values[$i]="$(trim "${values[$i]}")"
done

snapshot_time="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
timestamp="$(( $(date +%s) * 1000 ))"
stream_name="snapshot-$timestamp"

snapshot_json=$(printf '{"snapshot_time":"%s","total_payments_30d":%s,"payment_success_rate_pct_30d":%s,"failed_payments_30d":%s,"high_value_payments_30d":%s,"avg_payment_amount_30d":%s,"failed_workflows_30d":%s,"running_workflows_30d":%s,"ledger_coverage_pct":%s,"statement_coverage_pct":%s}' \
  "$(json_escape "$snapshot_time")" \
  "${values[0]}" "${values[1]}" "${values[2]}" "${values[3]}" "${values[4]}" "${values[5]}" "${values[6]}" "${values[7]}" "${values[8]}")

temp_log_payload="$(mktemp)"
temp_snapshot="$(mktemp)"

cleanup() {
  rm -f "$temp_log_payload" "$temp_snapshot"
}

trap cleanup EXIT

aws --endpoint-url "$LOCALSTACK_ENDPOINT" logs create-log-stream --log-group-name "$log_group_name" --log-stream-name "$stream_name" >/dev/null

log_payload_json=$(printf '{"logGroupName":"%s","logStreamName":"%s","logEvents":[{"timestamp":%s,"message":"%s"}]}' \
  "$(json_escape "$log_group_name")" \
  "$(json_escape "$stream_name")" \
  "$timestamp" \
  "$(json_escape "$snapshot_json")")

printf '%s' "$log_payload_json" > "$temp_log_payload"
aws --endpoint-url "$LOCALSTACK_ENDPOINT" logs put-log-events --cli-input-json "file://$temp_log_payload" >/dev/null

printf '%s' "$snapshot_json" > "$temp_snapshot"
s3_path="s3://$metrics_bucket/snapshots/compliance_snapshot_$timestamp.json"
aws --endpoint-url "$LOCALSTACK_ENDPOINT" s3 cp "$temp_snapshot" "$s3_path" >/dev/null

echo "Published compliance snapshot to CloudWatch Logs and S3."
echo "Log group: $log_group_name"
echo "S3 path: $s3_path"
echo "Snapshot payload: $snapshot_json"
