# frozen_string_literal: true

RSpec.describe Eharchiver::BotUser do
  before { enable_current_plugin }

  it "creates one active non-staff bot and configures it not to receive email" do
    bot = described_class.ensure!
    never = UserOption.email_level_types[:never]

    expect(bot).to have_attributes(
      username: SiteSetting.eharchiver_bot_username,
      active: true,
      approved: true,
      staged: false,
      admin: false,
      moderator: false,
    )
    expect(bot).to be_bot
    expect(bot.custom_fields[Eharchiver::BOT_USER_CUSTOM_FIELD]).to eq(true)
    expect(bot.user_option).to have_attributes(email_level: never, email_messages_level: never)
  end

  it "is idempotent" do
    bot = described_class.ensure!

    expect { described_class.ensure! }.not_to change(User, :count)
    expect(described_class.ensure!).to eq(bot)
  end

  it "renames the managed bot when the setting changes" do
    bot = described_class.ensure!

    SiteSetting.eharchiver_bot_username = "archive_helper"

    expect(bot.reload.username).to eq("archive_helper")
    expect(described_class.find).to eq(bot)
  end

  it "does not take over an existing account" do
    existing_user = Fabricate(:user, username: "archive_helper")

    SiteSetting.eharchiver_bot_username = existing_user.username
    bot = described_class.find

    expect(bot).to be_present
    expect(bot).not_to eq(existing_user)
    expect(bot.username).to eq("archive_helper1")
    expect(SiteSetting.eharchiver_bot_username).to eq(bot.username)
  end
end
