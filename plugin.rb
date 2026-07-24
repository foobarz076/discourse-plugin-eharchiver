# frozen_string_literal: true

# name: discourse-eharchiver
# about: Archive supported E-Hentai and ExHentai galleries through a separate daemon.
# version: 0.1.0
# authors: Foo
# required_version: 2.7.0

enabled_site_setting :eharchiver_enabled

module ::Eharchiver
  PLUGIN_NAME = "discourse-eharchiver"
  BOT_USER_CUSTOM_FIELD = "eharchiver_bot_user"
  TRIGGER_SOURCE_POST_ID_FIELD = "eharchiver_trigger_source_post_id"
  TASK_ID_POST_FIELD = "eharchiver_task_id"
  ARTIFACT_TOPIC_TITLE_FIELD = "eharchiver_artifact_topic_title"
  ARTIFACT_TOPIC_TAGS_FIELD = "eharchiver_artifact_topic_tags"
end

require_relative "lib/eharchiver/bot_user"
require_relative "lib/eharchiver/errors"
require_relative "lib/eharchiver/engine"

after_initialize do
  register_seedfu_fixtures(Rails.root.join("plugins/discourse-eharchiver/db/fixtures"))
  register_user_custom_field_type(Eharchiver::BOT_USER_CUSTOM_FIELD, :boolean)
  register_post_custom_field_type(Eharchiver::TRIGGER_SOURCE_POST_ID_FIELD, :integer)
  register_post_custom_field_type(Eharchiver::TASK_ID_POST_FIELD, :string)
  register_post_custom_field_type(Eharchiver::ARTIFACT_TOPIC_TITLE_FIELD, :string)
  register_post_custom_field_type(Eharchiver::ARTIFACT_TOPIC_TAGS_FIELD, :string)

  on(:post_created) { |post| ::Eharchiver::MentionTrigger.enqueue_if_triggered(post) }

  on(:site_setting_changed) do |name|
    ::Eharchiver::BotUser.ensure! if name.to_s == "eharchiver_bot_username"
  end

  on_enabled_change { |_, enabled| ::Eharchiver::BotUser.ensure! if enabled }
end
