# Project Structure

## English

### Purpose and repository boundary

`discourse-eharchiver` is the Discourse-facing half of EH Archiver. It owns
authorization, task submission, local task snapshots, user and administrator
notifications, artifact verification, and publishing results into topics.

The companion `discourse-plugin-eharchiver-daemon` service owns gallery
credentials, E-Hentai/ExHentai access, archive spending, downloads, conversion,
artifact production, and durable execution state. Browser clients communicate
with Discourse; they do not receive daemon credentials or call the daemon
directly.

### Directory map

```text
discourse-plugin-eharchiver/
├── admin/assets/javascripts/discourse/
│   ├── components/                 # Task-dashboard rows
│   ├── controllers/                # Filtering, polling, pagination, retry
│   ├── routes/                     # Dashboard data loading
│   └── templates/                  # Administrator task dashboard
├── app/
│   ├── controllers/eharchiver/
│   │   ├── admin/                  # Administrator task list and retry API
│   │   ├── tasks_controller.rb     # Submit, inspect, and cancel tasks
│   │   └── webhooks_controller.rb  # Signed daemon status callbacks
│   ├── jobs/
│   │   ├── regular/                # Mention, publication, and notification jobs
│   │   └── scheduled/              # Polling reconciliation
│   ├── models/eharchiver/          # Local task snapshot and lifecycle rules
│   ├── serializers/eharchiver/     # JSON representation of local tasks
│   └── services/eharchiver/        # Administrator retry workflow
├── assets/
│   ├── javascripts/discourse/      # Admin route registration and navigation
│   └── stylesheets/                # Dashboard styles
├── config/
│   ├── locales/                    # English and Simplified Chinese strings
│   ├── routes.rb                   # `/eharchiver` server routes
│   └── settings.yml                # Site settings and permission policy
├── db/
│   ├── fixtures/                   # Managed Bot account
│   └── migrate/                    # Local task and retry schema
├── lib/eharchiver/
│   ├── artifact_reply.rb           # Artifact validation, upload, and topic update
│   ├── bot_user.rb                 # Bot account lifecycle
│   ├── daemon_client.rb            # Authenticated server-to-server HTTP client
│   ├── failure_notifier.rb         # User PM, administrator PM, and Chat fallback
│   ├── gallery_url.rb              # Strict gallery URL canonicalization
│   ├── mention_trigger.rb          # Public-post Bot mention trigger
│   ├── task_authorization.rb       # Short-lived HS256 task authorization
│   ├── task_policy.rb              # Category, group, quality, and GP policy
│   └── task_submitter.rb           # Idempotent local creation and daemon submission
├── spec/                           # Ruby request, library, and system tests
├── docs/                           # Project, deployment, and user documentation
└── plugin.rb                       # Plugin metadata, hooks, and initialization
```

### Runtime flow

1. An authorized user creates a regular post in a public topic, mentions the
   managed Bot, and includes one or more supported gallery links.
2. The `post_created` hook queues a background job. The job rechecks the post,
   extracts unique eligible links, and applies category, group, quality, and GP
   policy.
3. Discourse creates a local task with a stable UUID and signs a short-lived
   HS256 authorization. The authorization binds the UUID, requester, topic,
   canonical gallery URL, quality, GP limits, and conversion options.
4. `DaemonClient` authenticates with a separate API key and submits the
   authorization to `POST /v1/tasks`.
5. The daemon validates the authorization, persists its own task state, and
   performs the download and artifact build outside the Discourse process.
6. Signed webhooks update Discourse promptly. The scheduled poller also
   reconciles active tasks, so a missed callback does not permanently strand a
   local snapshot.
7. When the daemon reports `ready`, a Discourse job streams the artifact ZIP,
   checks its task-level SHA-256, validates the strict manifest, and verifies
   every included file's size and SHA-256.
