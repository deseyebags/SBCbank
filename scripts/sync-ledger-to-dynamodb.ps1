Param(
    [string]$LocalstackEndpoint = "http://localhost:4566",
    [string]$LedgerTableName = "sbcbank-dev-ledger",
    [string]$PostgresService = "postgres",
    [string]$PostgresDatabase = "scbbank",
    [string]$PostgresUser = "scbbank",
    [int]$Limit = 0
)

$ErrorActionPreference = "Stop"

if (-not $env:AWS_ACCESS_KEY_ID) {
    $env:AWS_ACCESS_KEY_ID = "test"
}
if (-not $env:AWS_SECRET_ACCESS_KEY) {
    $env:AWS_SECRET_ACCESS_KEY = "test"
}
if (-not $env:AWS_DEFAULT_REGION) {
    $env:AWS_DEFAULT_REGION = "ap-southeast-1"
}

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$backendDir = Join-Path $repoRoot "backend"

try {
    aws --endpoint-url $LocalstackEndpoint dynamodb describe-table --table-name $LedgerTableName | Out-Null
}
catch {
    throw "DynamoDB table '$LedgerTableName' was not found. Run Terraform apply first or pass -LedgerTableName with an existing table."
}

$sql = @"
SELECT
  id,
  COALESCE(REPLACE(description, '|', '/'), ''),
  COALESCE(amount::text, '0'),
  to_char(created_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
FROM ledger
ORDER BY id;
"@

Push-Location $backendDir
try {
    $rows = docker compose exec -T $PostgresService psql -U $PostgresUser -d $PostgresDatabase -t -A -F "|" -c $sql
}
finally {
    Pop-Location
}

$rows = @($rows | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

if ($Limit -gt 0) {
    $rows = @($rows | Select-Object -First $Limit)
}

if ($rows.Count -eq 0) {
    Write-Host "No ledger rows found in PostgreSQL. Nothing to sync."
    return
}

$written = 0
foreach ($row in $rows) {
    $parts = $row.Split("|", 4)
    if ($parts.Count -lt 4) {
        continue
    }

    $item = [ordered]@{
        id          = [ordered]@{ N = $parts[0].Trim() }
        description = [ordered]@{ S = $parts[1] }
        amount      = [ordered]@{ N = $parts[2].Trim() }
        created_at  = [ordered]@{ S = $parts[3].Trim() }
    }

    $itemJson = $item | ConvertTo-Json -Compress -Depth 6
    aws --endpoint-url $LocalstackEndpoint dynamodb put-item --table-name $LedgerTableName --item $itemJson | Out-Null
    $written++
}

Write-Host "Synced $written ledger rows into DynamoDB table '$LedgerTableName'."
