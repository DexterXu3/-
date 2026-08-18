# 安全边界与凭据管理

## 凭据

- 真实 DashScope Key 只保存在本地 `.env`，该文件被 Git 忽略。
- 仓库只提交 `.env.example`，不得填写真实 Key。
- Qwen Key 由 agent-compose daemon 使用，不注入 Agent 沙箱。
- OctoBus Capset 当前仅绑定本机回环端口，未配置公网访问。
- Agent 使用 agent-compose 生成的临时沙箱令牌访问 capability proxy，令牌不得输出到日志或报告。

## 最小权限

- Agent 仅授权 `local/security-review`。
- Capset 仅包含 `AnalyzeSnippet`。
- 扫描服务只处理请求中的代码文本，不读取任意宿主机路径。
- 项目目录以只读方式挂载到 daemon 工作目录。
- agent-compose 和 OctoBus 的宿主端口均绑定 `127.0.0.1`。
- Web 仅绑定宿主机 `127.0.0.1:3000`，通过 SSH 隧道访问，不向公网暴露未配置 TLS 的 HTTP 服务。
- Web 使用 Basic 登录，密码只存放在 `.env`；同时启用按来源地址限流、单任务并发、输入大小限制和调用超时。

## Docker Socket 的边界与剩余风险

Agent Compose 的 Docker sandbox driver 需要创建和回收隔离 Guest 容器，因此 daemon 挂载 Docker Socket。这是一项高权限能力，不能把只读挂载错误描述为安全隔离。本项目采用以下补偿控制：

- Docker Socket 只挂载给 Agent Compose daemon，Web、OctoBus 和 Agent Guest 均不挂载。
- daemon、OctoBus 和 Web 的宿主端口都只绑定回环地址。
- Agent 只获得 `local/security-review` Capset；项目源码在 daemon 中只读挂载，真实密钥不进入 Guest。
- 云主机作为该考核项目的单用途实例，不与其他生产工作负载混用。
- 面试官账户不能读取 `.env` 和运行数据目录。

剩余风险是：daemon 一旦被完全攻陷，Docker Socket 可能导致宿主机级影响。生产化改进方向是经过兼容性验证后迁移到 rootless 容器运行时或最小 API 白名单 Socket Proxy；本次 MVP 不声称已彻底消除该风险。

## 日志

OctoBus 访问日志记录协议、Capset、Service、Instance、方法、状态码和耗时，不记录请求正文、响应正文、Authorization 或 Token。公开日志或截图前仍应人工复核。

## 提交前检查

运行：

```powershell
.\scripts\check-secrets.ps1
```

脚本只扫描 Git 跟踪候选文件，跳过 `.env`、运行数据和 `.git`。发现疑似 Key 时返回非零状态。它是防误提交措施，不能替代阿里云控制台轮换和专业 Secret Scanner。

## 已知事项

开发过程中使用过的 DashScope Key 曾存在于工作区旧配置文件中。旧副本已删除，但 Key 本身应在最终公开仓库或服务器交付前于阿里云控制台轮换。
