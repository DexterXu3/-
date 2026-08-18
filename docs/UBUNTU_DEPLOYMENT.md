# Ubuntu 服务器部署手册

## 目标环境

- Ubuntu 22.04 或 24.04 LTS，建议 2 核 4 GB 起步；系统盘建议 40 GB 以上。
- 一台仅供本项目使用的服务器，具备公网出站访问能力。
- 普通 sudo 用户；禁止使用 root 直接远程登录。
- Docker Engine 与 Compose plugin。

## 1. 安全初始化

在云厂商安全组中仅开放 SSH。推荐把 SSH 来源限制为面试者或管理员的固定公网 IP，不开放 7411 和 9000。服务器上的两个服务已经绑定 `127.0.0.1`，如需远程演示，使用 SSH 隧道：

```bash
ssh -L 3000:127.0.0.1:3000 <user>@<server-ip>
```

登录服务器后更新系统，并安装 Docker 官方版本。将部署用户加入 `docker` 组后需重新登录：

```bash
sudo apt update
sudo apt upgrade -y
sudo apt install -y ca-certificates curl git nodejs
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker "$USER"
```

建议同时完成 SSH 加固：使用密钥登录、关闭密码登录、关闭 root 登录，并启用云厂商防火墙或 UFW。修改 SSH 配置前保留一个已登录会话，避免把自己锁在服务器外。

## 2. 获取代码和配置密钥

私有仓库可以使用 Git 拉取，也可以把项目 ZIP 上传后解压到部署目录。以 Git 为例：

```bash
git clone <github-repository-url> qwen-agent-mvp
cd qwen-agent-mvp
cp .env.example .env
chmod 600 .env
```

ZIP 方式需确保解压后项目根目录直接包含 `docker-compose.yml`，不要把 `.env`、`data/` 或私钥打包进 ZIP。

编辑 `.env`，替换 `DASHSCOPE_API_KEY`，并将 `WEB_PASSWORD` 设置为至少 16 位的随机密码。不要把 Key 或密码写入命令行、聊天记录、截图或 Git。确认忽略规则：

```bash
git check-ignore .env
```

预期输出为 `.env`。

## 3. 启动完整服务栈

```bash
docker volume create octobus-data
chmod +x octobus/code-security/bin/code-security.js scripts/*.sh
docker compose pull
docker compose up -d --build
bash scripts/setup-octobus.sh
docker compose ps
docker exec qwen-agent-mvp-daemon agent-compose --file /data/work/agent-compose.yml config
docker exec qwen-agent-mvp-daemon agent-compose --file /data/work/agent-compose.yml up
```

配置成功时会显示 `qwen-agent-mvp` 项目和 `assistant` Agent 已创建或更新。
Web UI 同时启动并绑定服务器回环地址 `127.0.0.1:3000`。远程演示时通过 SSH 隧道访问：

```bash
ssh -L 3000:127.0.0.1:3000 <user>@<server-ip>
```

## 4. 部署 OctoBus 能力

`docker-compose.yml` 会启动官方 OctoBus 容器，将扫描器源码以只读方式挂载到 `/opt/code-security`，并使用 `octobus-data` 外部卷保存服务目录和审计记录。首次启动后执行：

```bash
bash scripts/setup-octobus.sh
```

该脚本可重复执行，会创建或更新 Service、Instance 和 Capset。最终输出应包含 `AnalyzeSnippet` 与 `OCTOBUS_SETUP_OK`。

## 5. 验收

```bash
sudo bash scripts/verify-linux.sh
```

最终成功标志为：

```text
LINUX_VERIFICATION_OK
```

验收失败时先看容器状态和日志：

```bash
docker compose ps
docker logs --tail 100 qwen-agent-mvp-daemon
docker logs --tail 100 octobus-dev
```

## 6. 运行与回滚

日常更新：

```bash
git pull --ff-only
docker compose pull
docker compose up -d
docker exec qwen-agent-mvp-daemon agent-compose --file /data/work/agent-compose.yml up
sudo bash scripts/verify-linux.sh
```

停止本项目：

```bash
docker compose down
```

`data/` 保存 agent-compose 本地状态，升级或轮换 Key 前应先备份。不要提交该目录。若 Key 曾出现在日志或终端记录中，应在阿里云控制台立即轮换。

## 上线检查表

- 安全组未开放 3000、7411、9000，只允许受控 SSH。
- `.env` 权限为 600，且 `git check-ignore .env` 成功。
- OctoBus、agent-compose 和 Web UI 均设置了重启策略。
- `security-review` 只暴露 `AnalyzeSnippet`。
- 完整验收输出 `LINUX_VERIFICATION_OK`。
- 截图、日志和公开仓库不含 Key、Token、请求正文或服务器敏感信息。
