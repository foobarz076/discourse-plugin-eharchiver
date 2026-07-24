# frozen_string_literal: true

RSpec.describe Eharchiver::TaskAuthorization do
  before do
    SiteSetting.eharchiver_task_signing_secret = "task-signing-secret-that-is-at-least-32-bytes"
    SiteSetting.eharchiver_task_token_ttl_seconds = 300
    SiteSetting.eharchiver_pdf_max_width = 2048
    SiteSetting.eharchiver_jpeg_quality = 88
    SiteSetting.eharchiver_include_uploader_comment = true
  end

  it "issues the exact strict daemon claim set" do
    user = Fabricate(:user)
    topic = Fabricate(:topic)
    now = Time.utc(2026, 7, 23, 12, 0, 0)
    task_id = SecureRandom.uuid
    token =
      described_class.issue(
        task_id: task_id,
        user: user,
        topic: topic,
        gallery_url: "https://E-HENTAI.org/g/3407838/B8AE774A46",
        quality: "original",
        max_cost_gp: 500,
        min_remaining_gp: 100_000,
        now: now,
      )

    payload, header =
      JWT.decode(
        token,
        SiteSetting.eharchiver_task_signing_secret,
        true,
        algorithm: "HS256",
        verify_aud: true,
        aud: "eharchiver-daemon",
        verify_iss: true,
        iss: Discourse.base_url,
        verify_expiration: false,
      )

    expect(header).to eq("alg" => "HS256", "typ" => "JWT")
    expect(payload.keys).to contain_exactly(
      "v",
      "jti",
      "iss",
      "aud",
      "sub",
      "topic_id",
      "gallery_url",
      "quality",
      "max_gp",
      "min_gp_balance",
      "max_image_width",
      "jpeg_quality",
      "include_uploader_comment",
      "iat",
      "exp",
    )
    expect(payload).to include(
      "v" => 2,
      "jti" => task_id,
      "sub" => user.id.to_s,
      "topic_id" => topic.id,
      "gallery_url" => "https://e-hentai.org/g/3407838/b8ae774a46/",
      "quality" => "original",
      "max_gp" => 500,
      "min_gp_balance" => 100_000,
      "max_image_width" => 2048,
      "jpeg_quality" => 88,
      "include_uploader_comment" => true,
      "iat" => now.to_i,
      "exp" => now.to_i + 300,
    )
  end

  it "requires a sufficiently long signing secret" do
    SiteSetting.eharchiver_task_signing_secret = "short"
    expect do
      described_class.issue(
        task_id: SecureRandom.uuid,
        user: Fabricate(:user),
        topic: Fabricate(:topic),
        gallery_url: "https://e-hentai.org/g/3407838/b8ae774a46/",
        quality: "resample",
        max_cost_gp: 0,
        min_remaining_gp: 0,
      )
    end.to raise_error(Eharchiver::ConfigurationError)
  end
end
