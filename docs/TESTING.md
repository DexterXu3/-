# 测试与验收

## 单元测试

```bash
node --test octobus/code-security/test/analyzer.test.js
node --test web/test/*.test.js
```

扫描器测试覆盖五类阳性规则、跨行 SQL/命令注入、参数化 SQL 与安全代码反例、空输入、超大输入和证据截断。

Web 测试除输入校验外，必须证明：

- Prompt 强制 Agent 调用 `code-security` Skill 和 OctoBus。
- Web 只调用 Agent Compose 的 Project/Run API。
- Web 源码和请求中不存在 OctoBus 直连旁路。
- Agent 报告必须匹配当前 `requestId` 和文件名。
- Agent Compose 不可用时请求失败关闭。

## 云端完整链路

```bash
bash scripts/verify-linux.sh
```

该脚本通过 Web 提交带唯一 ID 的真实漏洞样例，并验证：

1. 三个容器运行。
2. 规则测试通过。
3. Agent 项目配置有效。
4. OctoBus 的 Service → Instance → Capset 资源存在。
5. OctoBus 组件可独立返回确定性 Finding。
6. Web 健康信息声明 `agent-compose` 审计路径。
7. Web 报告返回同一请求 ID、持久 `runId` 和 `projectId`。
8. 使用 `projectId + runId` 调用 Agent Compose `GetRun`，验证本次持久运行成功，且其 Prompt 与输出都包含同一请求 ID。
9. 逐项比较 OctoBus 组件结果和 Agent 最终报告中的规则编号、行号与证据，必须完全一致。
10. 比较调用前后的日志计数，证明本次 Web 请求新增了一次 Agent→OctoBus gRPC 成功调用。
11. Agent、模型目录和环境模板统一使用 `qwen-max`。
12. Web 源码不存在 OctoBus 直连接口。

成功标志为 `LINUX_VERIFICATION_OK`。

## 禁止旁路验收

下面的测试会短暂停止 Agent Compose，确认 Web 审计返回 HTTP 502，然后自动恢复 daemon：

```bash
bash scripts/verify-agent-required.sh
```

成功标志为 `AGENT_REQUIRED_OK`。这项测试证明删除或停止 Agent Compose 后，产品主要功能无法继续工作。
