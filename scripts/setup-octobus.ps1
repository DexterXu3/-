$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$serviceRoot = Join-Path $projectRoot "octobus\code-security"

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw "Docker Desktop was not found."
}

docker exec octobus-dev octobus status | Out-Null
if ($LASTEXITCODE -ne 0) { throw "OctoBus is not available." }

docker exec --user 0 octobus-dev rm -rf /tmp/code-security
if ($LASTEXITCODE -ne 0) { throw "Failed to clear the temporary OctoBus service package." }

docker cp $serviceRoot octobus-dev:/tmp/code-security
if ($LASTEXITCODE -ne 0) { throw "Failed to copy the OctoBus service package." }

docker exec octobus-dev octobus service import code-security /tmp/code-security --source-mode remote
if ($LASTEXITCODE -ne 0) { throw "OctoBus service import failed." }

$instances = (docker exec octobus-dev octobus instance list 2>&1) -join "`n"
if ($instances -notmatch '"ID":\s*"code-security-main"') {
    docker exec octobus-dev octobus instance create code-security-main --service code-security
    if ($LASTEXITCODE -ne 0) { throw "OctoBus instance creation failed." }
}

$capsets = (docker exec octobus-dev octobus capset list 2>&1) -join "`n"
if ($capsets -notmatch '"ID":\s*"security-review"') {
    docker exec octobus-dev octobus capset create security-review --name "Security Review" --description "Read-only deterministic code security checks"
    if ($LASTEXITCODE -ne 0) { throw "OctoBus capset creation failed." }
}

$bindings = (docker exec octobus-dev octobus capset list-instances security-review 2>&1) -join "`n"
if ($bindings -notmatch '"InstanceID":\s*"code-security-main"') {
    docker exec octobus-dev octobus capset add-instance security-review code-security-main
    if ($LASTEXITCODE -ne 0) { throw "OctoBus capset binding failed." }
}

docker exec octobus-dev octobus catalog security-review --all --json
