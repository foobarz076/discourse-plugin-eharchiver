# frozen_string_literal: true

RSpec.describe SiteSetting do
  it "uses deny-by-default task and spending settings" do
    expect(SiteSetting.eharchiver_enabled).to eq(false)
    expect(SiteSetting.eharchiver_trigger_mode).to eq("manual")
    expect(SiteSetting.eharchiver_bot_username).to eq("eharchiver")
    expect(SiteSetting.eharchiver_default_archive_quality).to eq("resample")
    expect(SiteSetting.eharchiver_request_allowed_groups).to eq("3")
    expect(SiteSetting.eharchiver_paid_download_groups).to eq("1")
    expect(SiteSetting.eharchiver_standard_max_gp_per_download).to eq(0)
    expect(SiteSetting.eharchiver_elevated_max_gp_per_download).to eq(0)
    expect(SiteSetting.eharchiver_notification_admin_username).to eq("")
    expect(SiteSetting.eharchiver_notification_chat_channel_id).to eq(0)
  end

  it "keeps connection and signing secrets out of client settings" do
    secret_settings = %i[
      eharchiver_daemon_api_key
      eharchiver_task_signing_secret
      eharchiver_webhook_signing_secret
    ]

    expect(SiteSetting.client_settings).to include(:eharchiver_enabled)
    expect(SiteSetting.client_settings).not_to include(*secret_settings)
    expect(SiteSetting.secret_settings).to include(*secret_settings)
  end

  it "matches the daemon task authorization lifetime limit" do
    expect(SiteSetting.eharchiver_task_token_ttl_seconds).to eq(300)
    expect(SiteSetting.type_supervisor.type_hash(:eharchiver_task_token_ttl_seconds)).to include(
      min: 30,
      max: 600,
    )
  end
end
