# Qwen Agent MVP

这是一个最小可运行的 agent-compose 项目：一个中文助手 Agent，通过 agent-compose 的 LLM facade 调用阿里云百炼兼容 OpenAI 的 Qwen 接口。密钥只由 daemon 读取，不写入项目清单，也不进入 Agent 沙箱。

项目提供浏览器代码审计工作台，默认入口为 `http://127.0.0.1:3000`。产品唯一审计链路为 `Web → Agent Compose → Qwen Agent → Skill → OctoBus → 扫描器 → Agent 报告`；Web 不允许直接调用 OctoBus。

## 云端交付访问信息

- 服务器：`47.243.196.218`
- SSH 端口：`22`
- 面试官用户：`examiner`（仅使用已登记公钥登录）
- Web UI：不对公网开放；面试官执行 `ssh -N -L 3001:127.0.0.1:3000 examiner@47.243.196.218` 后访问 `http://127.0.0.1:3001`
- Web 登录用户名：`examiner`；密码由候选人通过安全渠道单独提供
- 只读状态查询：`sudo /usr/local/bin/qwen-mvp-examiner-status`

面试官账号不在 Docker 组，不能读取 `.env` 或 `data`。详细步骤见 `docs/EXAMINER_ACCESS.md`。

## 项目内容

- `agent-compose.yml`：Agent、模型引用和 Docker sandbox 配置。
- `models.json`：daemon 使用的 Qwen Provider 目录。
- `.env.example`：环境变量模板，不包含真实密钥。
- `scripts/prepare.ps1`：准备本地环境和 daemon 模型配置。
- `scripts/smoke-test.ps1`：校验、应用项目并运行最小测试。

## 运行前提

- Docker Desktop 已启动。
- 已安装并启动 agent-compose daemon。
- 可拉取项目清单中按 SHA-256 摘要固定的 Agent Compose、Guest、OctoBus 与 Node 镜像。
- 已开通阿里云百炼并取得 DashScope API Key。

## 1. 配置密钥

在本目录执行：

```powershell
Copy-Item .env.example .env
```

打开 `.env`，填写 `DASHSCOPE_API_KEY`。`.env` 已被 Git 忽略。
同时将 `WEB_PASSWORD` 改成至少 16 位的随机密码。Web 页面会显示浏览器原生登录框，默认用户名为 `examiner`。Web 只绑定服务器回环地址，面试官通过 SSH 隧道访问；SSH 已提供传输加密，因此本 MVP 不把未配置 TLS 的 HTTP 端口暴露到公网。

如果工作区根目录已有旧版 `agent-compose.env`，也可以直接运行下面的一键脚本；它会在不显示密钥的情况下迁移配置。

```powershell
.\scripts\install-and-run.ps1
```

该脚本会启动 Docker 服务、创建 Agent，并完成第一次 `MVP_OK` 对话测试。
MVP daemon 对外使用本机 `127.0.0.1:7411`，以避免干扰已有的 7410 开发实例。

### 端口选择说明

题目示例端口为 Web `46282`、Agent `8000`、OctoBus `8888`，并非协议要求。本项目实际使用
Web `127.0.0.1:3000`、Agent Compose `127.0.0.1:7411 → 容器 7410`、OctoBus
`127.0.0.1:9000`：容器内保留官方服务约定端口，宿主机端口用于避开既有开发服务。三者均只绑定
回环地址，不对公网开放；面试官通过 SSH 隧道访问 Web。若现场要求指定端口，只需调整宿主机映射和
SSH 隧道目标，不应修改容器间的服务发现地址。

## 2. 准备模型目录

```powershell
.\scripts\prepare.ps1
```

脚本默认把 `models.json` 放到本项目的 `data` 目录。如果 daemon 使用其他数据目录，请先设置 `AGENT_COMPOSE_DATA_DIR`。配置变更后需要重启 daemon，因为模型目录只在启动时加载。

启动 daemon 时，要让 `.env` 中的变量进入 daemon 进程环境。若使用 Docker Compose 部署，可将本项目 `.env` 和 `data/models.json` 挂载到 daemon 对应的数据目录。

## 3. 验证 MVP

