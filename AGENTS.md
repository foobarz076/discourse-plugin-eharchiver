# Project Documentation

- Read `docs/project-structure.md` before changing plugin boundaries, task flow,
  persistent state, artifact publication, or the Discourse/daemon
  responsibility split.
- Read `docs/adr/README.md` and the relevant accepted ADRs before changing
  architecture, authorization, task reconciliation, side-effect idempotency, or
  artifact trust rules.
- Use `docs/daemon-deployment.md` when changing the plugin/daemon connection,
  secrets, network assumptions, or administrator-facing deployment guidance.
- Keep `docs/user-guide.md` aligned with user-visible triggers, permissions,
  statuses, retries, notifications, and publication behavior.

# Architecture Decision Check

- Before finishing a change, decide whether it introduces, reverses, or
  materially changes a long-lived architectural constraint.
- An ADR is normally required for changes to component responsibilities, trust
  or security boundaries, the cross-repository protocol, persistent state and
  ownership, failure or reconciliation semantics, irreversible side effects,
  or scaling and deployment invariants.
- An ADR is normally not required for a bug fix that restores documented
  behavior, an internal refactor with no contract change, routine dependency or
  documentation maintenance, or implementation work already covered by an
  accepted ADR.
- When a decision is required, add a proposed ADR or supersede the relevant
  accepted ADR under `docs/adr/`. If the shared Discourse/daemon contract
  changes, also inspect the daemon repository's ADRs and update or
  cross-reference every affected record.
- In the final handoff, state whether an ADR was added, changed, or judged
  unnecessary, with a brief reason.

# Change Handoff

- Before the final response, inspect Git status in every project changed during
  the task.
- Tell the user whether validated, cohesive changes remain uncommitted and
  whether they should be committed now. Name each affected project.
- Do not stage or commit unless the user explicitly requests it.
- If no commit is needed because the task was read-only or all changes are
  already committed, say so explicitly.
