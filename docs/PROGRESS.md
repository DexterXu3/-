# 项目进度与验证记录

更新时间：2026-08-17

## P0 架构整改（面试复盘后）

- 已删除 Web → OctoBus 直连，Web 现在只调用 Agent Compose `ProjectService` 与 `RunService`。
- 已建立唯一产品主链路：Web → Agent Compose → Qwen Agent → code-security Skill → capability proxy → OctoBus → 扫描器 → Agent JSON 报告。
- Web 报告增加 `requestId` 与持久 `runId`；前端不再使用固定风险字典生成原因、影响和修复建议。
- Agent 最终输出遵循 JSON 契约，Web 对关键字段执行严格校验；工具事实进入 `findings`，非工具观察只能进入 `manualReview`。
- 云端首次 P0 验收发现 Pi runner 不支持 `outputSchemaJson` 参数，已改为 Prompt 声明契约 + Web 失败关闭校验，并增加 Pi 元数据解析回归测试。
- 已把页面能力范围收缩为真实实现的 JavaScript/TypeScript/Node.js，不再宣称泛多语言审计。
- 已增加反旁路测试：Web 测试断言不请求 OctoBus；Agent Compose 不可用时必须失败。
- 已增加云端 `verify-agent-required.sh`，通过停止 daemon 验证 Web 无法绕过 Agent。
- 已统一 `agent-compose.yml`、`models.json`、`.env.example` 和 daemon 默认模型为经工具链验证的 `qwen-max`。
- 已增加 pnpm 依赖锁文件和 GitHub Actions CI。
- 本地扫描器测试 13 项通过，Web/安全控制/反旁路测试 14 项通过，密钥检查通过。
- P0 修复版已部署云端；真实 Web → Agent → Skill → OctoBus → Agent 报告验收输出 `LINUX_VERIFICATION_OK`。
- 停止 Agent Compose 后 Web 返回 502，自动恢复 daemon 后输出 `AGENT_REQUIRED_OK`，证明产品不存在 OctoBus 旁路。
- 已使用 `projectId + runId` 查回本次持久 Run，并验证 Prompt、输出与同一 `requestId` 关联。
- 已逐项核对 Agent 报告和 OctoBus 原始结果的规则编号、行号和代码证据，完全一致。
- 已固定所有外部容器镜像 digest，并在 CI 中禁止重新引入 `latest`。
- Web 已增加 Basic 登录、限流、单任务并发、输入上限、超时和安全响应头；未登录访问返回 401。

## 已完成

- agent-compose daemon 通过 Docker 运行，本机入口为 `127.0.0.1:7411`。
- Pi Agent 使用 Qwen Max 完成模型调用和 OctoBus 工具编排。
- OctoBus daemon 运行正常，本机入口为 `127.0.0.1:9000`。
- 创建只读代码安全服务 `code-security`，运行模式为 on-demand。
- 创建 Instance `code-security-main`。
- 创建 Capset `security-review`，绑定 `AnalyzeSnippet` 方法。
- Connect RPC 与 MCP 均完成真实调用并写入 OctoBus 访问日志。
- 已知漏洞样例定位结果：
  - 第 4 行：`HARDCODED_SECRET`，高风险。
  - 第 5 行：`CMD_INJECTION`，严重风险。
