#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"

failures=0
check() {
  if "$@"; then
    printf '[PASS] %s\n' "$check_message"
  else
    printf '[FAIL] %s\n' "$check_message" >&2
    failures=$((failures + 1))
  fi
}

printf '1/8 Checking containers\n'
running="$(docker ps --format '{{.Names}}')"
check_message='agent-compose daemon is running'
check grep -qx 'qwen-agent-mvp-daemon' <<<"$running"
check_message='OctoBus daemon is running'
check grep -qx 'octobus-dev' <<<"$running"
check_message='Web UI is running'
check grep -qx 'qwen-agent-mvp-web' <<<"$running"

printf '2/8 Running deterministic rule tests\n'
check_message='code security rule tests pass'
check node --test octobus/code-security/test/analyzer.test.js

printf '3/8 Validating the Agent project\n'
check_message='agent-compose project is valid'
check docker exec qwen-agent-mvp-daemon agent-compose --file /data/work/agent-compose.yml config
schedulers="$(docker exec qwen-agent-mvp-daemon agent-compose --file /data/work/agent-compose.yml scheduler ls --verbose 2>&1 || true)"
check_message='weekly Agent scheduler is enabled'
check grep -Eq 'weekly-agent-health.*cron.*true' <<<"$schedulers"

printf '4/8 Checking OctoBus resources\n'
status="$(docker exec octobus-dev octobus status 2>&1 || true)"
check_message='OctoBus status is OK'
check grep -Eq '"status"[[:space:]]*:[[:space:]]*"ok"' <<<"$status"
methods="$(docker exec octobus-dev octobus capset list-methods security-review 2>&1 || true)"
check_message='security-review exposes AnalyzeSnippet'
check grep -q 'AnalyzeSnippet' <<<"$methods"

printf '5/8 Calling the capability through Connect RPC\n'
payload="$(node -e 'const fs=require("fs"); const code=fs.readFileSync(process.argv[1],"utf8"); process.stdout.write(JSON.stringify({filename:"vulnerable-route.js",language:"javascript",code}));' samples/vulnerable-route.js)"
result="$(curl --fail --silent --show-error \
  -H 'Content-Type: application/json' \
  --data-binary "$payload" \
  http://127.0.0.1:9000/capsets/security-review/connect/code-security-main/codesecurity.v1.CodeSecurityService/AnalyzeSnippet)"
check_message='sample reports HARDCODED_SECRET'
check grep -q 'HARDCODED_SECRET' <<<"$result"
check_message='sample reports CMD_INJECTION'
check grep -q 'CMD_INJECTION' <<<"$result"

printf '6/8 Checking the Web-to-Agent end-to-end chain\n'
web_health="$(curl --fail --silent --show-error http://127.0.0.1:3000/api/health)"
check_message='Web UI declares the Agent Compose audit path'
check grep -q '"auditPath":"agent-compose"' <<<"$web_health"
request_id="audit-e2e-$(date +%s)"
web_username="$(docker exec qwen-agent-mvp-web printenv WEB_USERNAME)"
web_password="$(docker exec qwen-agent-mvp-web printenv WEB_PASSWORD)"
grpc_before="$(docker exec octobus-dev octobus logs --capset security-review --limit 500 2>&1 | grep -Ec '"protocol":"grpc".*"grpc_code":"OK"' || true)"
web_payload="$(node -e 'const fs=require("fs"); const code=fs.readFileSync(process.argv[1],"utf8"); process.stdout.write(JSON.stringify({requestId:process.argv[2],filename:"vulnerable-route.js",language:"javascript",code}));' samples/vulnerable-route.js "$request_id")"
web_result="$(curl --fail --silent --show-error --user "$web_username:$web_password" -H 'Content-Type: application/json' --data-binary "$web_payload" http://127.0.0.1:3000/api/audit)"
check_message='Web report preserves the end-to-end request ID'
check grep -q "\"requestId\":\"$request_id\"" <<<"$web_result"
check_message='Web report contains a persistent Agent Run ID'
check grep -Eq '"runId":"[^\"]+"' <<<"$web_result"
check_message='Web report contains the Agent Compose Project ID'
check grep -Eq '"projectId":"[^\"]+"' <<<"$web_result"
check_message='Web report proves the Agent-Skill-OctoBus path'
check grep -q '"web":"agent-compose".*"skill":"code-security".*"capability":"OctoBus/security-review/AnalyzeSnippet"' <<<"$web_result"
check_message='Web report contains verified OctoBus evidence provenance'
check node -e 'const p=JSON.parse(process.argv[1]).toolEvidence||{}; if(p.provider!=="octobus" || p.capset!=="local/security-review" || p.method!=="codesecurity.v1.CodeSecurityService/AnalyzeSnippet" || !/^[a-f0-9]{64}$/.test(p.evidenceDigest||"")) process.exit(1)' "$web_result"
check_message='Agent report preserves OctoBus findings'
check grep -q 'HARDCODED_SECRET' <<<"$web_result"
check_message='Agent report preserves all sample findings'
check grep -q 'CMD_INJECTION' <<<"$web_result"

