$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$composeFile = Join-Path $projectRoot "agent-compose.yml"

if (-not (Get-Command agent-compose -ErrorAction SilentlyContinue)) {
    throw "未找到 agent-compose 命令，请先安装并启动 daemon。"
}

& agent-compose --file $composeFile config
if ($LASTEXITCODE -ne 0) { throw "项目配置校验失败。" }

& agent-compose --file $composeFile up
if ($LASTEXITCODE -ne 0) { throw "项目应用失败。" }

& agent-compose --file $composeFile run assistant --prompt "只回复：MVP_OK"
if ($LASTEXITCODE -ne 0) { throw "Agent 冒烟测试失败。" }

