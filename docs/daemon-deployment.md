# Daemon Deployment Reference for Administrators

## English

### Scope

This guide connects the companion EH Archiver Daemon to this Discourse plugin.
It uses the daemon repository's production Docker Compose path as the baseline.
The daemon repository remains the canonical source for its image, Compose
files, environment examples, and systemd unit.

Keep the Discourse plugin disabled until the daemon is healthy, reachable from
the Discourse server, and configured with matching secrets.

### Production topology

```text
User browser
    |
    v
Discourse + discourse-eharchiver
    |  API key + short-lived signed task
    v
EH Archiver Daemon
    |  daemon-only cookie
    v
E-Hentai / ExHentai

Daemon -- signed status webhook --> Discourse
Discourse -- authenticated polling --> Daemon
Discourse -- authenticated artifact download --> Daemon
```

The daemon should be reachable only from Discourse and operators. Bind it to
loopback or a private network, or place it behind a TLS reverse proxy. Do not
publish port `8765` directly to the public Internet.

### Prerequisites

- A production host with Docker Engine and the Compose v2 plugin.
- A checkout of `discourse-plugin-eharchiver-daemon`.
- A Netscape-format E-Hentai/ExHentai cookie file containing only the cookies
  required by the daemon.
- A private network path between Discourse and the daemon.
- Enough durable storage for SQLite state, downloaded archives, artifacts, and
  the expected task volume.
- `pdf` included in Discourse's `authorized_extensions`.

The current daemon uses SQLite-backed coordination. Run one daemon container
and one Uvicorn process (`--workers 1`). Configure in-process concurrency with
`EHARCHIVER_TASK_WORKERS`; do not scale the Compose service horizontally.

### 1. Prepare the daemon

From the daemon repository:

```sh
cp .env.example.docker .env.docker
mkdir -p docker-data/lib docker-data/cache docker-data/run docker-secrets
chmod 0600 .env.docker
```

Generate three independent secret values. If the daemon virtual environment
already exists:

```sh
venv/bin/python -m eh_archiver.tools.generate_keys
```

Otherwise, create the environment first:

```sh
python3.13 -m venv venv
venv/bin/python -m pip install -r requirements.txt
venv/bin/python -m eh_archiver.tools.generate_keys
```

Never reuse a value across API authentication, task signing, and webhook
signing. Each value must contain at least 32 bytes.

Install the cookie as:

```text
docker-secrets/e-hentai.org_cookies.txt
```

On a native Linux Docker host, make the mounted data writable and the cookie
readable by the image's `10001:10001` user:

```sh
sudo chown -R 10001:10001 docker-data
sudo chown 10001:10001 docker-secrets/e-hentai.org_cookies.txt
chmod 0700 docker-data/lib docker-data/cache docker-data/run
chmod 0400 docker-secrets/e-hentai.org_cookies.txt
```

Docker Desktop can virtualize ownership differently. Verify effective
container access instead of assuming host UID mapping.

### 2. Configure daemon policy

Edit `.env.docker`. At minimum, replace or review:

```dotenv
EHARCHIVER_DAEMON_API_KEY=<independent-secret>
EHARCHIVER_TASK_SIGNING_SECRET=<independent-secret>
EHARCHIVER_DISCOURSE_ISSUER=https://forum.example
EHARCHIVER_COOKIE_FILE=/run/secrets/e-hentai.org_cookies.txt

EHARCHIVER_TASK_AUDIENCE=eharchiver-daemon
EHARCHIVER_TASK_MAX_LIFETIME_SECONDS=600
EHARCHIVER_TASK_WORKERS=2

EHARCHIVER_ALLOW_ORIGINAL=false
EHARCHIVER_MAX_COST_GP=0
EHARCHIVER_MIN_REMAINING_GP=0
```

`EHARCHIVER_DISCOURSE_ISSUER` must exactly match the Discourse base URL used in
task tokens, including scheme and any non-default port.

