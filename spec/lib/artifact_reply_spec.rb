# frozen_string_literal: true

require "zip"

RSpec.describe Eharchiver::ArtifactReply do
  let(:requester) { Fabricate(:user, trust_level: TrustLevel[1]) }
  let(:topic) { Fabricate(:topic, user: requester) }
  let(:source_post) { Fabricate(:post, topic: topic, user: requester) }
  let(:gallery_url) { "https://e-hentai.org/g/3407838/b8ae774a46/" }
  let(:artifact_gallery_url) { gallery_url }
  let(:japanese_title) { "日本語の画廊タイトル" }
  let(:original_title) { "Original gallery title" }
  let(:max_attachment_size_kb) { 10_240 }
  let(:max_tags_per_topic) { 5 }
  let(:trusted_tags) do
    {
      artist: ["Example Artist"],
      female: ["trusted tag"],
    }
  end
  let(:low_trust_tags) { { female: ["low trust tag"] } }
  let(:task) do
    Eharchiver::Task.create!(
      task_id: SecureRandom.uuid,
      user: requester,
      topic: topic,
      source_post: source_post,
      gallery_url: gallery_url,
      quality: "resample",
      max_cost_gp: 0,
      min_remaining_gp: 0,
      status: "ready",
      daemon_status_version: 3,
      artifact_size_bytes: artifact_bytes.bytesize,
      artifact_sha256: Digest::SHA256.hexdigest(artifact_bytes),
    )
  end
  let(:image) { File.binread(Rails.root.join("spec/fixtures/images/logo.jpg")) }
  let(:pdf) { File.binread(Rails.root.join("spec/fixtures/pdf/small.pdf")) }
  let(:markdown) { "| Field | Value |\n|---|---|\n| Title | Example |\n" }
  let(:artifact_bytes) do
    files = { "reply.md" => markdown, "images/0001.jpg" => image, "3407838-b8ae774a46.pdf" => pdf }
    manifest = {
      schema_version: 3,
      gallery: {
        source_url: artifact_gallery_url,
        japanese_title: japanese_title,
        title: original_title,
        tags: trusted_tags,
        tags_low_trust: low_trust_tags,
      },
      images: {
        count: 1,
        files: [
          {
            artifact: "0001.jpg",
            size_bytes: image.bytesize,
            sha256: Digest::SHA256.hexdigest(image),
          },
        ],
      },
      markdown: {
        file: "reply.md",
        size_bytes: markdown.bytesize,
        sha256: Digest::SHA256.hexdigest(markdown),
      },
      pdf: {
        file: "3407838-b8ae774a46.pdf",
        size_bytes: pdf.bytesize,
        sha256: Digest::SHA256.hexdigest(pdf),
      },
    }

    Tempfile.create(%w[artifact .zip]) do |package|
      package.close
      Zip::File.open(package.path, create: true) do |zip|
        zip.get_output_stream("artifact.json") { |stream| stream.write(JSON.generate(manifest)) }
        files.each do |name, contents|
          zip.get_output_stream(name) { |stream| stream.write(contents) }
        end
      end
      File.binread(package.path)
    end
  end

  before do
    enable_current_plugin
    SiteSetting.eharchiver_enabled = true
    SiteSetting.eharchiver_daemon_url = "http://127.0.0.1:8765"
    SiteSetting.eharchiver_daemon_api_key = "daemon-api-key-that-is-at-least-32-bytes"
    SiteSetting.eharchiver_max_artifact_size_mb = 16
    SiteSetting.authorized_extensions = "#{SiteSetting.authorized_extensions}|pdf"
    SiteSetting.max_attachment_size_kb = max_attachment_size_kb
    SiteSetting.tagging_enabled = true
    SiteSetting.max_tag_length = 50
    SiteSetting.max_tags_per_topic = max_tags_per_topic
    Eharchiver::BotUser.ensure!
    stub_request(:get, "http://127.0.0.1:8765/v1/tasks/#{task.task_id}/artifact").to_return(
      status: 200,
      body: artifact_bytes,
      headers: {
        "Content-Type" => "application/zip",
      },
    )
  end

  it "uploads manifest-ordered images and PDF, then publishes one bot reply" do
    post = described_class.publish!(task)

    expect(post).to have_attributes(
      user_id: Eharchiver::BotUser.find.id,
      topic_id: topic.id,
      reply_to_post_number: source_post.post_number,
    )
    expect(post.raw).to start_with(markdown.rstrip)
    image_upload = Upload.find_by!(original_filename: "0001.jpg")
    pdf_upload = Upload.find_by!(original_filename: "3407838-b8ae774a46.pdf")
    expect(post.raw.index(image_upload.short_url)).to be < post.raw.index(pdf_upload.short_url)
    expect(task.reload.reply_post_id).to eq(post.id)
    expect(topic.reload.title).to eq(japanese_title)
    expect(topic.first_post.reload.last_editor_id).to eq(Discourse::SYSTEM_USER_ID)
    expect(topic.tags.pluck(:name)).to contain_exactly(
      "artist:example-artist",
      "female:trusted-tag",
    )
    expect(Tag.where_name("female:low-trust-tag")).not_to exist
    expect(
      PostCustomField.find_by!(name: Eharchiver::TASK_ID_POST_FIELD, value: task.task_id).post,
    ).to eq(post)

    expect { described_class.publish!(task) }.not_to change(Post, :count)
  end

  it "rejects an artifact whose task checksum does not match" do
    task.update!(artifact_sha256: "0" * 64)

    expect { described_class.publish!(task) }.to raise_error(
      Eharchiver::ArtifactError,
      /does not match/,
    )
  end

  context "when the artifact uses the other supported gallery host" do
    let(:artifact_gallery_url) { "https://exhentai.org/g/3407838/b8ae774a46/" }

    it "accepts the matching gid and token" do
      expect { described_class.publish!(task) }.not_to raise_error
    end
  end

  context "when the artifact gallery gid differs" do
    let(:artifact_gallery_url) { "https://exhentai.org/g/3407839/b8ae774a46/" }

    it "rejects the artifact" do
      expect { described_class.publish!(task) }.to raise_error(
        Eharchiver::ArtifactError,
        "Artifact gallery does not match the task.",
      )
    end
  end

  context "when the artifact gallery token differs" do
    let(:artifact_gallery_url) { "https://exhentai.org/g/3407838/aaaaaaaaaa/" }

    it "rejects the artifact" do
      expect { described_class.publish!(task) }.to raise_error(
        Eharchiver::ArtifactError,
        "Artifact gallery does not match the task.",
      )
    end
  end

  context "when the artifact gallery URL is invalid" do
    let(:artifact_gallery_url) { "not a gallery URL" }

    it "rejects the artifact" do
      expect { described_class.publish!(task) }.to raise_error(
        Eharchiver::ArtifactError,
        "Artifact gallery does not match the task.",
      )
    end
  end

  context "when the Japanese title is absent" do
    let(:japanese_title) { nil }

    it "uses the original title as the fallback" do
      described_class.publish!(task)

      expect(topic.reload.title).to eq(original_title)
    end
  end

  context "when the topic already has tags and reaches the site limit" do
    let(:max_tags_per_topic) { 2 }
    let!(:existing_tag) { Fabricate(:tag, name: "existing-tag") }

    before { topic.tags << existing_tag }

    it "preserves existing tags and appends trusted tags in manifest order" do
      described_class.publish!(task)

      expect(topic.reload.tags.pluck(:name)).to contain_exactly(
        "existing-tag",
        "artist:example-artist",
      )
      expect(Tag.where_name("female:trusted-tag")).not_to exist
      expect(Tag.where_name("female:low-trust-tag")).not_to exist
    end
  end

  context "when the PDF exceeds the site's attachment limit" do
    let(:max_attachment_size_kb) { 0 }

    it "publishes without the PDF and privately notifies the requester" do
      expect { described_class.publish!(task) }.to change {
        Topic.where(archetype: Archetype.private_message).count
      }.by(1)

      reply = task.reload.reply_post
      expect(reply.raw).to include(Upload.find_by!(original_filename: "0001.jpg").short_url)
      expect(Upload.find_by(original_filename: "3407838-b8ae774a46.pdf")).to be_nil
      notification = Topic.where(archetype: Archetype.private_message).last
      expect(notification.allowed_users).to include(requester)
      expect(notification.first_post.raw).to include(
        "/#{topic.id}/#{reply.post_number}",
        gallery_url,
      )
    end
  end
end
