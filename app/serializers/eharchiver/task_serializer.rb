# frozen_string_literal: true

module Eharchiver
  class TaskSerializer < ApplicationSerializer
    attributes :task_id,
               :topic_id,
               :requester_user_id,
               :gallery_url,
               :quality,
               :max_cost_gp,
               :min_remaining_gp,
               :status,
               :status_version,
               :stage,
               :terminal,
               :retryable,
               :cost_gp,
               :artifact_size_bytes,
               :artifact_sha256,
               :source_post_id,
               :reply_post_id,
               :retried_from_task_id,
               :source_url,
               :result_url,
               :error_code,
               :error_message,
               :created_at,
               :updated_at

    has_one :user, serializer: BasicUserSerializer, embed: :objects
    has_one :topic, serializer: BasicTopicSerializer, embed: :objects

    def requester_user_id
      object.user_id
    end

    def status_version
      object.daemon_status_version
    end

    def stage
      object.dashboard_stage
    end

    def terminal
      object.terminal?
    end

    def retryable
      object.retryable?
    end

    def source_url
      object.source_post&.url || object.topic.relative_url
    end

    def result_url
      object.reply_post&.url
    end

    def include_result_url?
      object.reply_post_id.present?
    end

    def created_at
      object.created_at&.iso8601
    end

    def updated_at
      object.updated_at&.iso8601
    end
  end
end
