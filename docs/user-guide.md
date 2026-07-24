# End-User Guide

## English

### What EH Archiver does

EH Archiver lets an authorized Discourse user request an archive of a supported
E-Hentai or ExHentai gallery from a public topic. When processing succeeds, the
EH Archiver Bot replies in the same topic with gallery metadata, converted
images in page order, and normally a generated PDF.

Your site administrator decides who may use the service, which categories
allow requests, whether original archives are available, and whether any GP
may be spent.

### Before requesting an archive

You need:

- a logged-in account in an allowed request group;
- a public topic in an allowed category;
- the current EH Archiver Bot username shown by your site;
- a complete supported gallery URL.

Supported URLs have one of these exact shapes:

```text
https://e-hentai.org/g/<gallery-id>/<10-character-token>/
https://exhentai.org/g/<gallery-id>/<10-character-token>/
```

HTTP links, shortened links, gallery search pages, image-page links, and links
with query strings or fragments are not accepted.

### Request an archive

Create a new regular post that includes both a real Bot mention and the gallery
link:

```text
@eharchiver Please archive this gallery:
https://e-hentai.org/g/123456/0123456789/
```

Replace `@eharchiver` with the Bot username configured on your site, and replace
the example with the real gallery URL.

The mention and link must be part of the new post itself:

- content inside a quote, code block, or inline code does not trigger a task;
- private messages do not trigger a task;
- posts made by the Bot do not trigger another task;
- editing an existing post does not create a new request;
- repeating the same gallery link in one post creates only one task;
- including several different supported links creates one task per unique
  link.

There may be no immediate public acknowledgement. The Bot publishes the result
after the daemon has downloaded, converted, and packaged the gallery.

### Archive quality

The mention format currently has no command flag for selecting quality. The
site's default quality is used.

- **Resampled:** generally smaller and normally the safest default.
- **Original:** available only when both your account and the daemon policy
  allow it.

If the site default is Original but you do not have Original permission, the
request automatically uses Resampled quality. Writing words such as
`original`, `resample`, or `--quality` in the post does not change the request.

Some archives can require GP. The site and daemon enforce maximum cost and
remaining-balance limits. A request is rejected if it cannot be completed
within both policies.

### What happens when the request completes

The Bot reply contains:

- prepared gallery metadata;
- converted images in verified page order;
- a generated PDF, when it fits the site's attachment policy.

The topic title may be updated from verified gallery metadata, preferring the
Japanese title and falling back to the original title. Trusted gallery tags may
be appended as namespaced Discourse tags, while the topic's existing tags are
preserved.

If the PDF is larger than the site's attachment limit, the Bot still publishes
the metadata and images. You receive a private message explaining that the PDF
was omitted.

### Notifications and failures

- If your account or topic is not permitted, the Bot sends you a private
  permission notice.
- If an archive option, spending rule, or balance rule prevents completion, the
  Bot sends you a private failure notice.
- Operational faults are sent to the site's administrators, so you may not
  receive technical error details.

Administrators can inspect task status and retry eligible failed tasks. A retry
is a new linked attempt and rechecks your current permissions.

### If nothing happens

Check the original post:

1. Confirm that the mention resolved to the actual EH Archiver Bot account.
2. Confirm that the link uses HTTPS and the complete `/g/{id}/{token}/` form.
3. Make sure neither the mention nor the link is inside quoted or code content.
4. Make sure the post is in a public topic rather than a private message.
5. Check your private messages for a permission or policy notice.
6. Ask an administrator to check **EH Archiver → Tasks** and the allowed group
   and category settings.

Do not repeatedly post the same paid request while its status is unknown. Ask
an administrator to reconcile the existing task first.

### Privacy and content notes

The result is posted into the same topic as the request and is visible to
everyone who can see that topic. Do not request content in a topic whose
audience should not receive the resulting images and metadata.

Gallery credentials belong to the daemon operator. End users should never post
E-Hentai/ExHentai cookies or account credentials in Discourse.

---

## 中文

### EH Archiver 的用途

EH Archiver 允许获得授权的 Discourse 用户在公开主题中请求归档受支持的
E-Hentai 或 ExHentai 画廊。处理成功后，EH Archiver Bot 会在同一主题中
回复画廊元数据、按页面顺序排列的转换图片，并通常附带生成的 PDF。

