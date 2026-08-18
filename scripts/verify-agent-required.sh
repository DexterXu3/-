#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"

daemon="qwen-agent-mvp-daemon"
restart_daemon() {
  docker start "$daemon" >/dev/null 2>&1 || true
}
trap restart_daemon EXIT

docker stop "$daemon" >/dev/null
payload='{"requestId":"audit-agent-required","filename":"required.js","language":"javascript","code":"const ok = true;"}'
web_username="$(docker exec qwen-agent-mvp-web printenv WEB_USERNAME)"
web_password="$(docker exec qwen-agent-mvp-web printenv WEB_PASSWORD)"
status="$(curl --silent --output /tmp/agent-required-response.json --write-out '%{http_code}' --user "$web_username:$web_password" -H 'Content-Type: application/json' --data-binary "$payload" http://127.0.0.1:3000/api/audit || true)"

if [[ "$status" != "502" ]]; then
  printf 'Expected HTTP 502 while Agent Compose was stopped, got %s\n' "$status" >&2
  exit 1
fi

grep -q 'Agent 审计链路不可用' /tmp/agent-required-response.json
restart_daemon
trap - EXIT
printf 'AGENT_REQUIRED_OK\n'
