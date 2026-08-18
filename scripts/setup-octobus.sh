#!/usr/bin/env bash
set -euo pipefail

docker exec octobus-dev octobus status >/dev/null
docker exec octobus-dev test -f /opt/code-security/service.json
docker exec octobus-dev test -x /opt/code-security/bin/code-security.js
docker exec octobus-dev octobus service import code-security /opt/code-security --source-mode remote

instances="$(docker exec octobus-dev octobus instance list)"
if ! grep -Eq '"ID"[[:space:]]*:[[:space:]]*"code-security-main"' <<<"$instances"; then
  docker exec octobus-dev octobus instance create code-security-main --service code-security
fi

capsets="$(docker exec octobus-dev octobus capset list)"
if ! grep -Eq '"ID"[[:space:]]*:[[:space:]]*"security-review"' <<<"$capsets"; then
  docker exec octobus-dev octobus capset create security-review \
    --name "Security Review" \
    --description "Read-only deterministic code security checks"
fi

bindings="$(docker exec octobus-dev octobus capset list-instances security-review)"
if ! grep -Eq '"InstanceID"[[:space:]]*:[[:space:]]*"code-security-main"' <<<"$bindings"; then
  docker exec octobus-dev octobus capset add-instance security-review code-security-main
fi

catalog="$(docker exec octobus-dev octobus catalog security-review --all --json)"
printf '%s\n' "$catalog"
grep -q 'AnalyzeSnippet' <<<"$catalog"
printf 'OCTOBUS_SETUP_OK\n'
