# 最终交付说明

## 交付状态

- 中文 Web UI 已完成，可粘贴或上传 JavaScript/TypeScript，并通过 Agent 主链路生成结构化审计报告。
- OctoBus 已通过 Service → Instance → Capset 暴露 `AnalyzeSnippet` 能力。
- Web 只调用 Agent Compose；Agent 经 Skill 与 OctoBus 能力链路调用审计服务，报告包含可查询的 `projectId` 和 `runId`。
- 所有外部容器镜像均固定为服务器已验证的 SHA-256 digest，不使用 `latest`。
- Web 启用 Basic 登录、限流、单任务并发、输入限制、Agent 超时和安全响应头。
- agent-compose daemon、OctoBus 和 Web UI 支持 Docker Compose 启动与自动恢复。
- 云端 Web、daemon 和 OctoBus 端口仅绑定回环地址，远程访问使用 SSH 隧道。
- 面试官使用独立 `examiner` 账号和 SSH 公钥登录，不能读取 `.env` 与 `data`。
- 提供 SQL 注入、路径穿越和综合漏洞等可重复测试样例。

## 最终验证

- 代码安全规则测试：13 项通过。
- Web、结构化输出、安全控制与反旁路测试：14 项通过。
- 云端完整主链路：`LINUX_VERIFICATION_OK`。
- Agent 必需性/禁止旁路：`AGENT_REQUIRED_OK`。
- 最新成功 Agent Run：`b8b5c47f656c`，状态 `RUN_STATUS_SUCCEEDED`，耗时 15867 ms。
- 未登录访问 Web：HTTP 401。
- `examiner` 读取 `.env` 与进入 `data`：均被拒绝。
- 提交文件密钥检查：通过，输出 `SECRET_CHECK_OK`。
- Git diff 格式检查：通过。

## 上传范围

GitHub/ZIP 应包含源码、配置模板、规则知识、部署说明、测试样例和面试官访问说明。

以下内容禁止上传：

- `.env` 或任何真实 API Key
- `data/` 运行数据库及备份
- `verification-output/` 本地验证输出
- `.git/` 本地版本库内部文件
- 私钥、日志、缓存和临时构建文件

## 面试前最后动作

1. 保持 ECS 和百炼计费正常。
2. 运行 `sudo bash scripts/verify-linux.sh`，确认 `LINUX_VERIFICATION_OK`。
3. 由面试官使用 `examiner@47.243.196.218` 验证密钥登录。
4. 通过 SSH 隧道访问 Web UI，不开放公网 3000、7411、9000。
5. 面试结束后删除 SSH `0.0.0.0/0` 临时安全组规则。
