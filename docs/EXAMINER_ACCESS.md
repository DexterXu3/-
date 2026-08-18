# 面试官访问与验证说明

## 访问参数

- 服务器公网 IP：`47.243.196.218`
- SSH 端口：`22`
- SSH 用户名：`examiner`
- 身份认证：仅使用面试官持有的 SSH 私钥；服务器已安装对应公钥
- Web UI：仅绑定服务器本机 `127.0.0.1:3000`，通过 SSH 隧道访问

> 请勿使用 `root` 或密码登录，也不要将私钥发送给候选人。服务器安全组在面试期间允许 SSH 接入；Web、agent-compose daemon 和 OctoBus 端口不直接暴露公网。

## 第一步：确认 SSH 登录

在面试官电脑的终端中执行（如果私钥不是系统默认密钥，请增加 `-i` 参数）：

```bash
ssh examiner@47.243.196.218
```

指定私钥的示例：

```bash
ssh -i "/path/to/examiner-private-key" examiner@47.243.196.218
```

首次连接可能询问是否信任服务器指纹。确认 IP 无误后输入 `yes`。登录成功后执行：

```bash
whoami
```

预期输出为 `examiner`。

## 第二步：建立 Web UI 安全隧道

在面试官电脑上另开一个终端窗口并保持窗口运行：

```bash
ssh -N -L 3001:127.0.0.1:3000 examiner@47.243.196.218
```

指定私钥的示例：

```bash
ssh -i "/path/to/examiner-private-key" -N -L 3001:127.0.0.1:3000 examiner@47.243.196.218
```

随后在面试官电脑的浏览器中打开：

```text
http://127.0.0.1:3001
```

浏览器随后显示登录框：用户名为 `examiner`，Web 密码由候选人通过单独的安全渠道提供。该密码不是 SSH 密码，也不是 DashScope Key。

这里的 `127.0.0.1:3001` 是面试官电脑上的临时入口，流量经加密 SSH 隧道转发到服务器 Web UI。关闭隧道终端后，该地址即停止访问。

## 第三步：验证项目与服务状态

SSH 登录后，面试官账号不加入 `docker` 组，也不能直接执行任意 Docker 命令。候选人已安装一个 root 持有、内容不可由面试官修改的只读状态入口；面试官可以自行执行：

```bash
sudo /usr/local/bin/qwen-mvp-examiner-status
```

该命令只执行预设的容器状态、Agent 项目与 scheduler、OctoBus status 和 `security-review` 方法查询，成功标志为 `EXAMINER_STATUS_OK`，不能接收任意 Docker 参数。

预期看到 agent-compose daemon、OctoBus 和 Web UI 容器处于运行状态。面试官账号可查看项目和验证材料，但不能读取 `.env`、`data` 目录或其他敏感运行数据。

如需执行完整验收，由候选人在其已授权会话中运行：

```bash
cd /home/agentdeploy/qwen-agent-mvp
sudo bash scripts/verify-linux.sh
```

成功标志为：

```text
LINUX_VERIFICATION_OK
```

## 第四步：Web UI 审计演示

1. 打开 `http://127.0.0.1:3001`。
2. 粘贴或上传代码样例。
3. 点击开始审计。
4. 检查报告是否包含风险规则、等级、文件与行号、代码证据、原因、影响和修复建议。
5. 建议依次测试 `samples/sql-injection-demo.js`、`samples/path-traversal-demo.js` 和 `samples/vulnerable-route.js`。

## 常见问题

### 连接超时

确认服务器 IP、端口和网络正常；确认阿里云安全组仍允许 TCP 22。连接超时通常发生在网络或安全组阶段，尚未进入公钥校验。

### 显示 Permission denied (publickey)

说明已经到达 SSH 服务，但当前私钥与服务器中的面试官公钥不匹配。请确认使用的是与 `CT-interview-xy-access` 公钥配套的私钥。

### 本地 3001 端口已被占用

将命令中的本地端口换为 3002：

```bash
ssh -N -L 3002:127.0.0.1:3000 examiner@47.243.196.218
```

然后访问 `http://127.0.0.1:3002`。

### SSH 能登录但网页打不开

保持隧道窗口打开，检查隧道命令没有报错；再由候选人确认 Web 容器运行状态。无需在安全组中开放 3000 端口。

## 安全说明

- 面试官账号与部署账号分离。
- 面试官不能读取 `.env` 和 `data` 目录。
- 浏览器不会接触 DashScope API Key。
- 3000、7411、9000 均不对公网开放。
- 面试结束后，应删除 SSH `0.0.0.0/0` 临时规则或改回指定公网 IP。