Start with original and paid downloads disabled. The daemon settings are hard
ceilings: a signed Discourse task cannot override them. Enable either feature
only after reviewing the gallery account, GP budget, reserve, cookie security,
and operator alerting.

To enable callbacks, configure both values together:

```dotenv
EHARCHIVER_WEBHOOK_SIGNING_SECRET=<third-independent-secret>
EHARCHIVER_DISCOURSE_WEBHOOK_URL=https://forum.example/eharchiver/webhooks/task-status
```

If both are omitted, the integration still works through Discourse polling,
but status updates may arrive later.

### 3. Start and verify the daemon

```sh
docker compose up --build -d
docker compose ps
docker compose logs --tail=100 daemon
curl --fail --silent http://127.0.0.1:8765/health
```

Expected health response:

```json
{"status":"ok","protocol":"v1"}
```

The health endpoint proves process liveness. It does not prove cookie validity,
gallery access, Discourse reachability, or matching signing secrets.

### 4. Make the daemon reachable from Discourse

Choose one route:

- **Discourse outside Docker:** use a private host address or a TLS reverse
  proxy that the Discourse host can reach.
- **Discourse in a Launcher container:** attach Discourse and the daemon to the
  same external Docker network. The daemon repository supplies
  `compose.discourse-network.yml`.
- **Separate hosts:** allow only the Discourse host through the firewall and
  terminate TLS before the daemon.

For a shared Docker network:

```sh
docker network create eharchiver-backend
docker compose --env-file .env.docker \
  -f compose.yml \
  -f compose.discourse-network.yml \
  up --build -d
```

After the Discourse container is attached to the same network, its daemon URL
is:

```text
http://eharchiver-daemon:8765
```

Use the same Compose file list for later `up`, `logs`, and `down` commands in
shared-network mode.

### 5. Configure Discourse

Open the `EH Archiver` site-settings category and configure these mappings:

| Discourse setting | Daemon value | Requirement |
| --- | --- | --- |
| `eharchiver_daemon_url` | Reachable daemon base URL | Server-side route; never a browser-only URL |
| `eharchiver_daemon_api_key` | `EHARCHIVER_DAEMON_API_KEY` | Exact match |
| `eharchiver_task_signing_secret` | `EHARCHIVER_TASK_SIGNING_SECRET` | Exact match, at least 32 bytes |
| `eharchiver_webhook_signing_secret` | `EHARCHIVER_WEBHOOK_SIGNING_SECRET` | Exact match when callbacks are enabled |
| Discourse base URL | `EHARCHIVER_DISCOURSE_ISSUER` | Exact scheme, host, and port |
| Webhook endpoint | `EHARCHIVER_DISCOURSE_WEBHOOK_URL` | `{base_url}/eharchiver/webhooks/task-status` |

Then review:

- request, original-download, paid-download, and elevated-spending groups;
- allowed categories;
- standard and elevated per-download GP limits;
- minimum remaining GP;
- default archive quality;
- artifact ZIP limit, Discourse upload limit, and `pdf` extension;
- Bot username;
- administrator PM recipient or Chat channel for operational failures;
- PDF width, JPEG quality, and whether untrusted uploader comments are included.

Plugin policy should be equal to or stricter than daemon policy. For example,
setting a non-zero Discourse GP grant has no effect while
`EHARCHIVER_MAX_COST_GP=0`.

Enable `eharchiver_enabled` only after these values are complete. Enabling the
plugin creates or repairs the managed Bot account.

Current behavior caveat: `eharchiver_trigger_mode` is not consulted by the
implemented mention trigger. Restrict request groups/categories or disable the
plugin when mention submissions must stop.

### 6. End-to-end validation

Use a public test topic in an allowed category and an account in the request
group:

```text
@eharchiver https://e-hentai.org/g/123456/0123456789/
```

Use a real permitted gallery URL in place of the example. Validate all of the
following:

1. A local task appears under **Admin → Plugins → discourse-eharchiver →
   Tasks**.
