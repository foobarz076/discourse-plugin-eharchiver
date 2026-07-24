# ADR-0005: Use Task Capabilities and Separate Secrets

- Status: Accepted (retrospective)
- Recorded: 2026-07-24
- Original decision date: No later than 2026-07-24

## 中文摘要

API Key 证明“调用者是插件”，短效 JWT 限定“这个任务可以做什么”，Webhook
Secret 验证“状态由 Daemon 发出”。三种信任关系使用独立密钥，降低单一密钥
泄漏的影响范围，同时增加了部署配置和密钥轮换成本。

## Context

The plugin and daemon exchange three different kinds of authority:

1. permission to call the daemon API;
2. permission to execute one task with specific user, topic, quality,
   conversion, and spending limits;
3. permission to update Discourse with a daemon task snapshot.

One shared bearer secret would make these authorities interchangeable. A broad
Discourse API key would also grant the daemon unrelated forum permissions.

## Decision

Use three independent secrets:

- `eharchiver_daemon_api_key` authenticates server-to-server daemon requests;
- `eharchiver_task_signing_secret` signs a short-lived HS256 JWT for each task;
- `eharchiver_webhook_signing_secret` authenticates daemon callbacks over the
  exact timestamp and raw body.

The task JWT binds:

- protocol version and stable task UUID;
- issuer, audience, requester, and topic;
- canonical gallery URL and requested quality;
- maximum GP cost and minimum remaining balance;
- conversion options;
- issue and expiry times.

Task JWTs expire after at most ten minutes and are not persisted in the plugin
database. Configured secrets must contain at least 32 bytes.

## Rationale

The API key identifies the calling service, while the JWT delegates only the
authority required for a particular task. A separate webhook secret prevents a
daemon API credential from automatically authorizing inbound Discourse state
changes.

## Consequences

### Positive

- A task token cannot authorize unrelated work.
- Spending and conversion policy is cryptographically bound to the task.
- The daemon needs no Discourse session or broad administrator API key.
- Compromise of one secret does not automatically grant every integration
  capability.

### Negative

- Operators must generate, distribute, and rotate three matching secrets.
- Clock skew affects JWT expiry and webhook timestamp validation.
- Protocol claim changes require coordinated plugin and daemon updates.
- HS256 requires both services to possess the task-signing secret.

## Alternatives considered

The following are retrospective inferences:

- reuse one secret for API, task, and webhook authentication;
- send unsigned task policy in a normal JSON request;
- give the daemon a Discourse administrator API key;
- use asymmetric task signatures.

Asymmetric signatures could further reduce daemon authority, but the current
two-service deployment uses the simpler shared-secret model.

## Evidence

- [`config/settings.yml`](../../config/settings.yml)
- [`lib/eharchiver/task_authorization.rb`](../../lib/eharchiver/task_authorization.rb)
- [`lib/eharchiver/daemon_client.rb`](../../lib/eharchiver/daemon_client.rb)
- [`app/controllers/eharchiver/webhooks_controller.rb`](../../app/controllers/eharchiver/webhooks_controller.rb)

## Related decisions

- [ADR-0001](0001-separate-discourse-plugin-and-archive-daemon.md)
- [ADR-0002](0002-make-discourse-the-integration-gateway.md)
- [ADR-0004](0004-reconcile-status-with-webhooks-and-polling.md)
