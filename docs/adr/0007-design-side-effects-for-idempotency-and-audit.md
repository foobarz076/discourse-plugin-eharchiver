# ADR-0007: Design Side Effects for Idempotency and Audit

- Status: Accepted (retrospective)
- Recorded: 2026-07-24
- Original decision date: No later than 2026-07-24

## 中文摘要

任务提交、结果发帖和通知都必须能安全重试；失败任务重试时创建关联的新记录，
而不是覆盖原记录。这样保留诊断与消费审计并避免重复副作用，代价是需要锁、
唯一索引、自定义字段和清理明确的重试链。

## Context

Discourse background jobs, webhook deliveries, scheduled polling, and
server-to-server requests can all execute more than once. A process may fail
after performing a remote side effect but before recording local completion.

For archive work, duplicate effects are costly:

- duplicate task submission may repeat paid acquisition;
- duplicate publication creates repeated replies and uploads;
- duplicate notifications create noise;
- overwriting a failed task destroys evidence needed for diagnosis.

## Decision

Design submission, publication, notification, and retry workflows for
at-least-once execution:

- assign every task a stable UUID;
- serialize mention-triggered submission with a distributed mutex;
- enforce one original task per source post and canonical gallery URL;
- attach the task UUID to the result post and search that custom field before
  publishing again;
- record the source and reply post IDs on the task;
- deduplicate notifications with a scoped Redis key and finite retention;
- retry a failed task by creating a new task linked through
  `retried_from_task_id`;
- re-evaluate the original requester's current policy before creating a retry;
- allow only one active retry for a failed task through both service locking and
  a partial unique database index.

The failed attempt remains immutable enough to preserve its status, error,
timestamps, result summary, and relationship to later attempts.

## Rationale

Exactly-once delivery cannot be guaranteed across the database, job queue, HTTP
API, uploads, and posts. Idempotent handlers make repetition safe. Linked retry
records preserve operational history and ensure current authorization is used
for new work.

## Consequences

### Positive

- Job and webhook retries do not normally duplicate visible results.
- A transport failure can be reconciled by task UUID.
- Failed attempts remain available for diagnosis and spending audit.
- Retry authorization reflects current groups, categories, quality rights, and
  GP policy.

### Negative

- Correctness depends on locks, unique indexes, and custom-field conventions.
- Retry chains add query and UI complexity.
- Notification deduplication has a retention window rather than permanent
  history.
- Manual API submissions without a source post do not receive the same
  source-post deduplication identity.

## Alternatives considered

The following are retrospective inferences:

- assume background jobs and callbacks execute exactly once;
- update a failed task in place when retrying;
- allow unlimited concurrent retries;
- rely only on application checks without database constraints.

These alternatives risk duplicate side effects, lost history, or races between
processes.

## Evidence

- [`lib/eharchiver/task_submitter.rb`](../../lib/eharchiver/task_submitter.rb)
- [`lib/eharchiver/artifact_reply.rb`](../../lib/eharchiver/artifact_reply.rb)
- [`lib/eharchiver/failure_notifier.rb`](../../lib/eharchiver/failure_notifier.rb)
- [`app/services/eharchiver/task/retry.rb`](../../app/services/eharchiver/task/retry.rb)
- [`db/migrate/20260723170000_add_delivery_to_eharchiver_tasks.rb`](../../db/migrate/20260723170000_add_delivery_to_eharchiver_tasks.rb)
- [`db/migrate/20260723204353_add_retry_tracking_to_eharchiver_tasks.rb`](../../db/migrate/20260723204353_add_retry_tracking_to_eharchiver_tasks.rb)

## Related decisions

- [ADR-0003](0003-persist-local-task-snapshots.md)
- [ADR-0004](0004-reconcile-status-with-webhooks-and-polling.md)
- [ADR-0006](0006-verify-artifacts-before-discourse-import.md)
