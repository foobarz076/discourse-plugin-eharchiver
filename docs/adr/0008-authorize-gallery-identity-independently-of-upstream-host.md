# ADR-0008: Authorize Gallery Identity Independently of Upstream Host

- Status: Accepted
- Recorded: 2026-07-24
- Decision date: 2026-07-24

## 中文摘要

获授权的组成员可以使用 daemon 服务帐号归档任何已知的画廊 `gid/token`。
任务 JWT 保留用户提交的规范 URL用于审计，但 URL host 不限制 daemon 的上游
路由；daemon 通过自己的必填配置选择 E-Hentai 或 ExHentai。若未来需要按用户
验证上游可见性，应重新设计凭据和授权边界。

## Context

The plugin authorizes trusted group members to request archive work performed
with the daemon service account. It does not possess or evaluate each user's
E-Hentai or ExHentai session.

The same gallery identity uses the same `gid` and token on the supported hosts.
Requiring the daemon to follow the submitted URL host would couple execution to
URL representation even though upstream access and credentials are explicitly
daemon-owned.

## Decision

- Continue signing and persisting the canonical URL submitted through
  Discourse.
- Define the task's authorized gallery identity as the URL's `gid` and token.
- Do not treat the submitted host as a user-level upstream visibility boundary.
- Allow the daemon to rebuild the effective gallery URL through its required
  deployment-selected upstream host.
- Keep requester, topic, quality, conversion, spending, issue-time, and expiry
  restrictions unchanged.

This does not change the JWT schema. It records the interpretation of the
existing `gallery_url` claim across the plugin/daemon boundary.

## Rationale

The plugin owns Discourse authorization and the daemon owns gallery source
access. The selected policy deliberately grants allowed group members use of
the daemon service account for any known gallery identity, so upstream host
routing belongs with the daemon credential and deployment configuration.

## Consequences

- An E-Hentai URL may be fulfilled through ExHentai, or vice versa, without
  changing the submitted URL stored in Discourse.
- Operators must configure the daemon upstream host and matching Cookie scope.
- The plugin cannot claim that completion proves the requester could personally
  access the submitted upstream URL.
- A future per-user gallery-visibility policy requires a new ADR and a
  user-specific credential or capability mechanism.

## Alternatives considered

- Require exact submitted-host execution. Rejected because host is not an
  accepted authorization boundary for this service-account policy.
- Let the plugin select the daemon upstream host. Rejected because the plugin
  does not own the gallery Cookie or upstream capability.
- Add a new host field to the task JWT. Rejected because routing is
  deployment-owned and must not be relaxed by a task.

## Evidence

- [`lib/eharchiver/gallery_url.rb`](../../lib/eharchiver/gallery_url.rb)
  validates both supported URL hosts.
- [`lib/eharchiver/task_authorization.rb`](../../lib/eharchiver/task_authorization.rb)
  signs the submitted canonical URL.
- The daemon's
  [ADR-0007](../../../discourse-plugin-eharchiver-daemon/docs/adr/0007-route-gallery-access-through-a-configured-upstream-host.md)
  owns effective upstream routing.

## Related decisions

- [ADR-0001](0001-separate-discourse-plugin-and-archive-daemon.md)
- [ADR-0005](0005-use-task-capabilities-and-separate-secrets.md)

## Review triggers

Review this decision if gallery access must be checked against each requester,
the supported hosts stop sharing `gid/token` identity, or Discourse begins to
own gallery credentials.
