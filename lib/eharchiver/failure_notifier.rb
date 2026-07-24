# frozen_string_literal: true

module Eharchiver
  class FailureNotifier
    USER_ACTIONABLE_CODES = %w[
      archive_option_unavailable
      archive_spending_not_allowed
      archive_balance_reserve_violation
      task_policy_denied
    ].freeze
    DEDUPE_TTL = 30.days

    class << self
      def permission_denied(post, _error)
        notify_user(
          post.user,
          key: "permission-#{post.id}",
          title_key: "eharchiver.notifications.permission_denied_title",
          body_key: "eharchiver.notifications.permission_denied_body",
          body_params: {
            topic_url: post.full_url,
          },
        )
      end

      def submission_failed(post, task, error)
        notify_admin(
          key: "submission-#{task&.task_id || post.id}",
          title_key: "eharchiver.notifications.operational_failure_title",
          body_key: "eharchiver.notifications.operational_failure_body",
          body_params: operational_params(task, error, post.full_url),
        )
      end

      def pdf_omitted(task, reply_post:, pdf_size_bytes:, limit_bytes:)
        notify_user(
          task.user,
          key: "pdf-omitted-#{task.task_id}",
          title_key: "eharchiver.notifications.pdf_omitted_title",
          body_key: "eharchiver.notifications.pdf_omitted_body",
          body_params: {
            reply_url: reply_post.full_url,
            gallery_url: task.gallery_url,
            pdf_size: ActiveSupport::NumberHelper.number_to_human_size(pdf_size_bytes),
            limit: ActiveSupport::NumberHelper.number_to_human_size(limit_bytes),
          },
        )
      end

      def task_failed(task)
        if USER_ACTIONABLE_CODES.include?(task.error_code)
          notify_user(
            task.user,
            key: "task-user-#{task.task_id}",
            title_key: "eharchiver.notifications.request_failed_title",
            body_key: "eharchiver.notifications.request_failed_body",
            body_params: {
              gallery_url: task.gallery_url,
            },
          )
        else
          notify_admin(
            key: "task-admin-#{task.task_id}",
            title_key: "eharchiver.notifications.operational_failure_title",
            body_key: "eharchiver.notifications.operational_failure_body",
            body_params: operational_params(task, nil, task.source_post&.full_url),
          )
        end
      end

      def delivery_failed(task, error)
        notify_admin(
          key: "delivery-#{task.task_id}",
          title_key: "eharchiver.notifications.delivery_failure_title",
          body_key: "eharchiver.notifications.operational_failure_body",
          body_params: operational_params(task, error, task.source_post&.full_url),
        )
      end

      private

      def operational_params(task, error, source_url)
        {
          task_id: task&.task_id || I18n.t("eharchiver.notifications.not_available"),
          gallery_url: task&.gallery_url || I18n.t("eharchiver.notifications.not_available"),
          source_url: source_url.presence || I18n.t("eharchiver.notifications.not_available"),
          error_code:
            task&.error_code.presence || error&.class&.name ||
              I18n.t("eharchiver.notifications.not_available"),
        }
      end

      def notify_user(user, key:, title_key:, body_key:, body_params:)
        deliver_once(key) do
          create_pm(
            user,
            I18n.t(title_key, locale: user.effective_locale),
            I18n.t(body_key, **body_params, locale: user.effective_locale),
          )
        end
      end

      def notify_admin(key:, title_key:, body_key:, body_params:)
        title = I18n.t(title_key, locale: SiteSetting.default_locale)
        body = I18n.t(body_key, **body_params, locale: SiteSetting.default_locale)
        deliver_once(key) do
          next true if deliver_to_chat(title, body)

          admin = User.find_by_username(SiteSetting.eharchiver_notification_admin_username)
          if admin.nil? || !admin.admin?
            Rails.logger.error(
              "[EHArchiver] Cannot deliver failure notification: notification admin is not configured.",
            )
            next false
          end
          create_pm(admin, title, body)
        end
      end

      def deliver_to_chat(title, body)
        channel_id = SiteSetting.eharchiver_notification_chat_channel_id
        return false if channel_id <= 0
        return false if !Discourse.plugins_by_name["chat"]&.enabled?
        return false if !defined?(ChatSDK::Message)

        bot = BotUser.ensure!
        ChatSDK::Message.create(
          raw: "**#{title}**\n\n#{body}",
          channel_id: channel_id,
          guardian: Guardian.new(bot),
          enforce_membership: true,
        )
        true
      rescue StandardError => error
        Rails.logger.warn("[EHArchiver] Chat notification failed: #{error.class}")
        false
      end

      def create_pm(recipient, title, body)
        PostCreator.create!(
          BotUser.ensure!,
          title: title,
          raw: body,
          archetype: Archetype.private_message,
          target_usernames: recipient.username,
          skip_guardian: true,
          skip_validations: true,
        )
        true
      end

      def deliver_once(key)
        redis_key = "eharchiver:notification:#{key}"
        return false if !Discourse.redis.set(redis_key, "1", nx: true, ex: DEDUPE_TTL.to_i)

        delivered = yield
        Discourse.redis.del(redis_key) if !delivered
        delivered
      rescue StandardError => error
        Discourse.redis.del(redis_key) if redis_key
        Rails.logger.error(
          "[EHArchiver] Failure notification could not be delivered: #{error.class}",
        )
        false
      end
    end
  end
end
