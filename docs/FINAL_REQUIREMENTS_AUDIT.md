# 原始题目与 AI 检测反馈终审对照

更新时间：2026-08-17

## 结论

忽略候选人最后手工上传 GitHub 的动作后，当前 MVP 已满足题目关于云端运行、Agent Compose、OctoBus、真实模型调用、非手工触发、最小暴露、可审计证据和安全主题 Agent 的核心要求。上次 AI 检测所依据的 Web→OctoBus 旁路已经删除，当前唯一产品链路为：

```text
Web → Agent Compose → Qwen Agent → code-security Skill
    → capability proxy → OctoBus → scanner → Agent JSON report → Web
```

当前实现仍是 JavaScript/TypeScript 代码片段的确定性安全初筛，不是完整 SAST。Docker Socket 是 Agent Compose Docker sandbox driver 的高权限依赖，已有补偿控制但仍是明确保留的剩余风险。

## 原始题目逐项对照

| 要求 | 状态 | 当前实现与证据 |
|---|---|---|
| 自备云服务器，建议 4 核 8G、Ubuntu 22.04/24.04 | 满足 | 阿里云香港 Ubuntu 24.04，4 vCPU / 8 GiB / 40 GB。 |
| Docker 与 Compose，服务自动恢复 | 满足 | 三服务由 Docker Compose 管理，`restart: always`；已执行 ECS 重启恢复验收。 |
| agent-compose daemon 常驻且可查询项目 | 满足 | daemon 回环映射 7411；配置查询与真实 Run 查询均已验证。 |
| 至少一个自建 Agent 项目 | 满足 | `qwen-agent-mvp` 项目，`assistant` Agent，Docker Guest 沙箱。 |
| 至少一个非手动触发 | 满足 | 原生 `weekly-agent-health` cron，每周一 03:00（Asia/Shanghai）。 |
| 配置模型凭据并真实调用 | 满足 | Qwen Max；最新真实 API Run 状态成功。 |
| Agent Compose 控制面不得匿名公网开放 | 满足 | 7411 只绑定服务器 `127.0.0.1`。 |
| OctoBus daemon 与 status 正常 | 满足 | `octobus status` 返回 OK；容器健康检查通过。 |
| Service→Instance→Capset 三层链路 | 满足 | `code-security` → `code-security-main` → `security-review`。 |
| 至少暴露一个能力方法 | 满足 | `AnalyzeSnippet`。 |
| Agent 必须经 OctoBus 调用能力 | 满足 | Agent 经 Skill 和 capability proxy 调用 OctoBus gRPC；本次调用新增日志。 |
| OctoBus 不对公网开放 | 满足 | 9000 仅绑定回环地址。 |
| 结论有证据，不由模型凭空生成 | 满足 | 工具结果与 Agent 报告的规则、行号、证据逐项比较；不一致则验收失败。 |
| Web 服务端核验 Agent 确实消费工具证据 | 满足 | Web 以 Base64 无损传递源码，避免 Shell 转义改变换行；OctoBus 结果生成 `evidenceDigest`；Web 按输入和报告中的不变量重新计算，摘要不符、未知规则、越界行号或证据不在代码中即失败；首轮失败只允许一次真实 Agent 重试，第二次仍失败则关闭式失败；零发现可正常通过。 |
| 业务闭环完整 | 满足 | Web 接收代码、Agent 取数/判断/生成报告，错误与人工复核边界被保留。 |
| LLM 与脚本分工合理 | 满足 | 确定性规则负责可复现事实；LLM 负责编排、中文解释与结构化报告。 |
| 真实知识与可执行判据 | 满足 | 五条规则均有判定条件、阳性/阴性测试、阈值和误报/漏报说明。 |
| 仓库不含明文密钥 | 满足 | `.env.example` + `.gitignore`；最终包排除 `.env`、data、私钥；`SECRET_CHECK_OK`。 |
| 面试官 SSH 登录与查询 | 满足 | 独立 `examiner` 公钥账号；固定只读状态入口查询容器、项目、scheduler 和 OctoBus 能力。 |

## 上次 AI 检测反馈逐项复核

| 上次问题 | 当前状态 | 防回归措施 |
|---|---|---|
| Web 直接调用 OctoBus | 已修复 | Web 只允许 Agent Compose Project/Run API；CI 搜索并拒绝直连 URL。 |
| 仓库残留直连 OctoBus 的本地审计入口 | 已修复 | 已删除旧 `run-agent.js` 与 `audit-code.ps1`，避免组件诊断入口被误认为产品旁路；Connect RPC 仅保留在明确命名的验收脚本中。 |
| Qwen、Skill、Agent 不参与主功能 | 已修复 | 每次 Web 审计产生真实 Agent Run；停止 daemon 后 Web 返回 502。 |
| 报告由固定规则和前端文案生成 | 已修复 | 前端风险字典删除；报告字段来自 Agent JSON，扫描事实来自 OctoBus。 |
| 测试绕开主链路，只验证 VERIFY_OK | 已修复 | Web 发起真实请求，GetRun 查回同一 Run，并验证本次 OctoBus 新日志。 |
| 缺少 env 模板、ignore，模型冲突 | 已修复 | 文件已补齐；配置统一为 `qwen-max`。 |
| 安装脚本可能恢复旧模型或丢失 Web 登录配置 | 已修复 | Windows 安装脚本默认使用 `qwen-max`，并保留或生成 Web 用户名、随机密码和限流配置。 |
| 多语言宣传大于实现 | 已修复 | UI、API、文档明确只支持 JavaScript/TypeScript；language 参数实际校验。 |
| latest、无锁文件、无 CI | 已修复 | 外部镜像固定 digest；pnpm lockfile；GitHub Actions；CI 禁止 `latest`。 |
| Docker Socket、Web 无认证/限流/TLS | 部分为补偿控制 | Web Basic 登录、限流、超时、单任务并发；仅回环绑定并使用 SSH 隧道加密。Socket 仅给 daemon，仍列为剩余风险。 |
| 端口偏离题目示例值 | 已说明 | 题目端口视为示例；项目保留官方容器内部端口并避开宿主机已有服务，3000/7411/9000 均只绑定回环地址。 |

## 自动验收结果

- 扫描规则测试：13/13。
- Web、结构化输出、安全控制与反旁路测试：14/14。
- 云端完整主链路：`LINUX_VERIFICATION_OK`。
- Agent 必需性：`AGENT_REQUIRED_OK`。
- 最新成功 Run：`b8b5c47f656c`，`RUN_SOURCE_API`，`RUN_STATUS_SUCCEEDED`，15867 ms。
- 未登录 Web：HTTP 401。
- 面试官读取 `.env` 或进入 `data`：拒绝。

## 面试时必须主动说明的边界

1. 当前只覆盖 JavaScript/TypeScript/Node.js 代码片段的五类确定性规则。
2. 没有 AST、跨文件/跨函数污点、依赖漏洞和业务权限分析，不能替代完整 SAST 与人工审计。
3. 风险等级是项目预置分级，不是 CVSS 计算结果。
4. Connect RPC 仅用于扫描器组件诊断，不能冒充 Web 产品链路；产品链路必须经过 Agent。
5. Docker Socket 是已知高权限依赖；现有隔离是补偿控制，不代表风险完全消失。
