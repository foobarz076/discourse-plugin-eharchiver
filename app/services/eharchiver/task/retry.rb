# frozen_string_literal: true

module Eharchiver
  class Task::Retry
    include Service::Base

    params do
      attribute :task_id, :string

      validates :task_id,
                presence: true,
                format: {
                  with:
                    /\A[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i,
                }
    end

    policy :administrator
    policy :plugin_enabled
    model :task
    policy :retryable
    policy :requester_still_authorized

    lock :task do
      policy :without_active_retry
      model :retry_task, :create_retry_task
    end

    step :dispatch_retry

    private

    def administrator(guardian:)
      guardian.is_admin?
    end

    def plugin_enabled
      SiteSetting.eharchiver_enabled
    end

    def fetch_task(params:)
      Task.find_by(task_id: params.task_id)
    end

    def retryable(task:)
      task.retryable?
    end

    def requester_still_authorized(task:)
      TaskPolicy.authorize!(user: task.user, topic: task.topic, quality: task.quality)
      true
    rescue PolicyDenied, Discourse::InvalidParameters
      false
    end

    def without_active_retry(task:)
      !task.active_retry?
    end

    def create_retry_task(task:)
      policy = TaskPolicy.authorize!(user: task.user, topic: task.topic, quality: task.quality)
      Task.create(
        task_id: SecureRandom.uuid,
        user: task.user,
        topic: task.topic,
        source_post: task.source_post,
        retried_from_task: task,
        gallery_url: task.gallery_url,
        quality: policy.quality,
        max_cost_gp: policy.max_cost_gp,
        min_remaining_gp: policy.min_remaining_gp,
        status: "submitting",
      )
    end

    def dispatch_retry(retry_task:)
      Task::Action::Dispatch.call(task: retry_task)
    end
  end
end
