$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$workspaceRoot = Split-Path -Parent $projectRoot
$envPath = Join-Path $projectRoot ".env"
$legacyEnvPath = Join-Path $workspaceRoot "agent-compose.env"
$modelsPath = Join-Path $projectRoot "models.json"
$dataRoot = Join-Path $projectRoot "data"

function Read-DotEnv([string]$path) {
    $values = @{}
    if (-not (Test-Path -LiteralPath $path)) { return $values }
    foreach ($line in Get-Content -LiteralPath $path -Encoding UTF8) {
        if ($line -match '^\s*([^#][^=]*)=(.*)$') {
            $values[$matches[1].Trim()] = $matches[2].Trim()
        }
    }
    return $values
}

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw "Docker Desktop was not found."
}

$values = Read-DotEnv $envPath
if (-not $values.ContainsKey("DASHSCOPE_API_KEY") -and (Test-Path -LiteralPath $legacyEnvPath)) {
    $legacy = Read-DotEnv $legacyEnvPath
    if ($legacy.ContainsKey("LLM_API_KEY")) {
        $values["DASHSCOPE_API_KEY"] = $legacy["LLM_API_KEY"]
    }
}

if (-not $values.ContainsKey("DASHSCOPE_API_KEY") -or
    [string]::IsNullOrWhiteSpace($values["DASHSCOPE_API_KEY"]) -or
    $values["DASHSCOPE_API_KEY"] -eq "replace-with-your-dashscope-api-key") {
    throw "A valid DASHSCOPE_API_KEY was not found in .env or the legacy environment file."
}

$baseUrl = if ($values.ContainsKey("QWEN_BASE_URL")) {
    $values["QWEN_BASE_URL"]
} else {
    "https://dashscope.aliyuncs.com/compatible-mode/v1"
}

$model = if ($values.ContainsKey("QWEN_MODEL")) { $values["QWEN_MODEL"] } else { "qwen-max" }
$webUsername = if ($values.ContainsKey("WEB_USERNAME")) { $values["WEB_USERNAME"] } else { "examiner" }
$webPassword = if ($values.ContainsKey("WEB_PASSWORD") -and
    $values["WEB_PASSWORD"] -ne "replace-with-a-long-random-password") {
    $values["WEB_PASSWORD"]
} else {
    [Convert]::ToHexString([Security.Cryptography.RandomNumberGenerator]::GetBytes(24)).ToLowerInvariant()
}
$envContent = @(
    "DASHSCOPE_API_KEY=$($values['DASHSCOPE_API_KEY'])"
    "QWEN_BASE_URL=$baseUrl"
    "QWEN_MODEL=$model"
    "WEB_USERNAME=$webUsername"
    "WEB_PASSWORD=$webPassword"
    "WEB_RATE_LIMIT_MAX=10"
    "WEB_RATE_LIMIT_WINDOW_MS=60000"
    "WEB_MAX_CONCURRENT_AUDITS=1"
) -join [Environment]::NewLine
[System.IO.File]::WriteAllText($envPath, $envContent + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))

New-Item -ItemType Directory -Force -Path $dataRoot | Out-Null
Copy-Item -LiteralPath $modelsPath -Destination (Join-Path $dataRoot "models.json") -Force

Push-Location $projectRoot
try {
    docker compose up -d
    if ($LASTEXITCODE -ne 0) { throw "Failed to start the agent-compose service." }

    $ready = $false
    foreach ($attempt in 1..30) {
        try {
            $response = Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:7411/api/version" -TimeoutSec 2
            if ($response.StatusCode -eq 200) { $ready = $true; break }
        } catch {
            # Startup may take a few seconds while the daemon initializes.
        }
        Start-Sleep -Seconds 2
    }
    if (-not $ready) { throw "The agent-compose service did not become ready in time." }

    docker exec qwen-agent-mvp-daemon agent-compose --file /data/work/agent-compose.yml config
    if ($LASTEXITCODE -ne 0) { throw "Agent project validation failed." }

    docker exec qwen-agent-mvp-daemon agent-compose --file /data/work/agent-compose.yml up
    if ($LASTEXITCODE -ne 0) { throw "Agent project creation failed." }

    docker exec qwen-agent-mvp-daemon agent-compose --file /data/work/agent-compose.yml run assistant --prompt "Reply with exactly MVP_OK"
    if ($LASTEXITCODE -ne 0) { throw "The first Agent conversation test failed." }
} finally {
    Pop-Location
}
