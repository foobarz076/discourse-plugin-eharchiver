# frozen_string_literal: true

module Eharchiver
  class MentionTrigger
    EXCLUDED_LINK_ANCESTORS = %w[pre code blockquote].freeze

    class << self
      def enqueue_if_triggered(post)
        return false if !candidate?(post)
        return false if gallery_urls(post).empty?

        Jobs.enqueue(:eharchiver_mention_reply, post_id: post.id)
        true
      end

      def process(post)
        return if !candidate?(post)

        gallery_urls(post).each do |gallery_url|
          submitter =
            TaskSubmitter.new(
              user: post.user,
              topic: post.topic,
              gallery_url: gallery_url,
              source_post: post,
            )
          submitter.submit!
        rescue PolicyDenied => error
          FailureNotifier.permission_denied(post, error)
          break
        rescue DaemonError, ConfigurationError => error
          task = submitter&.task
          task&.update!(
            status:
              (
                if error.is_a?(DaemonError) && error.http_status.present?
                  "failed"
                else
                  "submission_unknown"
                end
              ),
            error_code:
              (
                if error.is_a?(DaemonError) && error.http_status.present?
                  "daemon_rejected"
                else
                  "daemon_unreachable"
                end
              ),
            error_message: error.message,
          )
          FailureNotifier.submission_failed(post, task, error)
        rescue StandardError => error
          FailureNotifier.submission_failed(post, submitter&.task, error)
          raise
        end
      end

      def gallery_urls(post)
        return [] if post&.cooked.blank?

        Nokogiri::HTML5
          .fragment(post.cooked)
          .css("a[href]")
          .filter_map do |link|
            next if excluded_link?(link)

            GalleryUrl.canonicalize(link["href"])
          rescue Discourse::InvalidParameters
            nil
          end
          .uniq
      end

      def candidate?(post)
        return false if !SiteSetting.eharchiver_enabled
        return false if post.blank? || post.topic.blank? || post.user.blank?
        return false if post.deleted_at.present? || post.hidden?
        return false if post.topic.private_message?
        return false if post.post_type != Post.types[:regular]

        bot = BotUser.find
        return false if bot.nil? || !bot.active? || bot.suspended?
        return false if post.user_id == bot.id

        post.raw_mentions.include?(bot.username_lower)
      end

      private

      def excluded_link?(link)
        link.ancestors.any? do |ancestor|
          EXCLUDED_LINK_ANCESTORS.include?(ancestor.name) ||
            (ancestor.name == "aside" && ancestor["class"].to_s.split.include?("quote"))
        end
      end
    end
  end
end