2. Its stage advances from Submitting/Queued to Downloading.
3. The daemon logs contain the same task UUID.
4. The Bot publishes metadata, ordered converted images, and normally a PDF.
5. The topic title and trusted namespaced tags are updated.
6. The task becomes Completed and links to the result post.

Perform the first production validation with a free, resampled archive. Enable
original or paid work only after this path succeeds.

### 7. Operations, backup, and recovery

Useful commands:

```sh
docker compose logs -f daemon
docker compose restart daemon
docker compose build --pull daemon
docker compose up -d daemon
docker compose down
```

`docker compose down` preserves the bind-mounted directories. Do not add `-v`
unless deleting runtime state is intentional.

Back up at least:

- `docker-data/lib/` while the daemon is stopped, for a consistent SQLite and
  durable-artifact snapshot;
- `.env.docker`, separately and as a secret;
- the gallery cookie file, through the organization's secret-management
  process.

`docker-data/cache/` is rebuildable. The runtime lock under `docker-data/run/`
is not a backup artifact.

Before an upgrade, keep a restorable backup, review changes to
`.env.example.docker`, rebuild the image, inspect startup recovery and
spend-audit warnings, and repeat the free/resampled validation.

Treat any `uncertain` spend-audit record as an operator reconciliation event.
Do not retry paid work blindly.

### systemd alternative

For a non-container Linux deployment, use the daemon repository's
`systemd/eharchiver.service` and `systemd/eharchiver.env.example` as the
starting point. Replace every `/path/to/eharhiver_daemon` placeholder, create a
dedicated `eharchiver` user, install Python 3.13 dependencies and qpdf, keep
`--workers 1`, and verify the service hardening against the actual filesystem
layout before enabling it.

---

## 中文

### 范围

本指南用于把配套的 EH Archiver Daemon 连接到这个 Discourse 插件。这里以
daemon 仓库的生产 Docker Compose 路径为基准。Daemon 仓库仍然是镜像、
Compose 文件、环境变量示例和 systemd Unit 的权威来源。

在 daemon 健康、Discourse 服务器能够访问它、并且双方机密完全匹配之前，请
保持 Discourse 插件停用。

### 生产拓扑

```text
用户浏览器
    |
    v
Discourse + discourse-eharchiver
    |  API Key + 短效签名任务
    v
EH Archiver Daemon
    |  仅 daemon 持有的 Cookie
    v
E-Hentai / ExHentai

Daemon -- 签名状态 Webhook --> Discourse
Discourse -- 认证轮询 --> Daemon
Discourse -- 认证下载 Artifact --> Daemon
```

Daemon 应当只允许 Discourse 和运维人员访问。请将它绑定到 loopback 或私有
网络，或者放在 TLS 反向代理之后。不要把 `8765` 端口直接发布到公网。

### 前置条件

- 安装了 Docker Engine 与 Compose v2 插件的生产主机。
- `discourse-plugin-eharchiver-daemon` 的工作副本。
- Netscape 格式的 E-Hentai/ExHentai Cookie 文件，只包含 daemon 所需的
  Cookie。
- Discourse 与 daemon 之间的私有网络路径。
- 足以保存 SQLite 状态、下载归档、Artifact 和预期任务量的持久化空间。
- Discourse 的 `authorized_extensions` 中包含 `pdf`。

当前 daemon 使用基于 SQLite 的协调机制。只运行一个 daemon 容器和一个
Uvicorn 进程（`--workers 1`）。进程内并发由 `EHARCHIVER_TASK_WORKERS` 控制；
不要横向扩展 Compose 服务。

### 1. 准备 daemon

在 daemon 仓库中执行：

```sh
cp .env.example.docker .env.docker
mkdir -p docker-data/lib docker-data/cache docker-data/run docker-secrets
chmod 0600 .env.docker
```

生成三个相互独立的机密。如果 daemon 虚拟环境已经存在：

```sh
venv/bin/python -m eh_archiver.tools.generate_keys
```

否则先创建环境：

```sh
python3.13 -m venv venv
venv/bin/python -m pip install -r requirements.txt
venv/bin/python -m eh_archiver.tools.generate_keys
```