run_id="$(node -e 'const r=JSON.parse(process.argv[1]); process.stdout.write(r.runId || "")' "$web_result")"
project_id="$(node -e 'const r=JSON.parse(process.argv[1]); process.stdout.write(r.projectId || "")' "$web_result")"
run_result="$(curl --fail --silent --show-error -H 'Content-Type: application/json' -H 'Connect-Protocol-Version: 1' --data-binary "{\"projectId\":\"$project_id\",\"runId\":\"$run_id\"}" http://127.0.0.1:7411/agentcompose.v2.RunService/GetRun)"
check_message='GetRun resolves the exact persistent Agent run'
check node -e 'const r=JSON.parse(process.argv[1]).run; if(!r || r.summary.runId!==process.argv[2] || ![3,"RUN_STATUS_SUCCEEDED"].includes(r.summary.status)) process.exit(1)' "$run_result" "$run_id"
check_message='The persisted Agent prompt contains the same request ID'
check node -e 'const r=JSON.parse(process.argv[1]).run; if(!r?.prompt?.includes(process.argv[2])) process.exit(1)' "$run_result" "$request_id"
check_message='The persisted Agent output contains the same request ID and findings'
check node -e 'const r=JSON.parse(process.argv[1]).run; const out=`${r?.output||""}\n${r?.resultJson||""}`; if(!out.includes(process.argv[2]) || !out.includes("HARDCODED_SECRET") || !out.includes("CMD_INJECTION")) process.exit(1)' "$run_result" "$request_id"
check_message='Agent findings exactly preserve OctoBus rule, line, and evidence tuples'
check node -e 'const tool=JSON.parse(process.argv[1]); const agent=JSON.parse(process.argv[2]); const pick=x=>(x.findings||[]).map(f=>[f.ruleId,f.line,f.evidence]).sort(); if(JSON.stringify(pick(tool))!==JSON.stringify(pick(agent))) process.exit(1)' "$result" "$web_result"

printf '7/8 Checking auditable access logs\n'
logs="$(docker exec octobus-dev octobus logs --capset security-review --limit 50 2>&1 || true)"
check_message='Connect RPC success is recorded'
check grep -Eq '"protocol":"connect".*"http_status":200' <<<"$logs"
check_message='Agent gRPC success is recorded'
check grep -Eq '"protocol":"grpc".*"grpc_code":"OK"' <<<"$logs"
grpc_after="$(docker exec octobus-dev octobus logs --capset security-review --limit 500 2>&1 | grep -Ec '"protocol":"grpc".*"grpc_code":"OK"' || true)"
check_message='This Web request produced a new Agent-to-OctoBus gRPC call'
check test "$grpc_after" -gt "$grpc_before"

printf '8/8 Checking model and bypass invariants\n'
check_message='Agent and provider use qwen-max consistently'
check sh -c "grep -q 'model: default/qwen-max' agent-compose.yml && grep -q '\"default\": \"dashscope/qwen-max\"' models.json && grep -q 'QWEN_MODEL=qwen-max' .env.example"
check_message='Web source has no direct OctoBus audit endpoint'
check sh -c "! grep -R -E 'OCTOBUS_ANALYZE_URL|capsets/security-review/connect' web docker-compose.yml"

if (( failures > 0 )); then
  printf 'Linux verification failed: %d check(s).\n' "$failures" >&2
  exit 1
fi

printf 'LINUX_VERIFICATION_OK\n'