- 规则与边界测试共 13 项，全部通过；SQL 注入和命令注入均支持“污染输入赋值—危险 API 调用”的跨行模式。
- 一键本地验收覆盖容器、规则、Agent 配置、OctoBus 资源、真实能力调用、审计日志和 Qwen 健康检查，最终输出 `LOCAL_VERIFICATION_OK`。
- Agent 已通过受保护的 capability proxy 调用 OctoBus gRPC，访问日志中有 `grpc_code=OK` 的端到端证据。
- 开发阶段 DashScope Key 已轮换，Agent Compose 缓存 Provider 已同步，完整本地验收再次通过。
- 已补齐 Ubuntu 部署手册、Linux 一键验收脚本和 30 分钟面试演示提纲。
- 已增加 Windows 一条命令代码审计入口；即使模型服务暂时不可用，也可通过 OctoBus 输出中文确定性初筛报告。
- 已完成轻量 Web UI，支持 JavaScript/TypeScript 代码粘贴、文件上传、风险分级和中文结构化 Agent 报告，本地入口为 `127.0.0.1:3000`。
- Web UI、agent-compose 和 OctoBus 使用同一套 Docker Compose 配置，可原样迁移到 Ubuntu。
- Web UI 已修复空态、加载态和结果态重叠，新增“输入校验—OctoBus 扫描—生成报告”三阶段反馈。
- 2026-08-17 百炼计费恢复，完整 8 项本地验收再次输出 `LOCAL_VERIFICATION_OK`。
- 已迁移到阿里云香港 Ubuntu 24.04 服务器，4 vCPU / 8 GiB / 40 GB，云端完整验收输出 `LINUX_VERIFICATION_OK`。
- 云端 OctoBus、agent-compose 和 Web UI 均已配置容器自动重启，3000、7411 和 9000 仅绑定回环地址。
- 已创建普通部署用户 `agentdeploy`，关闭 root、密码与交互式密码 SSH 登录，UFW 入站仅放行 22/tcp。
- 已添加 agent-compose 原生 `weekly-agent-health` cron 触发器，每周一 03:00（Asia/Shanghai）运行，手动验收返回 `SCHEDULE_OK`。
- 已执行 ECS 整机重启验收：约 24 秒后 `agentdeploy` SSH 恢复，三个容器自动启动，scheduler 保留，完整验收再次输出 `LINUX_VERIFICATION_OK`。
- 已补充规则判定条件、200000 字符输入上限、180 字符证据上限及误报/漏报边界。
- 最新交付 ZIP 已由候选人手动上传并更新私有 GitHub 仓库。

## 当前限制

- 检测器是确定性初筛，不是完整数据流 SAST；结果必须结合上下文复核。
- 当前规则覆盖命令注入、SQL 注入、路径穿越、硬编码密钥和弱哈希。
- Qwen 在开放式工具规划中仍可能重复执行相同动作；稳定验收将确定性扫描、Agent 健康检查和真实工具调用分开。
- 周期任务只做最短 Agent 健康检查，避免无人值守时重复工具规划造成额外模型费用。
- GitHub 仓库状态不影响 P0 架构整改；考官 SSH 已使用独立 `examiner` 账号配置。

## 已处理问题

1. 本机 7410 端口已有开发实例：MVP 改用 7411，避免干扰已有环境。
2. Qwen 认证未从模型目录进入默认 Provider：改用 agent-compose 官方 `LLM_API_*` 兼容配置，并最终统一为当前已验证的 `default/qwen-max`。
3. PowerShell JSON 首次把代码字段序列化为错误类型：改为显式字符串和 UTF-8 字节载荷，OctoBus 随后返回 200。
4. Agent 自动工具测试中 Qwen 多轮规划导致上下文持续增长并最终失败：保留为未完成项，不将直接 MCP 调用冒充 Agent 自主调用。
5. 最终 Qwen 回归被百炼账号 `Arrearage` 拒绝：需要在阿里云控制台恢复账号计费状态后才能继续模型侧验证。
6. 计费恢复后，Agent 已成功调用 OctoBus gRPC，但 Qwen 重复执行同一调用；固定调用器增加了同一沙箱、同一输入的缓存去重。
7. Linux 下 OctoBus 服务曾引用容器 `/tmp` 目录，容器重建后返回 503；改为只读稳定挂载和外部数据卷。
8. Windows ZIP 的 CRLF 和可执行位导致 Linux 脚本与 on-demand 入口无法执行；增加 `.gitattributes`、权限检查和部署步骤。
9. 早期模型方案在工具结果回传时出现 `tool` 角色兼容问题；替换为当前 `qwen-max` 后完整工具链路成功。
10. 首个定时审计测试触发重复工具规划，253990 ms 后主动取消；周期任务改为最短健康检查并验收成功。

## 下一步

1. 将本次最终 ZIP 上传并同步私有 GitHub，确认 GitHub Actions 全绿。
2. 按完整 Agent 主链路进行最终面试彩排。
3. 面试结束后收紧 SSH 安全组来源并撤销临时访问权限。