API 认证、任务签名和 Webhook 签名绝不能复用同一个值。每个值都必须至少包含
32 字节。

把 Cookie 安装为：

```text
docker-secrets/e-hentai.org_cookies.txt
```

在原生 Linux Docker 主机上，使镜像中的 `10001:10001` 用户可以写入挂载数据
并读取 Cookie：

```sh
sudo chown -R 10001:10001 docker-data
sudo chown 10001:10001 docker-secrets/e-hentai.org_cookies.txt
chmod 0700 docker-data/lib docker-data/cache docker-data/run
chmod 0400 docker-secrets/e-hentai.org_cookies.txt
```

Docker Desktop 可能以不同方式虚拟化所有权。请验证容器中的实际访问权限，不要
假定宿主机 UID 映射。

### 2. 配置 daemon 策略

编辑 `.env.docker`。至少替换或检查：

```dotenv
EHARCHIVER_DAEMON_API_KEY=<独立机密>
EHARCHIVER_TASK_SIGNING_SECRET=<独立机密>
EHARCHIVER_DISCOURSE_ISSUER=https://forum.example
EHARCHIVER_COOKIE_FILE=/run/secrets/e-hentai.org_cookies.txt

EHARCHIVER_TASK_AUDIENCE=eharchiver-daemon
EHARCHIVER_TASK_MAX_LIFETIME_SECONDS=600
EHARCHIVER_TASK_WORKERS=2

EHARCHIVER_ALLOW_ORIGINAL=false
EHARCHIVER_MAX_COST_GP=0
EHARCHIVER_MIN_REMAINING_GP=0
```

`EHARCHIVER_DISCOURSE_ISSUER` 必须与任务令牌所用的 Discourse 基础 URL 完全
一致，包括协议和任何非默认端口。

初始状态应禁止原始版本和付费下载。Daemon 设置是硬上限；Discourse 的签名
任务不能覆盖它们。只有在检查画廊帐号、GP 预算、余额保留线、Cookie 安全性和
运维告警之后，才应启用这些功能。

如需启用回调，必须同时配置：

```dotenv
EHARCHIVER_WEBHOOK_SIGNING_SECRET=<第三个独立机密>
EHARCHIVER_DISCOURSE_WEBHOOK_URL=https://forum.example/eharchiver/webhooks/task-status
```

如果两项都省略，集成仍可通过 Discourse 轮询工作，但状态更新可能较慢。

### 3. 启动并验证 daemon

```sh
docker compose up --build -d
docker compose ps
docker compose logs --tail=100 daemon
curl --fail --silent http://127.0.0.1:8765/health
```

预期健康响应：

```json
{"status":"ok","protocol":"v1"}
```

健康端点只能证明进程存活，不能证明 Cookie 有效、能够访问画廊、能够连接
Discourse，或双方签名机密一致。

### 4. 让 Discourse 能够访问 daemon

选择一种路径：

- **Discourse 位于 Docker 外：** 使用 Discourse 主机可访问的私有主机地址，
  或 TLS 反向代理。
- **Discourse 位于 Launcher 容器中：** 将 Discourse 与 daemon 连接到同一个
  外部 Docker 网络。Daemon 仓库提供 `compose.discourse-network.yml`。
- **分别位于不同主机：** 防火墙只允许 Discourse 主机访问，并在 daemon 前
  终止 TLS。

使用共享 Docker 网络时：

```sh
docker network create eharchiver-backend
docker compose --env-file .env.docker \
  -f compose.yml \
  -f compose.discourse-network.yml \
  up --build -d
```

Discourse 容器连接到同一网络后，daemon URL 为：

```text
http://eharchiver-daemon:8765
```

在共享网络模式下，后续执行 `up`、`logs` 和 `down` 时也应使用相同的 Compose
文件列表。

### 5. 配置 Discourse

打开 `EH Archiver` 站点设置分类，并完成以下映射：

