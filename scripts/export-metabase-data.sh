#!/usr/bin/env bash

set -euo pipefail

ARCHIVE_PATH="artifacts/metabase_data.tar.gz"
VOLUME_NAME="backend_metabase_data"
COMPOSE_FILE="docker-compose.db-metabase.yml"
NO_STOP="false"

usage() {
  cat <<'EOF'
Usage: ./scripts/export-metabase-data.sh [options]

Options:
  --archive-path <path>   Output tar.gz archive path (default: artifacts/metabase_data.tar.gz)
  --volume-name <name>    Docker volume name (default: backend_metabase_data)
  --compose-file <file>   Compose file under backend/ (default: docker-compose.db-metabase.yml)
  --no-stop               Do not stop/restart metabase during export
  -h, --help              Show this help message
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

while [[ $# -gt 0 ]]; do
  case "$1" in
    --archive-path)
      require_option_value "$1" "${2:-}"
      ARCHIVE_PATH="$2"
      shift 2
      ;;
    --volume-name)
      require_option_value "$1" "${2:-}"
      VOLUME_NAME="$2"
      shift 2
      ;;
    --compose-file)
      require_option_value "$1" "${2:-}"
      COMPOSE_FILE="$2"
      shift 2
      ;;
    --no-stop)
      NO_STOP="true"
      shift
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

if ! command -v docker >/dev/null 2>&1; then
  echo "Docker is required but not installed." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BACKEND_DIR="$REPO_ROOT/backend"

if [[ ! -d "$BACKEND_DIR" ]]; then
  echo "Expected backend directory at '$BACKEND_DIR' but it was not found." >&2
  exit 1
fi

COMPOSE_PATH="$BACKEND_DIR/$COMPOSE_FILE"
if [[ ! -f "$COMPOSE_PATH" ]]; then
  echo "Compose file '$COMPOSE_FILE' was not found under backend/." >&2
  exit 1
fi

if ! docker volume inspect "$VOLUME_NAME" >/dev/null 2>&1; then
  echo "Docker volume '$VOLUME_NAME' was not found." >&2
  exit 1
fi

if [[ "$ARCHIVE_PATH" = /* ]]; then
  RESOLVED_ARCHIVE_PATH="$ARCHIVE_PATH"
else
  RESOLVED_ARCHIVE_PATH="$REPO_ROOT/$ARCHIVE_PATH"
fi

ARCHIVE_DIR="$(dirname "$RESOLVED_ARCHIVE_PATH")"
ARCHIVE_FILE="$(basename "$RESOLVED_ARCHIVE_PATH")"

mkdir -p "$ARCHIVE_DIR"

METABASE_WAS_RUNNING="false"
METABASE_CONTAINER_ID="$(cd "$BACKEND_DIR" && docker compose -f "$COMPOSE_FILE" ps -q metabase)"

if [[ -n "$METABASE_CONTAINER_ID" ]]; then
  RUNNING_STATE="$(docker inspect --format '{{.State.Running}}' "$METABASE_CONTAINER_ID" 2>/dev/null || true)"
  if [[ "$RUNNING_STATE" == "true" ]]; then
    METABASE_WAS_RUNNING="true"
  fi
fi

if [[ "$NO_STOP" == "false" && "$METABASE_WAS_RUNNING" == "true" ]]; then
  echo "Stopping Metabase for consistent backup..."
  (cd "$BACKEND_DIR" && docker compose -f "$COMPOSE_FILE" stop metabase)
fi

restore_service() {
  if [[ "$NO_STOP" == "false" && "$METABASE_WAS_RUNNING" == "true" ]]; then
    echo "Restarting Metabase service..."
    (cd "$BACKEND_DIR" && docker compose -f "$COMPOSE_FILE" up -d metabase)
  fi
}

trap restore_service EXIT

echo "Exporting volume '$VOLUME_NAME' to '$RESOLVED_ARCHIVE_PATH'..."
docker run --rm \
  -v "$VOLUME_NAME:/from" \
  --mount "type=bind,source=$ARCHIVE_DIR,target=/backup" \
  alpine sh -c "cd /from && tar czf /backup/$ARCHIVE_FILE ."

echo "Metabase data export completed: $RESOLVED_ARCHIVE_PATH"
