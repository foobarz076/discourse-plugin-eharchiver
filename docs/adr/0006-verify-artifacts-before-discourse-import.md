# ADR-0006: Verify Artifacts Before Native Discourse Import

- Status: Accepted (retrospective)
- Recorded: 2026-07-24
- Original decision date: No later than 2026-07-24

## 中文摘要

Daemon 交付的是带版本化 Manifest 的 ZIP；插件在导入前检查任务级与逐文件
校验和、文件清单、路径和解压限制。验证后图片与 PDF 进入 Discourse 原生
Upload 系统，以换取更强的完整性和生命周期管理，但发布流程也因此更复杂。

## Context

The daemon produces files outside the Discourse process and storage system.
Even a normally trusted daemon can return an incomplete transfer, corrupted
file, incompatible manifest, excessive archive, or archive entry with an unsafe
path.

Serving permanent daemon artifact URLs would bypass Discourse upload policy,
storage lifecycle, backup, and content rendering. Importing an archive without
verification would extend daemon or transport failures into forum content.

## Decision

Treat every downloaded artifact as untrusted until verified.

The plugin:

- streams the ZIP with a configured total-size limit while calculating its
  SHA-256;
- compares the downloaded size and checksum with the accepted daemon task
  result;
- opens it with `Compression::SafeZipReader` using entry-count,
  uncompressed-size, and compression-ratio limits;
- requires a supported manifest schema and matching gallery identity;
- requires the ZIP inventory to match the manifest exactly;
- validates safe file names, declared sizes, and SHA-256 for Markdown, every
  image, and the PDF;
- imports verified images and an allowed-size PDF through Discourse
  `UploadCreator`;
- publishes one Bot reply and records the reply against the task.

If the verified PDF alone exceeds the Discourse attachment limit, publish the
metadata and images, omit the PDF, and notify the requester.

## Rationale

The manifest is a narrow, versioned contract between independently deployed
applications. Defense-in-depth protects Discourse from corruption and archive
attacks, while native uploads keep normal storage, extension, size, CDN, and
backup behavior authoritative.

## Consequences

### Positive

- Content is checked before it enters the forum.
- Protocol incompatibility fails explicitly.
- Final media uses normal Discourse storage and rendering.
- A large PDF does not discard otherwise valid metadata and images.

### Negative

- Publication performs additional I/O and hashing.
- The plugin and daemon must coordinate manifest schema changes.
- Upload failures can occur after daemon execution has completed.
- Partial publication requires explicit notification and recovery behavior.

## Alternatives considered

The following are retrospective inferences:

- trust the daemon response and extract the ZIP directly;
- publish permanent links to daemon-hosted artifacts;
- upload only the ZIP rather than native images and PDF;
- reject the entire result when the PDF exceeds the attachment limit.

These alternatives weaken verification, forum integration, or useful partial
delivery.

## Evidence

- [`lib/eharchiver/artifact_reply.rb`](../../lib/eharchiver/artifact_reply.rb)
- [`lib/eharchiver/daemon_client.rb`](../../lib/eharchiver/daemon_client.rb)
- [`spec/lib/artifact_reply_spec.rb`](../../spec/lib/artifact_reply_spec.rb)

## Related decisions

- [ADR-0001](0001-separate-discourse-plugin-and-archive-daemon.md)
- [ADR-0002](0002-make-discourse-the-integration-gateway.md)
- [ADR-0007](0007-design-side-effects-for-idempotency-and-audit.md)