| Discourse 设置 | Daemon 值 | 要求 |
| --- | --- | --- |
| `eharchiver_daemon_url` | Discourse 可访问的 daemon 基础 URL | 必须是服务端路径，不能只是浏览器可达 |
| `eharchiver_daemon_api_key` | `EHARCHIVER_DAEMON_API_KEY` | 完全一致 |
| `eharchiver_task_signing_secret` | `EHARCHIVER_TASK_SIGNING_SECRET` | 完全一致，至少 32 字节 |
| `eharchiver_webhook_signing_secret` | `EHARCHIVER_WEBHOOK_SIGNING_SECRET` | 启用回调时完全一致 |
| Discourse 基础 URL | `EHARCHIVER_DISCOURSE_ISSUER` | 协议、主机和端口完全一致 |
| Webhook 端点 | `EHARCHIVER_DISCOURSE_WEBHOOK_URL` | `{base_url}/eharchiver/webhooks/task-status` |

随后检查：

- 请求、原始版本下载、付费下载和高额度消费用户组；
- 允许的分类；
- 普通与高额度单次 GP 上限；
- 最低剩余 GP；
- 默认归档质量；
- Artifact ZIP 上限、Discourse 上传上限和 `pdf` 扩展名；
- Bot 用户名；
- 接收运行故障的管理员私信帐号或 Chat 频道；
- PDF 宽度、JPEG 品质，以及是否包含不受信任的上传者评论。

插件策略应当与 daemon 一样严格或更加严格。例如，当
`EHARCHIVER_MAX_COST_GP=0` 时，Discourse 中非零的 GP 授权不会生效。

完成所有配置后再启用 `eharchiver_enabled`。启用插件时会创建或修复托管的
Bot 帐号。

当前行为注意事项：`eharchiver_trigger_mode` 尚未被已经实现的提及触发器读取。
需要停止提及提交时，应限制请求用户组/分类，或停用插件。

### 6. 端到端验证

使用允许分类中的公开测试主题，以及属于请求用户组的帐号：

```text
@eharchiver https://e-hentai.org/g/123456/0123456789/
```

请用真实且允许访问的画廊 URL 替换示例。验证以下全部项目：

1. **管理后台 → 插件 → discourse-eharchiver → 任务** 中出现本地任务。
2. 阶段从提交中/排队中推进到下载中。
3. Daemon 日志中出现同一个任务 UUID。
4. Bot 发布元数据、按顺序排列的转换图片，并通常包含 PDF。
5. 主题标题和可信的命名空间标签得到更新。
6. 任务变成已完成，并链接到结果帖子。

第一次生产验证应使用免费、重采样归档。此路径成功后，再启用原始版本或付费
任务。

### 7. 运维、备份与恢复

常用命令：

```sh
docker compose logs -f daemon
docker compose restart daemon
docker compose build --pull daemon
docker compose up -d daemon
docker compose down
```

`docker compose down` 会保留 bind mount 目录。除非明确要删除运行状态，否则
不要添加 `-v`。

至少备份：

- 在 daemon 停止时备份 `docker-data/lib/`，获得一致的 SQLite 和持久化
  Artifact 快照；
- 单独备份 `.env.docker`，并把它作为机密保护；
- 按组织的机密管理流程备份画廊 Cookie 文件。

`docker-data/cache/` 可以重建。`docker-data/run/` 下的运行锁不是备份对象。

升级前，请保留可恢复的备份、检查 `.env.example.docker` 的变化、重新构建
镜像、查看启动恢复和消费审计警告，并再次执行免费/重采样验证。

任何 `uncertain` 消费审计记录都应当由运维人员对账。不要盲目重试付费任务。

### systemd 替代方案

在非容器 Linux 部署中，以 daemon 仓库的 `systemd/eharchiver.service` 和
`systemd/eharchiver.env.example` 为起点。替换所有
`/path/to/eharhiver_daemon` 占位符，创建专用 `eharchiver` 用户，安装
Python 3.13 依赖和 qpdf，保持 `--workers 1`，并根据实际文件系统布局验证
Service 加固设置后再启用。
