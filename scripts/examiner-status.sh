#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' '=== Containers ==='
docker ps --filter name=octobus-dev --filter name=qwen-agent-mvp-daemon --filter name=qwen-agent-mvp-web \
  --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'

printf '%s\n' '=== Agent Compose project ==='
docker exec qwen-agent-mvp-daemon agent-compose --file /data/work/agent-compose.yml config

printf '%s\n' '=== Agent Compose scheduler ==='
docker exec qwen-agent-mvp-daemon agent-compose --file /data/work/agent-compose.yml scheduler ls --verbose

printf '%s\n' '=== OctoBus status ==='
docker exec octobus-dev octobus status

printf '%s\n' '=== OctoBus authorized method ==='
docker exec octobus-dev octobus capset list-methods security-review

printf '%s\n' 'EXAMINER_STATUS_OK'
