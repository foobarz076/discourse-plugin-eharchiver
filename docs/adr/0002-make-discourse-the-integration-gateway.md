# ADR-0002: Make Discourse the Integration Gateway

- Status: Accepted (retrospective)
- Recorded: 2026-07-24
- Original decision date: No later than 2026-07-24

## 中文摘要

浏览器和普通用户只与 Discourse 通信，由插件把论坛身份、主题和权限转换成
受限任务后再提交给 Daemon。这样无需暴露 Daemon 凭据或另建用户权限系统，
代价是插件需要维护本地状态和服务端代理接口。

## Context

Discourse is authoritative for users, sessions, staff status, groups,
categories, topics, posts, uploads, and the administrator interface. The daemon
is authoritative for archive execution but has no reason to understand
Discourse browser sessions or expose its credentials to clients.

A browser-to-daemon API would require a second public authentication and
authorization surface. It would also expose daemon reachability and make it
harder to apply current forum policy consistently.

## Decision

All browser and user-facing integration flows pass through Discourse:

- logged-in users submit, inspect, and cancel tasks through plugin routes;
- administrators inspect and retry tasks through the Discourse plugin
  dashboard;
- the plugin applies current Discourse visibility and policy before contacting
  the daemon;
- final images and PDFs are stored as normal Discourse uploads;
- browser clients never receive daemon API credentials and do not call daemon
  endpoints directly.

The daemon may call only the narrow, signed webhook endpoint used to deliver
task snapshots.

## Rationale

Discourse can make policy decisions using current user and topic state without
duplicating identity data. It also provides the existing UI, upload storage,
notification channels, and authorization model.

## Consequences

### Positive

- There is one user authentication and authorization boundary.
- Daemon credentials remain server-only.
- Existing Discourse visibility, upload, and administrator controls remain
  authoritative.
- Users and administrators do not need a separate web application.

### Negative

- The plugin must persist a local view of remote execution.
- Discourse availability affects task submission and result publication.
- Server-side routes and serializers must remain compatible with the plugin UI
  and integrations.

## Alternatives considered

The following are retrospective inferences:

- expose the daemon directly to authenticated browsers;
- build a separate daemon dashboard with its own users and permissions;
- let the daemon publish results directly into Discourse.

Each alternative duplicates forum policy or grants the daemon more authority
than its execution role requires.

## Evidence

- [`config/routes.rb`](../../config/routes.rb)
- [`app/controllers/eharchiver/tasks_controller.rb`](../../app/controllers/eharchiver/tasks_controller.rb)
- [`app/controllers/eharchiver/admin/tasks_controller.rb`](../../app/controllers/eharchiver/admin/tasks_controller.rb)
- [`admin/assets/javascripts/discourse/`](../../admin/assets/javascripts/discourse/)

## Related decisions

- [ADR-0001](0001-separate-discourse-plugin-and-archive-daemon.md)
- [ADR-0003](0003-persist-local-task-snapshots.md)
- [ADR-0005](0005-use-task-capabilities-and-separate-secrets.md)
