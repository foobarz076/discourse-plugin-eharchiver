# ADR-0001: Separate the Discourse Plugin and the Archive Daemon

- Status: Accepted (retrospective)
- Recorded: 2026-07-24
- Original decision date: No later than 2026-07-24

## 中文摘要

Discourse 插件负责用户、权限、任务编排和结果发布；独立 Daemon 负责画廊
访问、消费、下载与转换。这个边界隔离了长时间任务和敏感 Cookie，但也引入了
跨服务协议、部署及故障恢复成本。

## Context

The integration combines two very different workloads:

- Discourse user, topic, category, group, and upload operations;
- credentialed gallery access, paid archive acquisition, image conversion, and
  PDF production.

Archive acquisition can be slow, resource-intensive, and dependent on native or
Python processing libraries. It also requires gallery credentials that do not
belong in the Discourse database or web process.

## Decision

Implement EH Archiver as two cooperating applications:

- the Discourse plugin owns authorization, task submission, local task
  snapshots, user and administrator notifications, artifact verification, and
  publication into topics;
- the archive daemon owns gallery credentials, source access, spending,
  downloads, conversion, artifact production, and durable execution state.

The plugin communicates with the daemon through a versioned server-to-server
HTTP API. The daemon does not receive direct database access or a broad
Discourse administrator API key.

## Rationale

This boundary keeps long-running and dependency-heavy processing out of
Discourse request processes. It also limits credential exposure and allows the
archive pipeline to be tested, deployed, scaled, and recovered independently
from the forum.

## Consequences

### Positive

- Gallery credentials and spending state remain outside Discourse.
- Archive failures do not directly block Discourse web requests.
- Each application can use a runtime suited to its responsibilities.
- The daemon can be tested independently of Discourse.

### Negative

- Operators must deploy and monitor two applications.
- The integration requires a stable protocol and coordinated configuration.
- Network ambiguity, retries, and cross-service state reconciliation must be
  handled explicitly.

## Alternatives considered

The following are retrospective inferences; the repository does not prove that
they were formally discussed:

- perform download and conversion inside a Discourse background job;
- grant an external worker direct access to the Discourse database;
- let the daemon publish through a broad Discourse administrator API key.

These alternatives would reduce protocol work but weaken isolation or increase
the authority granted to the processing service.

## Evidence

- [`docs/project-structure.md`](../project-structure.md)
- [`lib/eharchiver/daemon_client.rb`](../../lib/eharchiver/daemon_client.rb)
- [`lib/eharchiver/task_submitter.rb`](../../lib/eharchiver/task_submitter.rb)
- [`lib/eharchiver/artifact_reply.rb`](../../lib/eharchiver/artifact_reply.rb)

## Related decisions

- [ADR-0002](0002-make-discourse-the-integration-gateway.md)
- [ADR-0005](0005-use-task-capabilities-and-separate-secrets.md)
- [ADR-0006](0006-verify-artifacts-before-discourse-import.md)
