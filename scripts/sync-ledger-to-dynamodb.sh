#!/usr/bin/env bash

set -euo pipefail

LOCALSTACK_ENDPOINT="http://localhost:4566"
LEDGER_TABLE_NAME="sbcbank-dev-ledger"
POSTGRES_SERVICE="postgres"
POSTGRES_DATABASE="scbbank"
POSTGRES_USER="scbbank"
LIMIT="0"
COMPOSE_FILE="docker-compose.yml"

usage() {
  cat <<'EOF'
Usage: ./scripts/sync-ledger-to-dynamodb.sh [options]

Options:
  --localstack-endpoint <url>   LocalStack endpoint (default: http://localhost:4566)
  --ledger-table-name <name>    DynamoDB ledger table name (default: sbcbank-dev-ledger)
  --postgres-service <name>     Docker Compose postgres service name (default: postgres)
  --postgres-database <name>    PostgreSQL database name (default: scbbank)
  --postgres-user <name>        PostgreSQL user (default: scbbank)
  --limit <number>              Max number of rows to sync (default: 0, meaning all)
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
    --ledger-table-name)
      require_option_value "$1" "${2:-}"
      LEDGER_TABLE_NAME="$2"
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
    --limit)
      require_option_value "$1" "${2:-}"
      LIMIT="$2"
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

case "$LIMIT" in
  ''|*[!0-9]*)
    echo "--limit must be a non-negative integer" >&2
    exit 1
    ;;
esac

if ! command -v aws >/dev/null 2>&1; then
  echo "AWS CLI is required but not installed." >&2
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "Docker is required but not installed." >&2
  exit 1
fi

export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-test}"
export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-test}"
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-ap-southeast-1}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BACKEND_DIR="$REPO_ROOT/backend"

if [[ ! -d "$BACKEND_DIR" ]]; then
  echo "Expected backend directory at '$BACKEND_DIR' but it was not found." >&2
  exit 1
fi

if ! aws --endpoint-url "$LOCALSTACK_ENDPOINT" dynamodb describe-table --table-name "$LEDGER_TABLE_NAME" >/dev/null 2>&1; then
  echo "DynamoDB table '$LEDGER_TABLE_NAME' was not found. Run Terraform apply first or pass --ledger-table-name with an existing table." >&2
  exit 1
fi

SQL_QUERY=$(cat <<'SQL'
SELECT
  id,
  COALESCE(REPLACE(description, '|', '/'), ''),
  COALESCE(amount::text, '0'),
  to_char(created_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
FROM ledger
ORDER BY id;
SQL
)

COMPOSE_ARGS=()
if [[ -n "$COMPOSE_FILE" ]]; then
  COMPOSE_ARGS=(-f "$COMPOSE_FILE")
fi

written=0
processed=0

while IFS= read -r row; do
  if [[ -z "${row//[[:space:]]/}" ]]; then
    continue
  fi

  if [[ "$LIMIT" -gt 0 && "$processed" -ge "$LIMIT" ]]; then
    break
  fi

  IFS='|' read -r id description amount created_at <<<"$row"

  if [[ -z "$id" || -z "$amount" || -z "$created_at" ]]; then
    continue
  fi

  description_escaped="$(json_escape "$description")"
  created_at_escaped="$(json_escape "$created_at")"

  item_json=$(printf '{"id":{"N":"%s"},"description":{"S":"%s"},"amount":{"N":"%s"},"created_at":{"S":"%s"}}' \
    "$id" "$description_escaped" "$amount" "$created_at_escaped")

  aws --endpoint-url "$LOCALSTACK_ENDPOINT" dynamodb put-item --table-name "$LEDGER_TABLE_NAME" --item "$item_json" >/dev/null

  written=$((written + 1))
  processed=$((processed + 1))
done < <(
  cd "$BACKEND_DIR" && docker compose "${COMPOSE_ARGS[@]}" exec -T "$POSTGRES_SERVICE" \
    psql -U "$POSTGRES_USER" -d "$POSTGRES_DATABASE" -t -A -F "|" -c "$SQL_QUERY"
)

if [[ "$written" -eq 0 ]]; then
  echo "No ledger rows found in PostgreSQL. Nothing to sync."
  exit 0
fi

echo "Synced $written ledger rows into DynamoDB table '$LEDGER_TABLE_NAME'."