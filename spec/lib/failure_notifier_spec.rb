# frozen_string_literal: true

RSpec.describe Eharchiver::FailureNotifier do
  let(:admin) { Fabricate(:admin) }
  let(:requester) { Fabricate(:user) }
  let(:task) do
    Eharchiver::Task.create!(
      task_id: SecureRandom.uuid,
      user: requester,
      topic: Fabricate(:topic),
      gallery_url: "https://e-hentai.org/g/3407838/b8ae774a46/",
      quality: "resample",
      max_cost_gp: 0,
      min_remaining_gp: 0,
      status: "failed",
      error_code: "pdf_creation_error",
      error_message: "sensitive daemon detail",
    )
  end

  before do
    enable_current_plugin
    Eharchiver::BotUser.ensure!
    SiteSetting.eharchiver_notification_admin_username = admin.username
  end

  it "privately sends operational failures to the configured administrator once" do
    expect { described_class.task_failed(task) }.to change {
      Topic.where(archetype: Archetype.private_message).count
    }.by(1)
    expect { described_class.task_failed(task) }.not_to change(Topic, :count)

    message = Topic.where(archetype: Archetype.private_message).last.first_post
    expect(message.raw).to include(task.task_id, task.gallery_url, "pdf_creation_error")
    expect(message.raw).not_to include("sensitive daemon detail")
    expect(message.topic.allowed_users).to include(admin)
  end
end
