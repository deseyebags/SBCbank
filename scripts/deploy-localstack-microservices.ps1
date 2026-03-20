Param(
	[string]$DbPassword = "localpassword"
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$terraformDir = Join-Path $repoRoot "terraform"
$backendDir = Join-Path $repoRoot "backend"
$envPath = Join-Path $backendDir ".env.runtime"

Write-Host "Setting LocalStack AWS environment variables..."
$env:AWS_ACCESS_KEY_ID = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"
$env:AWS_DEFAULT_REGION = "ap-southeast-1"
Write-Host "Ensure LocalStack is running at http://localhost:4566 before continuing."

Write-Host "Applying Terraform resources in LocalStack..."
Push-Location $terraformDir
terraform init | Out-Host
terraform apply -auto-approve -var-file="localstack.tfvars" -var="db_password=$DbPassword" | Out-Host

$outputsRaw = terraform output -json
$outputs = $outputsRaw | ConvertFrom-Json
Pop-Location

function Get-OutputValue {
	param(
		[Parameter(Mandatory = $true)] [object]$Object,
		[Parameter(Mandatory = $true)] [string]$Name,
		[string]$Fallback = ""
	)

	if ($Object.PSObject.Properties.Name -contains $Name) {
		return $Object.$Name.value
	}

	return $Fallback
}

$eventBusName = Get-OutputValue -Object $outputs -Name "eventbridge_bus_name" -Fallback "sbcbank-dev-main-bus"
$manualReviewQueueUrl = Get-OutputValue -Object $outputs -Name "transactions_queue_url" -Fallback "http://host.docker.internal:4566/000000000000/sbcbank-dev-transactions"
$postgresHost = "postgres"
$postgresPort = "5432"
$redisHost = "redis"

$envContent = @(
	"AWS_REGION=ap-southeast-1",
	"AWS_ACCESS_KEY_ID=test",
	"AWS_SECRET_ACCESS_KEY=test",
	"AWS_ENDPOINT_URL=http://host.docker.internal:4566",
	"EVENT_BUS_NAME=$eventBusName",
	"PAYMENT_WORKFLOW_ARN=arn:aws:states:ap-southeast-1:000000000000:stateMachine:sbcbank-payment-workflow",
	"MANUAL_REVIEW_QUEUE_URL=$manualReviewQueueUrl",
	"LEDGER_TABLE_NAME=sbcbank-dev-ledger",
	"STATEMENT_TABLE_NAME=sbcbank-dev-statement",
	"POSTGRES_HOST=$postgresHost",
	"POSTGRES_PORT=$postgresPort",
	"POSTGRES_DB=sbcbank",
	"POSTGRES_USER=sbcbank",
	"POSTGRES_PASSWORD=$DbPassword",
	"DATABASE_URL=postgresql://sbcbank:$DbPassword@$postgresHost:$postgresPort/sbcbank",
	"REDIS_HOST=$redisHost",
	"REDIS_PORT=6379"
)

Set-Content -Path $envPath -Value $envContent
Write-Host "Generated runtime env file at $envPath"

Write-Host "Building and starting microservices with Docker Compose..."
Push-Location $backendDir
docker compose -f docker-compose.localstack.yml up --build -d | Out-Host
Pop-Location

Write-Host "Deployment completed."
Write-Host "Account service:   http://localhost:8001/accounts"
Write-Host "Payment service:   http://localhost:8002/payments"
Write-Host "Ledger service:    http://localhost:8003/ledger"
Write-Host "Statement service: http://localhost:8004/statements"
