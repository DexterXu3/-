# P0 主链路整改验收证据

验收时间：2026-08-17（Asia/Shanghai）

## 整改目标

消除 Web → OctoBus 直连旁路，确保产品唯一链路为：

```text
Web → Agent Compose → Qwen Agent → code-security Skill → OctoBus → 扫描器 → Agent JSON 报告
```

## 本地自动化结果

- 确定性扫描规则：13/13 通过。
- Web、结构化解析、安全控制和反旁路：14/14 通过。
- Web 测试断言请求只访问 Agent Compose，不包含 OctoBus URL。
- Agent Compose 不可用时 Web 审计失败关闭。
- 密钥检查：`SECRET_CHECK_OK`。

## 云端完整链路

执行：

```bash
sudo bash scripts/verify-linux.sh
```

结果：`LINUX_VERIFICATION_OK`。

本次验收确认：

- Web 健康信息声明 `auditPath=agent-compose`。
- Web 返回与请求一致的唯一 `requestId`。
- Web 返回持久 Agent `runId`。
- Web 返回 `projectId`，并通过 Agent Compose `GetRun` 查回完全相同的持久运行记录。
- 持久 Run 的 Prompt 和输出均包含本次唯一 `requestId`。
- 报告链路元数据包含 Agent Compose、`code-security` Skill 和 OctoBus `AnalyzeSnippet`。
- 漏洞样例经 Agent 报告保留 `HARDCODED_SECRET` 与 `CMD_INJECTION`。
- Agent 报告与 OctoBus 原始结果中的规则编号、行号和代码证据逐项完全一致。
- 本次请求前后日志计数增加，证明本次 Web 请求产生了新的 Agent→OctoBus gRPC 成功调用。
- Agent 与模型目录统一为 `qwen-max`。
- Web 源码不存在 OctoBus 直连接口。

成功 Agent Run：

```text
runShortId: b8b5c47f656c
source: RUN_SOURCE_API
status: RUN_STATUS_SUCCEEDED
duration: 15867 ms
projectRevision: 5
```

## 禁止旁路验收

执行：

```bash
sudo bash scripts/verify-agent-required.sh
```

结果：`AGENT_REQUIRED_OK`。

脚本停止 Agent Compose 后，Web `/api/audit` 返回 HTTP 502；脚本随后恢复 daemon。该结果证明停止 Agent Compose 后主要审计功能无法继续，不会降级为 Web 直连 OctoBus。

## 实际问题复盘

首次云端 P0 验收在创建 Run 后立即失败。`GetRun` 证据显示：

```text
structured JSON output is not supported by pi runner
```

修复方式：不再向 Pi runner 传入 `outputSchemaJson`，改为在 Prompt 中声明 JSON 契约，并由 Web 后端严格校验 `requestId`、`filename`、`findings` 和 `manualReview`。同时解析逻辑会跳过 Pi 自身的运行元数据，读取 Agent 最终输出，并兼容 JSON Markdown 围栏。修复后同一云端链路通过。

## 终审加固结果

- Agent Compose、Guest、OctoBus 和 Node 基础镜像均固定到服务器已验证的 SHA-256 digest，不再使用浮动 `latest`。
- Web 增加 Basic 登录、按来源地址限流、单任务并发、输入上限、调用超时和安全响应头。
- 未登录访问 Web 返回 HTTP 401。
- 云端 `.env` 权限为 `600 agentdeploy:agentdeploy`；`examiner` 无法读取 `.env`，也无法进入 `data`。
- Docker Socket 的必要性、补偿控制和剩余风险已在 `docs/SECURITY.md` 明确说明，未把风险包装为已彻底消除。
