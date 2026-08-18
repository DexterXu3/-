$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$patterns = @(
    'sk-[A-Za-z0-9_-]{12,}',
    '(?i)(DASHSCOPE|OPENAI|LLM)_API_KEY\s*=\s*["''](?!replace-|example-|\$\{|<)[^"'']{12,}["'']',
    '(?i)authorization\s*[:=]\s*bearer\s+[A-Za-z0-9._-]{12,}'
)

$ignoredSegments = @("\.git\", "\data\", "\node_modules\", "\verification-output\")
$ignoredNames = @(".env", ".env.local")
$findings = [System.Collections.Generic.List[string]]::new()

Get-ChildItem -LiteralPath $projectRoot -Recurse -Force -File | ForEach-Object {
    $file = $_
    if ($ignoredNames -contains $file.Name) { return }
    foreach ($segment in $ignoredSegments) {
        if ($file.FullName.Contains($segment)) { return }
    }
    $content = Get-Content -Raw -Encoding UTF8 -LiteralPath $file.FullName -ErrorAction SilentlyContinue
    foreach ($pattern in $patterns) {
        if ($content -match $pattern) {
            $findings.Add($file.FullName.Substring($projectRoot.Length + 1))
            break
        }
    }
}

if ($findings.Count -gt 0) {
    Write-Host "Potential secrets found:" -ForegroundColor Red
    $findings | Sort-Object -Unique | ForEach-Object { Write-Host "- $_" }
    exit 1
}

Write-Host "SECRET_CHECK_OK" -ForegroundColor Green
