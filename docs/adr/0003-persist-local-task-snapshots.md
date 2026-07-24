# ADR-0003: Persist Local Task Snapshots in Discourse

- Status: Accepted (retrospective)
- Recorded: 2026-07-24
- Original decision date: No later than 2026-07-24

## 中文摘要

Daemon 保有实际执行状态，插件则在 Discourse 数据库保存任务快照、来源帖子、
结果回复和重试关系。它让管理界面、授权和通知不依赖实时访问 Daemon，但需要
明确处理两边暂时不一致的情况。

## Context

Archive tasks outlive the HTTP request that creates them. Discourse must still
answer questions about ownership, visibility, source and result posts,
notifications, and retries even when the daemon is temporarily unavailable.

Treating the daemon as the only readable task store would make the plugin UI
and policy checks dependent on a live cross-service request. Treating
Discourse as the execution store would duplicate worker coordination and spend
audit state.

## Decision

Persist a local task snapshot in `eharchiver_tasks` before submitting work to
the daemon.

The local record owns Discourse-facing data:

- requester, topic, and optional source post;
- canonical gallery URL and authorized task policy;
- the latest accepted daemon status version and result summary;
- the published reply post;
- polling timestamps, error summary, and retry relationships.

The daemon remains authoritative for execution, replay, spending, downloaded
archives, and artifact availability. A stable task UUID correlates both stores.

The dashboard derives a Discourse-facing stage from the daemon status and local
delivery state. In particular, daemon `ready` means `publishing` until a reply
post is recorded, then `completed`.

## Rationale

A local snapshot lets Discourse enforce visibility and render operational state
without exposing the daemon. It also preserves forum-specific audit links and
supports recovery after temporary network failures.

## Consequences

### Positive

- The dashboard and authorization checks use local relational data.
- Source posts, result posts, and retry attempts remain auditable.
- Temporary daemon outages do not erase the last known state.
- Discourse can distinguish artifact readiness from completed publication.

### Negative

- Local and daemon state are eventually consistent rather than transactional.
- Schema migrations are required as delivery and operational needs evolve.
- Reconciliation rules must reject invalid or stale remote snapshots.

## Alternatives considered

The following are retrospective inferences:

- query the daemon for every dashboard or task request;
- store the complete execution state only in Discourse;
- keep task state only in transient background-job arguments.

These options respectively increase runtime coupling, duplicate daemon
responsibility, or lose recoverability.

## Evidence

- [`db/migrate/20250723000000_create_eharchiver_tasks.rb`](../../db/migrate/20250723000000_create_eharchiver_tasks.rb)
- [`db/migrate/20260723170000_add_delivery_to_eharchiver_tasks.rb`](../../db/migrate/20260723170000_add_delivery_to_eharchiver_tasks.rb)
- [`db/migrate/20260723204353_add_retry_tracking_to_eharchiver_tasks.rb`](../../db/migrate/20260723204353_add_retry_tracking_to_eharchiver_tasks.rb)
- [`app/models/eharchiver/task.rb`](../../app/models/eharchiver/task.rb)

## Related decisions

- [ADR-0002](0002-make-discourse-the-integration-gateway.md)
- [ADR-0004](0004-reconcile-status-with-webhooks-and-polling.md)
- [ADR-0007](0007-design-side-effects-for-idempotency-and-audit.md)
