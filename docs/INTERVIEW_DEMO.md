# 30 分钟面试演示提纲

## 演示目标

用一条完整链路证明三件事：Agent 能调用受控能力、能力返回可复核证据、系统具备最小权限和可审计性。

## 时间安排

### 0–5 分钟：需求与架构

展示 `docs/ARCHITECTURE.md`，说明模型不直接读取宿主文件，也不把推测冒充扫描结论。重点介绍授权链路：Agent → 临时 capability proxy → `security-review` Capset → `AnalyzeSnippet`。

### 5–10 分钟：项目定义与安全边界

展示 `agent-compose.yml`、`skills/code-security/SKILL.md` 和 `docs/SECURITY.md`：

- Agent 只获得一个 Capset。
- Capset 只暴露一个只读方法。
- DashScope Key 留在 daemon，不进入 Agent 沙箱。
- 服务只分析请求中的代码文本，不读取任意宿主路径。

### 10–18 分钟：端到端演示

先运行完整验收：

```bash
sudo bash scripts/verify-linux.sh
```

Windows 本地环境使用：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify-local.ps1
```

解释输出中的四类证据：13 项确定性回归测试、真实持久 `runId`、Agent Run 中的同一 `requestId`，以及 Agent 报告与 OctoBus 原始规则/行号/证据逐项一致。

然后展示一次真实审计，让 Agent 分析 `samples/vulnerable-route.js`。报告应包含规则编号、风险等级、文件、行号、证据、影响和修复建议。

展示 `weekly-agent-health` 原生 cron 触发器及成功运行记录，证明 Agent 不限于手工命令调用。

### 18–23 分钟：审计与故障处理

展示 OctoBus 日志中的 `connect` 200 和 Agent `grpc` OK，说明日志记录协议、方法、状态和耗时，但不记录请求正文或令牌。

说明实际处理过的问题：端口冲突、Provider 配置、PowerShell JSON 编码、模型重复工具调用、Key 轮换后的缓存 Provider。强调每个问题都有可重复验证，而不是只看模型回答。

### 23–27 分钟：边界与改进

主动说明当前是确定性初筛，不是跨文件数据流 SAST；未发现不等于安全。下一步可增加 AST/污点分析、依赖漏洞扫描、结果持久化、指标告警和 CI 安全门禁。

### 27–30 分钟：问答

准备回答：

1. 为什么用 OctoBus：集中做能力注册、最小授权、协议代理和审计。
2. 为什么规则与 LLM 分开：规则结果可复现，LLM 负责解释和编排。
3. 如何防止密钥泄露：`.env` 忽略、daemon 持有、沙箱临时令牌、提交前扫描、泄露即轮换。
4. 如何证明调用真的发生：使用 `projectId + runId` 查回真实 Agent Run，核对相同 `requestId`，并证明本次请求使 OctoBus gRPC 成功日志计数增加；不把页面自报链路当作唯一证据。
5. 如何控制幻觉：要求区分扫描事实与待验证假设，禁止编造工具未返回的发现。

## 演示前检查

- 提前运行一次完整验收。
- 清理终端历史和截图中的敏感信息。
- 准备架构、配置、样例、测试和日志五个页面。
- 可以独立展示确定性扫描器作为组件诊断，但明确它不是产品降级路径；Agent Compose 不可用时 Web 必须失败。
- 不在演示中打开 `.env` 或输出容器完整环境变量。
