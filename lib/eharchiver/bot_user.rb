# frozen_string_literal: true

module Eharchiver
  class BotUser
    DEFAULT_USERNAME = "eharchiver"
    FIRST_BOT_USER_ID = -10_000

    class << self
      def find
        UserCustomField.find_by(name: BOT_USER_CUSTOM_FIELD, value: "t")&.user
      end

      def ensure!
        bot =
          DistributedMutex.synchronize("eharchiver-bot-user") do
            existing_bot = find
            username =
              UserNameSuggester.suggest(desired_username, current_username: existing_bot&.username)

            existing_bot ? update_bot!(existing_bot, username) : create_bot!(username)
          end

        sync_username_setting!(bot)
        bot
      end

      private

      def desired_username
        SiteSetting.eharchiver_bot_username.presence || DEFAULT_USERNAME
      end

      def create_bot!(username)
        bot =
          User.new(
            id: next_bot_user_id,
            username: username,
            name: "EH Archiver",
            email: "eharchiver-bot-#{SecureRandom.hex(8)}@invalid.invalid",
            password: SecureRandom.hex(32),
            active: true,
            approved: true,
            staged: false,
            admin: false,
            moderator: false,
            trust_level: TrustLevel[0],
          )
        bot.custom_fields[BOT_USER_CUSTOM_FIELD] = true
        bot.save!(validate: false)

        configure_bot!(bot)
      end

      def update_bot!(bot, username)
        bot.username = username
        bot.active = true
        bot.approved = true
        bot.staged = false
        bot.admin = false
        bot.moderator = false
        bot.trust_level = TrustLevel[0]
        bot.custom_fields[BOT_USER_CUSTOM_FIELD] = true
        bot.save!(validate: false)

        configure_bot!(bot)
      end

      def configure_bot!(bot)
        user_option = bot.user_option || bot.create_user_option!
        never = UserOption.email_level_types[:never]

        user_option.update!(email_level: never, email_messages_level: never)
        bot
      end

      def sync_username_setting!(bot)
        return if SiteSetting.eharchiver_bot_username == bot.username

        SiteSetting.eharchiver_bot_username = bot.username
      end

      def next_bot_user_id
        [User.minimum(:id).to_i - 1, FIRST_BOT_USER_ID].min
      end
    end
  end
end
