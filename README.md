# Discourse EH Archiver

A Discourse plugin for authorizing, submitting, and displaying gallery archive
tasks executed by the separate EH Archiver daemon.

## Documentation

- [Project structure](docs/project-structure.md)
- [Architecture decision records](docs/adr/README.md)
- [Daemon deployment reference for administrators](docs/daemon-deployment.md)
- [End-user guide](docs/user-guide.md)

The plugin is disabled by default. Configure its daemon connection, task and
webhook signing secrets, category/group permissions, and GP limits in the
`EH Archiver` site-settings category before enabling it.

## Mention trigger

The plugin creates and manages a bot account with the username configured by
`eharchiver_bot_username`. If that username is already occupied, Discourse adds
a numeric suffix and the plugin stores the resulting username in the setting.
When an authorized user mentions the bot in a public topic, the plugin enqueues
a daemon task for every unique supported gallery link in that post. Mentions
without a supported link are ignored without posting.

The trigger uses Discourse's parsed mentions and cooked links, so mentions or
links inside code and links inside quoted content do not activate it. It also
applies `eharchiver_request_allowed_groups` and
`eharchiver_allowed_categories`, ignores private messages and the bot's own
posts, and stores source-post/task IDs to make submission and reply jobs
idempotent.

When the site default is original quality, requests without an explicit quality
from users outside `eharchiver_original_download_groups` automatically use the
resampled archive. An explicit original-quality request is still rejected for
users without that permission.

When the daemon reports `ready`, the plugin streams the artifact ZIP, verifies
the task-level checksum, validates its strict manifest, and verifies every
entry's size and SHA-256. It uploads the converted images in manifest order and
the PDF, then publishes one Bot reply containing the prepared metadata table,
the ordered images, and PDF attachment. After the reply succeeds, the Discourse
system user updates the topic title from the verified manifest, preferring the
Japanese title and falling back to the original title. The same system-user
revision creates and appends trusted EH tags as namespaced Discourse tags such
as `artist:example-artist`; `tags_low_trust` is never imported. Existing topic
tags are preserved, and the instance's tag limits and category/tag permissions
remain authoritative.

Add `pdf` to Discourse's `authorized_extensions`; normal Discourse upload size
and type policy remains in force. When the generated PDF exceeds
`max_attachment_size_kb`, the reply is still published with its metadata and
ordered images, the PDF upload is skipped, and the requester receives a
deduplicated private message explaining the omission.

Permission failures are privately sent to the requester. Operational failures
go to the administrator configured by
`eharchiver_notification_admin_username`, or to
`eharchiver_notification_chat_channel_id` when the Chat plugin is installed and
the channel is usable; Chat delivery falls back to the administrator PM.

## Task dashboard

Administrators can open **EH Archiver → Tasks** from the plugin configuration
area. The dashboard reads Discourse's local task snapshots and shows the task
stage, requester, source topic or post, gallery, requested quality, creation
time, error summary, and published result. It refreshes every ten seconds and
can filter tasks by active, failed, or completed state.

Failed daemon tasks can be retried from the dashboard. A retry rechecks the
original requester's current category, group, quality, and spending permissions,
then creates a new linked task so the failed attempt remains available for
diagnosis. Only one active retry is allowed for each failed task.

## Communication flow

The plugin exposes server-side endpoints under `/eharchiver`:

- `POST /eharchiver/tasks.json` checks the current user's topic, category,
  original-quality, and GP permissions; stores a local task; signs a short-lived
  HS256 authorization; and submits it to the daemon.
- `GET /eharchiver/tasks/{task_id}.json` returns the local snapshot and refreshes
  an active task from the daemon.
- `POST /eharchiver/tasks/{task_id}/cancel.json` cancels a task that has not begun
  downloading.
- `POST /eharchiver/webhooks/task-status` accepts daemon callbacks signed over
  the exact timestamp and request body.
- `GET /eharchiver/admin/tasks.json` lists local task snapshots for an
  administrator.
- `POST /eharchiver/admin/tasks/{task_id}/retry.json` creates a linked retry for
  a failed task after rechecking authorization.

Daemon callbacks update status promptly. A scheduled reconciliation job polls
active tasks at `eharchiver_status_poll_interval_seconds` so missed callbacks do
not strand the Discourse snapshot. Monotonic `status_version` values make both
paths idempotent and prevent older updates from overwriting newer state.

Set the daemon environment values to match Discourse:

```text
EHARCHIVER_DAEMON_API_KEY          = eharchiver_daemon_api_key
EHARCHIVER_TASK_SIGNING_SECRET     = eharchiver_task_signing_secret
EHARCHIVER_WEBHOOK_SIGNING_SECRET  = eharchiver_webhook_signing_secret
EHARCHIVER_DISCOURSE_ISSUER        = the Discourse base URL
EHARCHIVER_DISCOURSE_WEBHOOK_URL   = https://forum.example/eharchiver/webhooks/task-status
```

The connection secrets are server-only site settings. Task JWTs expire after at
most ten minutes, and no JWT is retained in the plugin database. If submission
times out after the daemon may have accepted it, the task remains
`submission_unknown` so polling can reconcile it by its stable UUID. If the
daemon still reports it missing after the authorization expires, the plugin
marks it failed instead of polling forever.

Credentials for E-Hentai or ExHentai belong to the daemon deployment and must
not be stored in this plugin's site settings.

## License

Discourse EH Archiver is licensed under the MIT License. The complete license
text and preserved copyright notices are in [LICENSE](LICENSE).
