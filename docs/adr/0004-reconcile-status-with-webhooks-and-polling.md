# ADR-0004: Reconcile Status with Webhooks and Polling

- Status: Accepted (retrospective)
- Recorded: 2026-07-24
- Original decision date: No later than 2026-07-24

## 中文摘要

Webhook 提供及时更新，定时轮询修复丢失的回调；单调递增的
`status_version` 防止重复或乱序消息覆盖新状态。提交超时时保留
`submission_unknown`，因为“不知道结果”不能直接等同于“Daemon 未接受”。

## Context

Task status crosses an unreliable network boundary. Webhooks can be delayed,
duplicated, reordered, or lost. Polling alone is slower and creates unnecessary
load. A submission request can also time out after the daemon has already
persisted the task.

The integration therefore cannot assume exactly-once message delivery or infer
task rejection from a transport error.

## Decision

Use both push and pull reconciliation:

- the daemon sends HMAC-signed status webhooks for prompt updates;
- a scheduled Discourse job polls active local tasks to recover missed
  callbacks;
- task snapshots carry a monotonically increasing `status_version`;
- Discourse ignores repeated or older versions and validates task identity
  before applying a snapshot;
- a transport-ambiguous submission becomes `submission_unknown`;
- polling reconciles that UUID until the daemon returns it or the short-lived
  authorization has expired and the daemon still reports it missing.

The poller limits each run and records `last_polled_at` so work is spread across
active tasks.

## Rationale

Webhooks optimize latency while polling provides eventual repair.
Version-based application makes both paths safe to repeat and allows their
messages to arrive in any order. The explicit unknown state prevents duplicate
paid work after a timeout.

## Consequences

### Positive

- A missed callback does not permanently strand a task.
- Duplicate and out-of-order snapshots are harmless.
- Submission timeouts can be reconciled without blindly creating another task.
- Webhook and polling code share one snapshot-validation path.

### Negative

- The system is eventually consistent.
- Polling consumes daemon and Discourse resources.
- Both sides must preserve the meaning and monotonicity of `status_version`.
- Operators must configure webhook signing and polling intervals coherently.

## Alternatives considered

The following are retrospective inferences:

- rely only on webhooks;
- rely only on polling;
- mark every submission timeout as failed and allow immediate resubmission;
- compare status names instead of a daemon-issued version.

These alternatives lose repair, increase latency, risk duplicate work, or make
state ordering ambiguous.

## Evidence

- [`app/controllers/eharchiver/webhooks_controller.rb`](../../app/controllers/eharchiver/webhooks_controller.rb)
- [`app/jobs/scheduled/eharchiver_poll_tasks.rb`](../../app/jobs/scheduled/eharchiver_poll_tasks.rb)
- [`app/models/eharchiver/task.rb`](../../app/models/eharchiver/task.rb)
- [`app/controllers/eharchiver/tasks_controller.rb`](../../app/controllers/eharchiver/tasks_controller.rb)

## Related decisions

- [ADR-0003](0003-persist-local-task-snapshots.md)
- [ADR-0005](0005-use-task-capabilities-and-separate-secrets.md)
- [ADR-0007](0007-design-side-effects-for-idempotency-and-audit.md)
