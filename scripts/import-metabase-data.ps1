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

$resolvedArchivePath = if ([System.IO.Path]::IsPathRooted($ArchivePath)) {
    $ArchivePath
}
else {
    Join-Path $repoRoot $ArchivePath
}

if (-not (Test-Path $resolvedArchivePath)) {
    throw "Archive file '$resolvedArchivePath' was not found."
}

$archiveDirectory = Split-Path -Path $resolvedArchivePath -Parent
$archiveFileName = Split-Path -Path $resolvedArchivePath -Leaf

if ([string]::IsNullOrWhiteSpace($archiveDirectory) -or [string]::IsNullOrWhiteSpace($archiveFileName)) {
    throw "ArchivePath must include a valid file name."
}

$metabaseWasRunning = $false

Push-Location $backendDir
try {
    $metabaseContainerId = (docker compose -f $ComposeFile ps -q metabase).Trim()
    if (-not [string]::IsNullOrWhiteSpace($metabaseContainerId)) {
        $isRunning = (docker inspect --format '{{.State.Running}}' $metabaseContainerId 2>$null).Trim()
        $metabaseWasRunning = $isRunning -eq "true"
    }

    if (-not $NoStop -and $metabaseWasRunning) {
        Write-Host "Stopping Metabase before import..."
        docker compose -f $ComposeFile stop metabase | Out-Host
    }

    try {
        docker volume inspect $VolumeName | Out-Null
    }
    catch {
        Write-Host "Volume '$VolumeName' not found. Creating it..."
        docker volume create $VolumeName | Out-Null
    }

    Write-Host "Importing '$resolvedArchivePath' into volume '$VolumeName'..."
    docker run --rm -v "${VolumeName}:/to" --mount "type=bind,source=$archiveDirectory,target=/backup" alpine sh -c "rm -rf /to/* /to/.[!.]* /to/..?* && tar xzf /backup/$archiveFileName -C /to" | Out-Host

    Write-Host "Metabase data import completed for volume '$VolumeName'."
}
finally {
    if (-not $NoStop -and $metabaseWasRunning) {
        Write-Host "Restarting Metabase service..."
        docker compose -f $ComposeFile up -d metabase | Out-Host
    }

    Pop-Location
}