8. Discourse uploads converted images in manifest order and uploads the PDF
   when it satisfies site upload policy. The Bot publishes one reply, then the
   system user updates the topic title and appends trusted namespaced tags.

### Task state mapping

| Layer | States or stages | Meaning |
| --- | --- | --- |
| Plugin submission | `submitting` | Local task exists and submission is in progress |
| Plugin recovery | `submission_unknown` / Confirming | Submission may have succeeded, so polling reconciles by UUID |
| Daemon | `queued` | Accepted and waiting for a worker |
| Daemon | `downloading` | Download/conversion work is running |
| Daemon | `ready` | Verified artifact metadata is available |
| Plugin dashboard | Publishing | Daemon is ready, but the Bot reply is not yet recorded |
| Plugin dashboard | Completed | The Bot reply was published |
| Terminal | `failed` or `cancelled` | No further execution is expected |

Daemon snapshots contain a monotonically increasing `status_version`.
Discourse ignores older or repeated versions, making webhook delivery and
polling reconciliation idempotent.

### Data ownership

| Data | Owner | Storage |
| --- | --- | --- |
| Users, topics, source posts, result posts | Discourse | Discourse database |
| Local task snapshots and retry links | Plugin | `eharchiver_tasks` in the Discourse database |
| Gallery cookies and account access | Daemon | Daemon-only secret file |
| Execution, replay, and spend-audit state | Daemon | Daemon SQLite databases |
| Downloaded archives and published artifact ZIPs | Daemon | Daemon durable storage |
| Final uploaded images and PDFs | Discourse | Normal Discourse upload storage |

The plugin never stores gallery cookies. The daemon never receives a Discourse
session cookie or broad Discourse API key.

### HTTP surfaces

The plugin mounts these server endpoints under `/eharchiver`:

| Method and path | Caller | Responsibility |
| --- | --- | --- |
| `POST /tasks.json` | Logged-in Discourse user or integration | Authorize and submit a task |
| `GET /tasks/{task_id}.json` | Requester or staff | Return and, if active, refresh a local snapshot |
| `POST /tasks/{task_id}/cancel.json` | Requester or staff | Cancel work that has not started downloading |
| `POST /webhooks/task-status` | Daemon | Deliver an HMAC-signed task snapshot |
| `GET /admin/tasks.json` | Administrator | List local task snapshots |
| `POST /admin/tasks/{task_id}/retry.json` | Administrator | Reauthorize and create a linked retry |

The daemon exposes `/health` plus authenticated `/v1/tasks` submission, status,
cancellation, and artifact-download endpoints.

### Security and policy boundaries

- Daemon API, task-signing, and webhook-signing secrets are separate values of
  at least 32 bytes.
- Task JWTs expire after at most ten minutes and are not stored in the plugin
  database.
- Plugin policy can narrow user permissions, but it cannot relax daemon hard
  limits for original or paid downloads.
- Supported gallery URLs must use HTTPS, an exact supported host, and the
  canonical `/g/{gid}/{token}/` shape without query strings or fragments.
- Artifacts are treated as untrusted input until ZIP safety, manifest identity,
  file inventory, size, and SHA-256 checks all pass.
- Normal Discourse upload extensions, size limits, tag limits, and category/tag
  permissions remain authoritative.

### Current implementation note

The site setting `eharchiver_trigger_mode` is defined, but the current
`MentionTrigger` does not consult it. The implemented end-user trigger is the
Bot mention flow. Do not rely on `eharchiver_trigger_mode` to disable mention
submissions; disable the plugin or restrict the allowed groups/categories
instead.

---

## 中文

### 项目职责与仓库边界

`discourse-eharchiver` 是 EH Archiver 面向 Discourse 的一半。它负责授权、提交
任务、保存本地任务快照、向用户和管理员发送通知、验证 Artifact，以及把结果
发布到主题中。