站点管理员决定哪些用户可以使用服务、哪些分类允许请求、是否允许原始版本，
以及是否可以消费 GP。

### 请求归档前

汝需要：

- 已登录且属于允许请求的用户组；
- 位于允许分类中的公开主题；
- 本站当前使用的 EH Archiver Bot 用户名；
- 完整且受支持的画廊 URL。

支持的 URL 必须采用以下精确形式之一：

```text
https://e-hentai.org/g/<画廊-ID>/<10-字符-Token>/
https://exhentai.org/g/<画廊-ID>/<10-字符-Token>/
```

HTTP 链接、短链接、画廊搜索页、单张图片页，以及带查询参数或 Fragment 的
链接均不受支持。

### 请求归档

创建一条新的普通帖子，其中同时包含真实的 Bot 提及和画廊链接：

```text
@eharchiver 请归档这个画廊：
https://e-hentai.org/g/123456/0123456789/
```

请把 `@eharchiver` 替换为本站配置的 Bot 用户名，并把示例替换为真实画廊
URL。

提及和链接必须位于新帖子本身：

- 引用、代码块或行内代码中的内容不会触发任务；
- 私信不会触发任务；
- Bot 自己发布的帖子不会再次触发任务；
- 编辑已有帖子不会创建新请求；
- 同一帖子中重复的相同画廊链接只会创建一个任务；
- 同一帖子包含多个不同的有效链接时，每个不重复链接会创建一个任务。

系统不一定立即发布公开确认。Daemon 完成下载、转换和打包后，Bot 才会发布
结果。

### 归档质量

当前的提及格式没有用于选择质量的命令参数，任务使用站点默认质量。

- **重采样：** 通常体积更小，也是更安全的默认值。
- **原始版本：** 只有帐号权限和 daemon 策略同时允许时才可使用。

如果站点默认为原始版本，而汝没有原始版权限，请求会自动改用重采样。在帖子中
书写 `original`、`resample` 或 `--quality` 并不会改变请求质量。

部分归档可能需要 GP。站点与 daemon 都会执行最高消费和最低剩余余额限制。
无法同时满足双方策略的请求会被拒绝。

### 请求完成后

Bot 回复包含：

- 整理后的画廊元数据；
- 按经过验证的页面顺序排列的转换图片；
- 在符合本站附件策略时生成的 PDF。

主题标题可能根据经过验证的画廊元数据更新，优先使用日文标题，没有时回退到
原始标题。可信画廊标签可能作为带命名空间的 Discourse 标签追加，主题原有
标签会被保留。

如果 PDF 大于本站附件上限，Bot 仍会发布元数据和图片。汝会收到一封私信，
说明 PDF 已被省略。

### 通知与失败

- 如果帐号或主题没有权限，Bot 会私信发送权限通知。
- 如果归档选项、消费规则或余额规则阻止任务完成，Bot 会私信发送失败通知。
- 运行故障会发送给站点管理员，因此汝不一定会收到技术错误详情。

管理员可以检查任务状态，并重试符合条件的失败任务。重试是一个新的关联尝试，
并会重新检查汝当前的权限。

### 如果没有任何反应

检查原始帖子：

1. 确认提及确实解析为 EH Archiver Bot 帐号。
2. 确认链接使用 HTTPS 和完整的 `/g/{id}/{token}/` 形式。
3. 确认提及和链接都不在引用或代码内容中。
4. 确认帖子位于公开主题，而不是私信。
5. 检查私信中是否有权限或策略通知。
6. 请管理员检查 **EH Archiver → 任务**，以及允许的用户组与分类设置。

当付费请求的状态未知时，不要反复发布同一个请求。请先让管理员对已有任务进行
对账。

### 隐私与内容说明

结果会发布到请求所在的同一主题，并对所有可以查看该主题的人可见。不要在受众
不应看到结果图片和元数据的主题中发起请求。

画廊凭据属于 daemon 运维方。最终用户绝不应在 Discourse 中发布
E-Hentai/ExHentai Cookie 或帐号凭据。
