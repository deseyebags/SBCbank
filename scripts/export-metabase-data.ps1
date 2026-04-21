Param(
    [string]$ArchivePath = "artifacts/metabase_data.tar.gz",
    [string]$VolumeName = "backend_metabase_data",
    [string]$ComposeFile = "docker-compose.db-metabase.yml",
    [switch]$NoStop
)

$ErrorActionPreference = "Stop"

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw "Docker is required but not installed or not on PATH."
}

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$backendDir = Join-Path $repoRoot "backend"

if (-not (Test-Path $backendDir)) {
    throw "Expected backend directory at '$backendDir' but it was not found."
}

$composePath = Join-Path $backendDir $ComposeFile
if (-not (Test-Path $composePath)) {
    throw "Compose file '$ComposeFile' was not found under backend/."
}

try {
    docker volume inspect $VolumeName | Out-Null
}
catch {
    throw "Docker volume '$VolumeName' was not found."
}

$resolvedArchivePath = if ([System.IO.Path]::IsPathRooted($ArchivePath)) {
    $ArchivePath
}
else {
    Join-Path $repoRoot $ArchivePath
}

$archiveDirectory = Split-Path -Path $resolvedArchivePath -Parent
$archiveFileName = Split-Path -Path $resolvedArchivePath -Leaf

if ([string]::IsNullOrWhiteSpace($archiveDirectory) -or [string]::IsNullOrWhiteSpace($archiveFileName)) {
    throw "ArchivePath must include a valid file name."
}

New-Item -ItemType Directory -Path $archiveDirectory -Force | Out-Null

$metabaseWasRunning = $false

Push-Location $backendDir
try {
    $metabaseContainerId = (docker compose -f $ComposeFile ps -q metabase).Trim()
    if (-not [string]::IsNullOrWhiteSpace($metabaseContainerId)) {
        $isRunning = (docker inspect --format '{{.State.Running}}' $metabaseContainerId 2>$null).Trim()
        $metabaseWasRunning = $isRunning -eq "true"
    }

    if (-not $NoStop -and $metabaseWasRunning) {
        Write-Host "Stopping Metabase for consistent backup..."
        docker compose -f $ComposeFile stop metabase | Out-Host
    }

    Write-Host "Exporting volume '$VolumeName' to '$resolvedArchivePath'..."
    docker run --rm -v "${VolumeName}:/from" --mount "type=bind,source=$archiveDirectory,target=/backup" alpine sh -c "cd /from && tar czf /backup/$archiveFileName ." | Out-Host

    Write-Host "Metabase data export completed: $resolvedArchivePath"
}
finally {
    if (-not $NoStop -and $metabaseWasRunning) {
        Write-Host "Restarting Metabase service..."
        docker compose -f $ComposeFile up -d metabase | Out-Host
    }

    Pop-Location
}