配套的 `discourse-plugin-eharchiver-daemon` 服务负责保存画廊凭据、访问
E-Hentai/ExHentai、控制归档消费、执行下载和转换、生成 Artifact，并持久化
执行状态。浏览器客户端只与 Discourse 通信；它们既不会获得 daemon 凭据，也
不会直接调用 daemon。

### 目录结构

```text
discourse-plugin-eharchiver/
├── admin/assets/javascripts/discourse/
│   ├── components/                 # 任务看板行组件
│   ├── controllers/                # 筛选、轮询、分页和重试
│   ├── routes/                     # 加载看板数据
│   └── templates/                  # 管理员任务看板
├── app/
│   ├── controllers/eharchiver/
│   │   ├── admin/                  # 管理员任务列表与重试 API
│   │   ├── tasks_controller.rb     # 提交、查看与取消任务
│   │   └── webhooks_controller.rb  # Daemon 签名状态回调
│   ├── jobs/
│   │   ├── regular/                # 提及、发布与通知任务
│   │   └── scheduled/              # 轮询对账
│   ├── models/eharchiver/          # 本地任务快照与生命周期规则
│   ├── serializers/eharchiver/     # 本地任务的 JSON 表示
│   └── services/eharchiver/        # 管理员重试流程
├── assets/
│   ├── javascripts/discourse/      # 管理路由与导航注册
│   └── stylesheets/                # 看板样式
├── config/
│   ├── locales/                    # 英文与简体中文字符串
│   ├── routes.rb                   # `/eharchiver` 服务端路由
│   └── settings.yml                # 站点设置与权限策略
├── db/
│   ├── fixtures/                   # 托管的 Bot 帐号
│   └── migrate/                    # 本地任务和重试数据结构
├── lib/eharchiver/
│   ├── artifact_reply.rb           # Artifact 验证、上传与主题更新
│   ├── bot_user.rb                 # Bot 帐号生命周期
│   ├── daemon_client.rb            # 经过认证的服务端 HTTP 客户端
│   ├── failure_notifier.rb         # 用户私信、管理员私信与 Chat 回退
│   ├── gallery_url.rb              # 严格的画廊 URL 规范化
│   ├── mention_trigger.rb          # 公开帖子中的 Bot 提及触发器
│   ├── task_authorization.rb       # 短效 HS256 任务授权
│   ├── task_policy.rb              # 分类、用户组、质量与 GP 策略
│   └── task_submitter.rb           # 幂等的本地创建与 daemon 提交
├── spec/                           # Ruby 请求、库与系统测试
├── docs/                           # 项目、部署与用户文档
└── plugin.rb                       # 插件元数据、Hook 与初始化
```

### 运行流程

1. 获得授权的用户在公开主题中创建普通帖子，提及托管的 Bot，并附上一个或多个
   受支持的画廊链接。
2. `post_created` Hook 将后台任务加入队列。后台任务会重新检查帖子、提取不重复
   的有效链接，并应用分类、用户组、质量和 GP 策略。
3. Discourse 使用稳定 UUID 创建本地任务，并签发一个短效 HS256 授权。授权会
   绑定 UUID、请求用户、主题、规范化画廊 URL、质量、GP 限制和转换选项。
4. `DaemonClient` 使用独立的 API Key 认证，并把授权提交到
   `POST /v1/tasks`。
5. Daemon 验证授权、持久化自己的任务状态，并在 Discourse 进程之外执行下载
   和 Artifact 构建。
6. 签名 Webhook 会及时更新 Discourse；定时轮询器也会对活动任务进行对账，
   因此一次丢失的回调不会让本地快照永久卡住。
7. Daemon 报告 `ready` 后，Discourse 后台任务会流式下载 Artifact ZIP，检查
   任务级 SHA-256、验证严格 Manifest，并核对每个文件的大小和 SHA-256。
8. Discourse 按 Manifest 顺序上传转换后的图片，并在符合站点上传策略时上传
   PDF。Bot 发布一条回复，随后系统用户更新主题标题并追加可信的命名空间标签。

