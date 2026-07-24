# frozen_string_literal: true

RSpec.describe Eharchiver::TasksController do
  let(:user) { Fabricate(:user) }
  let(:topic) { Fabricate(:topic) }
  let(:daemon_url) { "http://127.0.0.1:8765" }

  before do
    enable_current_plugin
    sign_in(user)
    SiteSetting.eharchiver_enabled = true
    SiteSetting.eharchiver_daemon_url = daemon_url
    SiteSetting.eharchiver_daemon_api_key = "daemon-api-key-that-is-at-least-32-bytes"
    SiteSetting.eharchiver_task_signing_secret = "task-signing-secret-that-is-at-least-32-bytes"
    SiteSetting.eharchiver_webhook_signing_secret =
      "webhook-signing-secret-that-is-at-least-32-bytes"
    SiteSetting.eharchiver_request_allowed_groups = Group::AUTO_GROUPS[:everyone]
  end

  it "submits a signed authorization and stores the daemon snapshot" do
    stub_request(:post, "#{daemon_url}/v1/tasks").to_return do |request|
      token = JSON.parse(request.body).fetch("authorization")
      claims = JWT.decode(token, nil, false).first
      {
        status: 202,
        body:
          JSON.generate(
            task_id: claims.fetch("jti"),
            requester_user_id: user.id,
            topic_id: topic.id,
            gallery_url: "https://e-hentai.org/g/3407838/b8ae774a46/",
            quality: "resample",
            status: "queued",
            status_version: 1,
            updated_at: "2026-07-23T12:00:00Z",
          ),
      }
    end

    post "/eharchiver/tasks.json",
         params: {
           topic_id: topic.id,
           gallery_url: "https://e-hentai.org/g/3407838/b8ae774a46/",
           quality: "resample",
         }

    expect(response.status).to eq(202)
    task = Eharchiver::Task.find_by!(task_id: response.parsed_body.dig("task", "task_id"))
    expect(task).to have_attributes(
      user_id: user.id,
      topic_id: topic.id,
      status: "queued",
      daemon_status_version: 1,
      max_cost_gp: 0,
    )
  end

  it "uses resample when the default is original but the user lacks permission" do
    SiteSetting.eharchiver_default_archive_quality = "original"
    SiteSetting.eharchiver_original_download_groups = Group::AUTO_GROUPS[:admins]
    stub_request(:post, "#{daemon_url}/v1/tasks").to_return do |request|
      token = JSON.parse(request.body).fetch("authorization")
      claims = JWT.decode(token, nil, false).first
      {
        status: 202,
        body:
          JSON.generate(
            task_id: claims.fetch("jti"),
            requester_user_id: user.id,
            topic_id: topic.id,
            gallery_url: claims.fetch("gallery_url"),
            quality: claims.fetch("quality"),
            status: "queued",
            status_version: 1,
            updated_at: "2026-07-23T12:00:00Z",
          ),
      }
    end

    post "/eharchiver/tasks.json",
         params: {
           topic_id: topic.id,
           gallery_url: "https://e-hentai.org/g/3407838/b8ae774a46/",
         }

    expect(response.status).to eq(202)
    expect(response.parsed_body.dig("task", "quality")).to eq("resample")
  end

  it "keeps the local task reconcilable when submission outcome is unknown" do
    stub_request(:post, "#{daemon_url}/v1/tasks").to_timeout

    post "/eharchiver/tasks.json",
         params: {
           topic_id: topic.id,
           gallery_url: "https://e-hentai.org/g/3407838/b8ae774a46/",
         }

    expect(response.status).to eq(502)
    expect(response.parsed_body.dig("task", "status")).to eq("submission_unknown")
  end
end
