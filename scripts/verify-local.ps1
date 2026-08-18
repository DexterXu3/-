$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$composeFile = Join-Path $projectRoot "agent-compose.yml"
$sampleFile = Join-Path $projectRoot "samples\vulnerable-route.js"
$serviceTest = Join-Path $projectRoot "octobus\code-security\test\analyzer.test.js"
$failures = [System.Collections.Generic.List[string]]::new()

function Check([bool]$condition, [string]$message) {
    if ($condition) {
        Write-Host "[PASS] $message" -ForegroundColor Green
    } else {
        Write-Host "[FAIL] $message" -ForegroundColor Red
        $failures.Add($message)
    }
}

function DockerExec([string]$container, [string[]]$arguments) {
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $output = & docker exec $container @arguments 2>&1
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousPreference
    }
    $text = ($output | ForEach-Object { $_.ToString() }) -join "`n"
    return @{ Output = $text; ExitCode = $exitCode }
}

Write-Host "1/8 Checking containers"
$running = docker ps --format '{{.Names}}'
Check ($running -contains "qwen-agent-mvp-daemon") "agent-compose daemon is running"
Check ($running -contains "octobus-dev") "OctoBus daemon is running"
Check ($running -contains "qwen-agent-mvp-web") "Web UI is running"

Write-Host "2/8 Running deterministic rule tests"
& node --test $serviceTest
Check ($LASTEXITCODE -eq 0) "code security rule tests pass"

Write-Host "3/8 Validating the Agent project"
$config = DockerExec "qwen-agent-mvp-daemon" @("agent-compose", "--file", "/data/work/agent-compose.yml", "config")
Check ($config.ExitCode -eq 0) "agent-compose project is valid"

Write-Host "4/8 Checking OctoBus resources"
$status = DockerExec "octobus-dev" @("octobus", "status")
Check ($status.ExitCode -eq 0 -and $status.Output -match '"status":\s*"ok"') "OctoBus status is OK"
$methods = DockerExec "octobus-dev" @("octobus", "capset", "list-methods", "security-review")
Check ($methods.ExitCode -eq 0 -and $methods.Output -match "AnalyzeSnippet") "security-review exposes AnalyzeSnippet"

Write-Host "5/8 Calling the capability through Connect RPC"
$sourceText = [string](Get-Content -Raw -Encoding UTF8 $sampleFile)
$payload = [ordered]@{ filename = "vulnerable-route.js"; language = "javascript"; code = $sourceText }
$body = ConvertTo-Json -InputObject $payload -Compress
$result = Invoke-RestMethod -Method Post `
    -Uri "http://127.0.0.1:9000/capsets/security-review/connect/code-security-main/codesecurity.v1.CodeSecurityService/AnalyzeSnippet" `
    -ContentType "application/json" `
    -Body ([System.Text.Encoding]::UTF8.GetBytes($body))
$ruleIds = @($result.findings | ForEach-Object { $_.ruleId })
Check ($ruleIds -contains "HARDCODED_SECRET") "sample reports HARDCODED_SECRET"
Check ($ruleIds -contains "CMD_INJECTION") "sample reports CMD_INJECTION"

Write-Host "6/8 Checking the Web-to-Agent end-to-end chain"
$webHealth = Invoke-RestMethod -Uri "http://127.0.0.1:3000/api/health"
Check ($webHealth.status -eq "ok" -and $webHealth.auditPath -eq "agent-compose") "Web UI declares the Agent Compose audit path"
$requestId = "audit-e2e-$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())"
$payload["requestId"] = $requestId
$body = ConvertTo-Json -InputObject $payload -Compress
$webResult = Invoke-RestMethod -Method Post `
    -Uri "http://127.0.0.1:3000/api/audit" `
    -ContentType "application/json" `
    -Body ([System.Text.Encoding]::UTF8.GetBytes($body))
$webRuleIds = @($webResult.findings | ForEach-Object { $_.ruleId })
Check ($webResult.requestId -eq $requestId) "Web report preserves the end-to-end request ID"
Check (-not [string]::IsNullOrWhiteSpace($webResult.runId)) "Web report contains a persistent Agent Run ID"
Check ($webResult.pipeline.web -eq "agent-compose" -and $webResult.pipeline.skill -eq "code-security" -and $webResult.pipeline.capability -match "OctoBus") "Web report proves the Agent-Skill-OctoBus path"
Check ($webRuleIds -contains "HARDCODED_SECRET" -and $webRuleIds -contains "CMD_INJECTION") "Agent report preserves OctoBus findings"

Write-Host "7/8 Checking auditable access logs"
$logs = DockerExec "octobus-dev" @("octobus", "logs", "--capset", "security-review", "--limit", "50")
Check ($logs.ExitCode -eq 0 -and $logs.Output -match '"protocol":"connect".*"http_status":200') "Connect RPC success is recorded"
Check ($logs.Output -match '"protocol":"grpc".*"grpc_code":"OK"') "Agent gRPC success is recorded"

Write-Host "8/8 Checking model and bypass invariants"
$composeText = Get-Content -Raw -Encoding UTF8 $composeFile
$modelsText = Get-Content -Raw -Encoding UTF8 (Join-Path $projectRoot "models.json")
$envExampleText = Get-Content -Raw -Encoding UTF8 (Join-Path $projectRoot ".env.example")
Check ($composeText -match 'model:\s+default/qwen-max' -and $modelsText -match '"default":\s*"dashscope/qwen-max"' -and $envExampleText -match 'QWEN_MODEL=qwen-max') "Agent and provider use qwen-max consistently"
$webSource = (Get-Content -Raw -Encoding UTF8 (Join-Path $projectRoot "web\server.js")) + (Get-Content -Raw -Encoding UTF8 (Join-Path $projectRoot "docker-compose.yml"))
Check ($webSource -notmatch 'OCTOBUS_ANALYZE_URL|capsets/security-review/connect') "Web source has no direct OctoBus audit endpoint"

if ($failures.Count -gt 0) {
    Write-Host "Local verification failed: $($failures.Count) check(s)." -ForegroundColor Red
    exit 1
}

Write-Host "LOCAL_VERIFICATION_OK" -ForegroundColor Green