### 任务状态映射

| 层级 | 状态或阶段 | 含义 |
| --- | --- | --- |
| 插件提交 | `submitting` | 本地任务已创建，正在提交 |
| 插件恢复 | `submission_unknown` / 确认中 | 提交可能已经成功，按 UUID 轮询对账 |
| Daemon | `queued` | 已接受，等待 Worker |
| Daemon | `downloading` | 正在执行下载或转换 |
| Daemon | `ready` | 已有经过校验的 Artifact 元数据 |
| 插件看板 | 发布中 | Daemon 已就绪，但尚未记录 Bot 回复 |
| 插件看板 | 已完成 | Bot 回复已经发布 |
| 终止状态 | `failed` 或 `cancelled` | 不再继续执行 |

Daemon 快照包含单调递增的 `status_version`。Discourse 会忽略旧版本或重复版本，
从而让 Webhook 投递和轮询对账保持幂等。

### 数据归属

| 数据 | 责任方 | 存储位置 |
| --- | --- | --- |
| 用户、主题、来源帖子、结果帖子 | Discourse | Discourse 数据库 |
| 本地任务快照与重试关系 | 插件 | Discourse 数据库中的 `eharchiver_tasks` |
| 画廊 Cookie 与帐号访问 | Daemon | 仅 daemon 可读的机密文件 |
| 执行、防重放与消费审计状态 | Daemon | Daemon SQLite 数据库 |
| 下载的归档与已发布 Artifact ZIP | Daemon | Daemon 持久化存储 |
| 最终上传的图片与 PDF | Discourse | 常规 Discourse 上传存储 |

插件绝不会保存画廊 Cookie。Daemon 也不会获得 Discourse 会话 Cookie 或宽泛的
Discourse API Key。

### HTTP 接口

插件在 `/eharchiver` 下挂载以下服务端端点：

| 方法与路径 | 调用方 | 职责 |
| --- | --- | --- |
| `POST /tasks.json` | 已登录的 Discourse 用户或集成 | 授权并提交任务 |
| `GET /tasks/{task_id}.json` | 请求用户或 Staff | 返回本地快照；活动任务还会即时刷新 |
| `POST /tasks/{task_id}/cancel.json` | 请求用户或 Staff | 取消尚未开始下载的任务 |
| `POST /webhooks/task-status` | Daemon | 投递经过 HMAC 签名的任务快照 |
| `GET /admin/tasks.json` | 管理员 | 列出本地任务快照 |
| `POST /admin/tasks/{task_id}/retry.json` | 管理员 | 重新授权并创建关联的重试任务 |

Daemon 提供 `/health`，以及需要认证的 `/v1/tasks` 提交、状态、取消和
Artifact 下载端点。

### 安全与策略边界

- Daemon API、任务签名和 Webhook 签名使用三个独立的机密，每个至少 32 字节。
- 任务 JWT 最长十分钟过期，并且不会保存在插件数据库中。
- 插件策略可以进一步收紧用户权限，但不能放宽 daemon 对原始版本或付费下载
  的硬限制。
- 支持的画廊 URL 必须使用 HTTPS、精确匹配受支持的主机，并采用不带查询参数
  或 Fragment 的规范 `/g/{gid}/{token}/` 形式。
- 在 ZIP 安全性、Manifest 身份、文件清单、大小和 SHA-256 全部通过之前，
  Artifact 始终被视为不可信输入。
- Discourse 自身的上传扩展名、大小限制、标签上限和分类/标签权限始终优先。

### 当前实现说明

站点设置 `eharchiver_trigger_mode` 已经定义，但当前 `MentionTrigger` 并不会
读取它。已经实现的最终用户触发方式是提及 Bot。不要依靠
`eharchiver_trigger_mode` 禁止提及触发；需要停止提交时，请停用插件，或收紧
允许的用户组/分类。
