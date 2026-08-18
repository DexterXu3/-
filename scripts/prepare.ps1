$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$envPath = Join-Path $projectRoot ".env"
$examplePath = Join-Path $projectRoot ".env.example"

if (-not (Test-Path -LiteralPath $envPath)) {
    Copy-Item -LiteralPath $examplePath -Destination $envPath
    Write-Host "已创建 .env，请填写 DASHSCOPE_API_KEY 后重新运行。"
    exit 1
}

$envLines = Get-Content -LiteralPath $envPath
foreach ($line in $envLines) {
    if ($line -match '^\s*([^#][^=]*)=(.*)$') {
        $name = $matches[1].Trim()
        $value = $matches[2].Trim()
        [Environment]::SetEnvironmentVariable($name, $value, "Process")
    }
}

if ([string]::IsNullOrWhiteSpace($env:DASHSCOPE_API_KEY) -or
    $env:DASHSCOPE_API_KEY -eq "replace-with-your-dashscope-api-key") {
    throw "请先在 .env 中填写有效的 DASHSCOPE_API_KEY。"
}

if ([string]::IsNullOrWhiteSpace($env:QWEN_BASE_URL)) {
    $env:QWEN_BASE_URL = "https://dashscope.aliyuncs.com/compatible-mode/v1"
}

$dataRoot = if ($env:AGENT_COMPOSE_DATA_DIR) {
    $env:AGENT_COMPOSE_DATA_DIR
} else {
    Join-Path $projectRoot "data"
}

New-Item -ItemType Directory -Force -Path $dataRoot | Out-Null
Copy-Item -LiteralPath (Join-Path $projectRoot "models.json") -Destination (Join-Path $dataRoot "models.json") -Force

Write-Host "模型配置已准备到 $dataRoot"
Write-Host "下一步：启动或重启 agent-compose daemon，再运行 scripts/smoke-test.ps1"

