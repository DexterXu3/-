# 架构设计

## 目标与不可绕过约束

本项目实现一个最小、可验证的 JavaScript/TypeScript 代码安全审计 Agent。产品主入口必须经过 Agent Compose；Web 后端不得直接调用 OctoBus 或扫描器。停止 Agent Compose 后，Web 审计必须失败关闭。

## 唯一产品主链路

```text
用户浏览器
  -> Web 后端
     -> Agent Compose RunService
        -> assistant / Qwen Max
           -> code-security Skill
              -> agent-compose capability proxy
                 -> OctoBus security-review Capset
                    -> code-security-main Instance
                       -> AnalyzeSnippet 确定性扫描器
           <- 规则、行号与代码证据
        <- Qwen 基于证据生成 JSON 报告
     <- runId + 结构化报告
  <- Web 仅负责渲染
```

Web 的 `/api/audit` 首先调用 Agent Compose `ProjectService/ListProjects` 解析项目 ID，再调用 `RunService/RunAgent` 创建持久 Agent Run。请求携带唯一 `requestId`、JSON 输出契约和幂等键。当前 Pi runner 不支持 `outputSchemaJson` 参数，因此契约在 Prompt 中声明，并由 Web 对最终 JSON 的请求 ID、文件名及关键字段执行失败关闭校验。Web 把 `runId` 返回给浏览器作为审计证据。

## 组件职责

- `Web UI`：输入校验、调用 Agent Compose、展示 Agent JSON；不持有模型密钥、不直连 OctoBus、不生成安全结论。
- `agent-compose`：管理项目、Agent Run、隔离沙箱、Qwen 模型代理、Skill 与能力授权。
- `assistant / Qwen Max`：理解审计任务，调用 Skill，基于工具事实生成中文结构化报告。
- `code-security Skill`：规定唯一工具入口、单次调用、证据保真和失败处理。
- `capability proxy`：把临时沙箱令牌与授权 Capset 绑定，禁止 Agent 任意访问后端能力。
- `OctoBus`：管理 Service、Instance、Capset，路由 gRPC 调用并记录审计日志。
- `Code Security Scanner`：返回确定性 Finding；不负责自然语言报告。

## 事实与推断分离

扫描器负责输出 `ruleId`、`severity`、`line`、`evidence` 以及基础规则说明。Agent 必须原样保留规则编号、行号和证据。模型补充的中文解释、影响和修复建议只能建立在同一 Finding 上；其他观察必须进入 `manualReview`，不能伪装成扫描器结论。

前端不再维护风险原因、影响或修复建议字典。最终报告来自 Agent Run 的 `resultJson`，并由 Web 校验 `requestId`、`filename` 和数组结构。

## 能力边界

当前只声明支持 JavaScript、TypeScript 和 Node.js 常见模式。确定性扫描覆盖命令注入、SQL 注入、路径穿越、硬编码凭据和弱哈希，并包含少量跨行变量追踪。当前不支持跨文件污点分析、依赖漏洞分析、完整框架语义或其他语言；未发现问题不等于代码安全。

## 可验证性

- Web 单元测试断言所有审计请求只发往 Agent Compose，URL 中不得出现 OctoBus。
- Web 单元测试断言 Agent Compose 不可用时审计失败。
- Linux 验收使用唯一 `requestId` 调用 Web，核验 `runId`、链路元数据及真实 Finding。
- OctoBus 日志必须同时存在 Agent gRPC 成功记录。
- `verify-agent-required.sh` 会暂时停止 Agent Compose，确认 Web 返回 502，再恢复 daemon。
- 模型目录、Agent 引用和 `.env.example` 全部统一为 `qwen-max`。

## 安全边界

3000、7411 和 9000 只绑定服务器回环地址，远程演示使用 SSH 隧道。DashScope Key 仅由 daemon 读取。Docker Socket 是 Agent Compose 创建隔离 sandbox 所需的高权限接口，当前作为专用 MVP 主机的已知残余风险记录，不能将 daemon 暴露公网。