```powershell
.\scripts\smoke-test.ps1
```

测试会依次校验配置、应用项目，并要求 Agent 只回复 `MVP_OK`。

也可以手动对话：

```powershell
agent-compose --file .\agent-compose.yml run assistant --prompt "帮我制定今天的工作计划"
```

## 常用操作

```powershell
# 查看项目 Agent
agent-compose --file .\agent-compose.yml ls

# 删除项目及其运行中的 sandbox
agent-compose --file .\agent-compose.yml down
```

## MVP 边界

当前已验证单 Agent、中文结构化输出、Qwen Max、Docker 隔离、OctoBus 安全能力和 Web UI。规则范围限定为 JavaScript/TypeScript/Node.js 初筛。持久记忆、多 Agent、完整 SAST、Web 公网发布与集中式可观测性不在当前 MVP 边界内。

## 代码安全能力

项目现已包含一个 OctoBus on-demand 代码安全初筛服务：

```powershell
.\scripts\setup-octobus.ps1
```

它会创建 `code-security` Service、`code-security-main` Instance 和 `security-review` Capset。服务源码位于 `octobus/code-security`，已知漏洞样例位于 `samples/vulnerable-route.js`。

当前完成情况、验证证据与未完成项见 `docs/PROGRESS.md`。

## 一键本地验收

在 Docker Desktop、MVP daemon 和 OctoBus 均已启动时执行：

```powershell
.\scripts\verify-local.ps1
```

脚本会检查容器、规则测试、Agent 配置、OctoBus 三层资源和访问日志。Linux 云端验收还会从 Web 提交真实代码，验证持久 Agent Run、Skill/OctoBus 调用和最终结构化报告。停止 Agent Compose 时 Web 必须失败，不能降级到直连扫描器。

## Web UI

启动或更新网页服务：

```powershell
docker compose up -d --build web
```

浏览器访问：

```text
http://127.0.0.1:3000
```

页面支持 JavaScript/TypeScript 代码粘贴与上传、中文结构化报告、风险分级、行号证据及错误提示。浏览器不接触 DashScope Key；Web 后端只调用 Agent Compose 的 Project/Run API。Agent 在隔离沙箱中通过 `code-security` Skill 与授权 capability proxy 调用 OctoBus，最终报告携带可查询的 `runId`。

Web 还包含 Basic 登录、按来源地址限流、单任务并发、请求体/代码长度限制、120 秒 Agent 超时和安全响应头。健康检查 `/api/health` 不返回凭据且无需登录，以供 Docker 检查服务状态。

## 不可绕过验收

云端执行以下脚本会短暂停止 Agent Compose，确认 Web 返回 HTTP 502，再自动恢复 daemon：

```bash
bash scripts/verify-agent-required.sh
```

成功标志为 `AGENT_REQUIRED_OK`。完整链路与测试说明见 `docs/TESTING.md`。

## 交付文档

- `docs/EXAMINER_ACCESS.md`：面试官 SSH 登录、Web 隧道、验收与故障排查说明。
- `docs/FINAL_RELEASE.md`：最终交付状态、验证结果、上传范围和面试前检查。
- `docs/P0_VERIFICATION.md`：Web→Agent→Skill→OctoBus 完整链路及禁止旁路的云端验收证据。
- `docs/FINAL_REQUIREMENTS_AUDIT.md`：原始题目与上次 AI 检测反馈的最终逐项对照。
- `docs/ARCHITECTURE.md`：组件、数据流、能力边界和可靠性设计。
- `docs/SECURITY.md`：凭据、最小权限、日志与提交前安全检查。
- `docs/TESTING.md`：测试范围和验收方式。
- `docs/RULE_KNOWLEDGE.md`：实际检测条件、阈值、证据来源与误报/漏报边界。
- `docs/PROGRESS.md`：实现进度、问题处理和后续计划。
- `docs/UBUNTU_DEPLOYMENT.md`：Ubuntu 安全部署、验收与回滚步骤。
- `docs/INTERVIEW_DEMO.md`：30 分钟面试演示流程和问答准备。

提交前请执行：

```powershell
.\scripts\check-secrets.ps1
```
