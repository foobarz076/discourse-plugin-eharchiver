# frozen_string_literal: true

RSpec.describe Eharchiver::DaemonClient do
  before do
    SiteSetting.eharchiver_daemon_url = "http://127.0.0.1:8765/daemon"
    SiteSetting.eharchiver_daemon_api_key = "daemon-api-key-that-is-at-least-32-bytes"
  end

  it "sends the API key and task authorization only to the configured daemon" do
    request =
      stub_request(:post, "http://127.0.0.1:8765/daemon/v1/tasks").with(
        headers: {
          "X-Eharchiver-Api-Key" => SiteSetting.eharchiver_daemon_api_key,
        },
        body: JSON.generate(authorization: "signed-token"),
      ).to_return(status: 202, body: JSON.generate(task_id: SecureRandom.uuid, status: "queued"))

    response = described_class.new.submit("signed-token")

    expect(request).to have_been_requested.once
    expect(response["status"]).to eq("queued")
  end

  it "turns daemon failures into a structured transport error" do
    stub_request(:get, %r{/daemon/v1/tasks/}).to_return(
      status: 409,
      body: JSON.generate(detail: "task is running"),
    )

    expect { described_class.new.task(SecureRandom.uuid) }.to raise_error(
      Eharchiver::DaemonError,
      "task is running",
    ) do |error|
      expect(error.http_status).to eq(409)
    end
  end

  it "streams an artifact while calculating its size and checksum" do
    task_id = SecureRandom.uuid
    payload = "artifact bytes"
    stub_request(:get, "http://127.0.0.1:8765/daemon/v1/tasks/#{task_id}/artifact").to_return(
      status: 200,
      body: payload,
      headers: {
        "Content-Type" => "application/zip",
      },
    )

    Tempfile.create do |file|
      result = described_class.new.download_artifact(task_id, file, max_bytes: 1024)
      file.rewind

      expect(file.read).to eq(payload)
      expect(result).to eq(size_bytes: payload.bytesize, sha256: Digest::SHA256.hexdigest(payload))
    end
  end
end
