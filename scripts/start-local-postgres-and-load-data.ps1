Param(
    [string]$PostgresService = "postgres",
    [string]$PostgresDatabase = "scbbank",
    [string]$PostgresUser = "scbbank",
    [string]$ComposeFile = "docker-compose.yml",
    [string]$SeedSqlPath = "backend/scripts/reinitialize_mock_data.sql",
    [int]$WaitTimeoutSeconds = 120
)

$ErrorActionPreference = "Stop"

if ($WaitTimeoutSeconds -lt 5) {
    throw "WaitTimeoutSeconds must be at least 5 seconds."
}

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$backendDir = Join-Path $repoRoot "backend"
$seedSqlFile = Join-Path $repoRoot $SeedSqlPath

if (-not (Test-Path $backendDir)) {
    throw "Expected backend directory at '$backendDir' but it was not found."
}

if (-not (Test-Path $seedSqlFile)) {
    throw "Seed SQL file was not found at '$seedSqlFile'."
}

$composeArgs = @()
if (-not [string]::IsNullOrWhiteSpace($ComposeFile)) {
    $composePath = Join-Path $backendDir $ComposeFile
    if (-not (Test-Path $composePath)) {
        throw "Compose file '$ComposeFile' was not found under backend/."
    }

    $composeArgs += "-f"
    $composeArgs += $composePath
}

$schemaSql = @"
CREATE TABLE IF NOT EXISTS accounts (
  id SERIAL PRIMARY KEY,
  name VARCHAR NOT NULL,
  email VARCHAR NOT NULL UNIQUE,
  balance DOUBLE PRECISION NOT NULL DEFAULT 0.0,
  created_at TIMESTAMP WITHOUT TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS payments (
  id SERIAL PRIMARY KEY,
  account_id INTEGER REFERENCES accounts(id),
  recipient_account_id INTEGER,
  amount DOUBLE PRECISION NOT NULL,
  status VARCHAR NOT NULL,
  execution_id VARCHAR UNIQUE,
  created_at TIMESTAMP WITHOUT TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS ledger (
  id SERIAL PRIMARY KEY,
  description VARCHAR,
  amount DOUBLE PRECISION,
  created_at TIMESTAMP WITHOUT TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS orchestration_executions (
  id SERIAL PRIMARY KEY,
  execution_id VARCHAR NOT NULL UNIQUE,
  payment_id INTEGER NOT NULL,
  workflow_type VARCHAR NOT NULL DEFAULT 'P2P_PAYMENT',
  status VARCHAR NOT NULL,
  retry_count INTEGER NOT NULL DEFAULT 0,
  error_message VARCHAR,
  created_at TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
  completed_at TIMESTAMP WITHOUT TIME ZONE
);

CREATE TABLE IF NOT EXISTS statements (
  id SERIAL PRIMARY KEY,
  account_id INTEGER REFERENCES accounts(id),
  period VARCHAR,
  created_at TIMESTAMP WITHOUT TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS ix_orchestration_executions_execution_id ON orchestration_executions (execution_id);
CREATE INDEX IF NOT EXISTS ix_orchestration_executions_payment_id ON orchestration_executions (payment_id);
"@

Push-Location $backendDir
try {
    Write-Host "Starting PostgreSQL service '$PostgresService'..."
    docker compose @composeArgs up -d $PostgresService | Out-Host

    $containerId = (docker compose @composeArgs ps -q $PostgresService).Trim()
    if ([string]::IsNullOrWhiteSpace($containerId)) {
        throw "Unable to resolve container ID for service '$PostgresService'."
    }

    $deadline = (Get-Date).AddSeconds($WaitTimeoutSeconds)
    while ($true) {
        $status = (docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' $containerId 2>$null).Trim()

        if ($status -eq "healthy" -or $status -eq "running") {
            break
        }

        if ((Get-Date) -ge $deadline) {
            throw "Timed out waiting for '$PostgresService' to become ready. Last status: '$status'."
        }

        Start-Sleep -Seconds 2
    }

    Write-Host "PostgreSQL is ready. Bootstrapping schema..."
    $schemaSql | docker compose @composeArgs exec -T $PostgresService psql -v ON_ERROR_STOP=1 -U $PostgresUser -d $PostgresDatabase -f - | Out-Host

    Write-Host "Loading seed data from '$SeedSqlPath'..."
    Get-Content -Raw -Path $seedSqlFile | docker compose @composeArgs exec -T $PostgresService psql -v ON_ERROR_STOP=1 -U $PostgresUser -d $PostgresDatabase -f - | Out-Host

    Write-Host "Local PostgreSQL container started and data loaded successfully."
}
finally {
    Pop-Location
}
