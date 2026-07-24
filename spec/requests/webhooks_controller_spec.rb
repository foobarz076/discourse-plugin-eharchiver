# frozen_string_literal: true

RSpec.describe Eharchiver::WebhooksController do
  let(:secret) { "webhook-signing-secret-that-is-at-least-32-bytes" }
  let(:send_snapshot) do
    lambda do |status:, version:, result: nil|
      timestamp = Time.now.to_i
      body =
        JSON.generate(
          event_id: SecureRandom.uuid,
          task: {
            task_id: task.task_id,
            requester_user_id: task.user_id,
            topic_id: task.topic_id,
            gallery_url: task.gallery_url,
            quality: task.quality,
            status: status,
            status_version: version,
            updated_at: "2026-07-23T12:00:00Z",
            result: result,
          },
        )
      signature = OpenSSL::HMAC.hexdigest("SHA256", secret, "#{timestamp}.#{body}")
      post "/eharchiver/webhooks/task-status",
           params: body,
           headers: {
             "CONTENT_TYPE" => "application/json",
             "X-EHArchiver-Timestamp" => timestamp.to_s,
             "X-EHArchiver-Signature" => "sha256=#{signature}",
           }
    end
  end
  let(:task) do
    Eharchiver::Task.create!(
      task_id: SecureRandom.uuid,
      user: Fabricate(:user),
      topic: Fabricate(:topic),
      gallery_url: "https://e-hentai.org/g/3407838/b8ae774a46/",
      quality: "resample",
      max_cost_gp: 0,
      min_remaining_gp: 0,
      status: "queued",
      daemon_status_version: 1,
    )
  end

  before do
    enable_current_plugin
    SiteSetting.eharchiver_webhook_signing_secret = secret
  end

  it "accepts a signed newer snapshot and ignores stale re-delivery" do
    send_snapshot.call(status: "downloading", version: 2)
    expect(response.status).to eq(204)
    expect(task.reload).to have_attributes(status: "downloading", daemon_status_version: 2)

    send_snapshot.call(status: "queued", version: 1)
    expect(response.status).to eq(204)
    expect(task.reload).to have_attributes(status: "downloading", daemon_status_version: 2)
  end

  it "rejects an invalid signature" do
    post "/eharchiver/webhooks/task-status",
         params: JSON.generate(task: { task_id: task.task_id }),
         headers: {
           "CONTENT_TYPE" => "application/json",
           "X-EHArchiver-Timestamp" => Time.now.to_i.to_s,
           "X-EHArchiver-Signature" => "sha256=bad",
         }
    expect(response.status).to eq(403)
  end

  it "enqueues artifact publication for a valid ready snapshot" do
    expect_enqueued_with(job: :eharchiver_finalize_task, args: { task_id: task.task_id }) do
      send_snapshot.call(
        status: "ready",
        version: 3,
        result: {
          cost_gp: 0,
          size_bytes: 1024,
          sha256: "a" * 64,
        },
      )
    end

    expect(response.status).to eq(204)
    expect(task.reload).to have_attributes(status: "ready", artifact_size_bytes: 1024)
  end
end
