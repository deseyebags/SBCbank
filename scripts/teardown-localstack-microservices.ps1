Param(
    [string]$DbPassword = "localpassword"
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$terraformDir = Join-Path $repoRoot "terraform"
$backendDir = Join-Path $repoRoot "backend"
$envPath = Join-Path $backendDir ".env.runtime"

Write-Host "Stopping backend containers..."
Push-Location $backendDir
docker compose -f docker-compose.localstack.yml down -v | Out-Host
Pop-Location

Write-Host "Destroying LocalStack Terraform resources..."
$env:AWS_ACCESS_KEY_ID = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"
$env:AWS_DEFAULT_REGION = "ap-southeast-1"

Push-Location $terraformDir
terraform destroy -auto-approve -var-file="localstack.tfvars" -var="db_password=$DbPassword" | Out-Host
Pop-Location

if (Test-Path $envPath) {
    Remove-Item $envPath -Force
    Write-Host "Removed generated runtime env file: $envPath"
}

Write-Host "Teardown completed."
