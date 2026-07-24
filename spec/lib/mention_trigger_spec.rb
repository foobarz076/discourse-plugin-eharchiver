# frozen_string_literal: true

RSpec.describe Eharchiver::MentionTrigger do
  let(:bot) { Eharchiver::BotUser.ensure! }
  let(:requester) { Fabricate(:user, trust_level: TrustLevel[1]) }
  let(:topic) { Fabricate(:topic, user: requester) }
  let(:fabricate_post) do
    lambda do |raw, user: requester|
      Fabricate(:post, topic: topic, user: user, raw: raw, cooked: PrettyText.cook(raw))
    end
  end

  before do
    enable_current_plugin
    SiteSetting.eharchiver_enabled = true
    bot
    SiteSetting.eharchiver_request_allowed_groups = Group::AUTO_GROUPS[:everyone]
    SiteSetting.eharchiver_allowed_categories = ""
    SiteSetting.eharchiver_default_archive_quality = "resample"
    SiteSetting.eharchiver_daemon_url = "http://127.0.0.1:8765"
    SiteSetting.eharchiver_daemon_api_key = "daemon-api-key-that-is-at-least-32-bytes"
    SiteSetting.eharchiver_task_signing_secret = "task-signing-secret-that-is-at-least-32-bytes"
  end

  it "enqueues a task only when a parsed mention includes a supported gallery link" do
    post =
      fabricate_post.call(
        "Please archive https://e-hentai.org/g/3407838/b8ae774a46/, @#{bot.username}",
      )

    expect_enqueued_with(job: :eharchiver_mention_reply, args: { post_id: post.id }) do
      expect(described_class.enqueue_if_triggered(post)).to eq(true)
    end

    expect_not_enqueued_with(job: :eharchiver_mention_reply) do
      expect(
        described_class.enqueue_if_triggered(
          fabricate_post.call("Nothing supported here, @#{bot.username}"),
        ),
      ).to eq(false)
    end
  end

  it "ignores code mentions, gallery links in code or quotes, and the bot's own posts" do
    expect_not_enqueued_with(job: :eharchiver_mention_reply) do
      expect(described_class.enqueue_if_triggered(fabricate_post.call("`@#{bot.username}`"))).to eq(
        false,
      )
    end

    expect_not_enqueued_with(job: :eharchiver_mention_reply) do
      expect(
        described_class.enqueue_if_triggered(
          fabricate_post.call("@#{bot.username} `https://e-hentai.org/g/3407838/b8ae774a46/`"),
        ),
      ).to eq(false)
    end

    expect_not_enqueued_with(job: :eharchiver_mention_reply) do
      expect(
        described_class.enqueue_if_triggered(
          fabricate_post.call("> https://e-hentai.org/g/3407838/b8ae774a46/\n\n@#{bot.username}"),
        ),
      ).to eq(false)
    end

    expect_not_enqueued_with(job: :eharchiver_mention_reply) do
      expect(
        described_class.enqueue_if_triggered(
          fabricate_post.call(
            "@#{bot.username} https://e-hentai.org/g/3407838/b8ae774a46/",
            user: bot,
          ),
        ),
      ).to eq(false)
    end
  end

  it "submits one daemon task per unique gallery and remains idempotent" do
    SiteSetting.eharchiver_default_archive_quality = "original"
    SiteSetting.eharchiver_original_download_groups = Group::AUTO_GROUPS[:admins]
    post =
      fabricate_post.call(
        "@#{bot.username} https://e-hentai.org/g/3407838/b8ae774a46/ " \
          "https://e-hentai.org/g/3407838/b8ae774a46/",
      )
    stub_request(:post, "http://127.0.0.1:8765/v1/tasks").to_return do |request|
      claims = JWT.decode(JSON.parse(request.body).fetch("authorization"), nil, false).first
      {
        status: 202,
        body:
          JSON.generate(
            task_id: claims.fetch("jti"),
            requester_user_id: requester.id,
            topic_id: topic.id,
            gallery_url: claims.fetch("gallery_url"),
            quality: "resample",
            status: "queued",
            status_version: 1,
            updated_at: Time.now.utc.iso8601,
          ),
      }
    end

    expect { described_class.process(post) }.to change(Eharchiver::Task, :count).by(1)
    expect { described_class.process(post) }.not_to change(Eharchiver::Task, :count)
    expect(Eharchiver::Task.last).to have_attributes(
      source_post_id: post.id,
      gallery_url: "https://e-hentai.org/g/3407838/b8ae774a46/",
      quality: "resample",
      status: "queued",
    )
  end

  it "privately notifies a requester whose permissions are insufficient" do
    SiteSetting.eharchiver_request_allowed_groups = Group::AUTO_GROUPS[:admins]
    post = fabricate_post.call("@#{bot.username} https://e-hentai.org/g/3407838/b8ae774a46/")

    expect { described_class.process(post) }.to change {
      Topic.where(archetype: Archetype.private_message).count
    }.by(1)
    expect(Topic.where(archetype: Archetype.private_message).last.allowed_users).to include(
      requester,
    )
  end
end
