# Architecture Decision Records

This directory records architectural decisions for `discourse-eharchiver`.

The initial records are retrospective because the first application-specific
implementation entered the repository in one commit. They document decisions
that the current code already enforces; they do not claim that the listed
alternatives were discussed in a contemporaneous design meeting.

## Language policy

English is the normative language of each ADR. Every ADR also contains a short
Chinese summary for maintainers who work primarily in Chinese. The summary is
informative rather than a complete translation. If the two differ, the English
body is authoritative.

中文摘要只帮助快速理解决策及其主要代价，不作为英文正文的逐段翻译。如果两者
存在差异，以英文正文为准。

## Status vocabulary

- `Proposed`: under discussion and not yet binding.
- `Accepted`: approved for new work.
- `Accepted (retrospective)`: already enforced by the implementation and
  recorded after the fact.
- `Deprecated`: retained for history but no longer recommended.
- `Superseded by ADR-NNNN`: replaced by a later decision.

When a retrospective ADR cannot establish the original decision date, it uses
the earliest date by which the repository proves that the decision existed.

## Index

| ADR | Status | Decision |
| --- | --- | --- |
| [0001](0001-separate-discourse-plugin-and-archive-daemon.md) | Accepted (retrospective) | Separate the Discourse plugin from the archive daemon |
| [0002](0002-make-discourse-the-integration-gateway.md) | Accepted (retrospective) | Make Discourse the integration gateway |
| [0003](0003-persist-local-task-snapshots.md) | Accepted (retrospective) | Persist local task snapshots in Discourse |
| [0004](0004-reconcile-status-with-webhooks-and-polling.md) | Accepted (retrospective) | Reconcile status with webhooks and polling |
| [0005](0005-use-task-capabilities-and-separate-secrets.md) | Accepted (retrospective) | Use short-lived task capabilities and separate secrets |
| [0006](0006-verify-artifacts-before-discourse-import.md) | Accepted (retrospective) | Verify artifacts before native Discourse import |
| [0007](0007-design-side-effects-for-idempotency-and-audit.md) | Accepted (retrospective) | Design side effects for idempotency and audit |
| [0008](0008-authorize-gallery-identity-independently-of-upstream-host.md) | Accepted | Authorize gallery identity independently of upstream host |

## Decisions not yet recorded as accepted

The following questions are visible in the current structure but are not settled
enough to describe as accepted architecture:

- whether `eharchiver_trigger_mode` should select explicit Bot mentions,
  automatic link detection, or both;
- whether daemon execution state and Discourse delivery state should become
  separate persisted fields;
- whether `ArtifactReply` should be decomposed into verification, upload, and
  topic-update services.

Create a proposed ADR before implementing any of these changes.

## New ADR checklist

1. Copy the structure of an existing ADR.
2. Use the next four-digit sequence number.
3. Describe one decision, its context, consequences, and rejected alternatives.
4. Link to concrete code, protocol, migration, or operational evidence.
5. Add a short Chinese summary, not a second normative specification.
6. Update this index.
