# frozen_string_literal: true

module Eharchiver
  class Task
    module Action
      class Dispatch < Service::ActionBase
        option :task

        def call
          authorization =
            TaskAuthorization.issue(
              task_id: task.task_id,
              user: task.user,
              topic: task.topic,
              gallery_url: task.gallery_url,
              quality: task.quality,
              max_cost_gp: task.max_cost_gp,
              min_remaining_gp: task.min_remaining_gp,
            )
          task.apply_daemon_snapshot!(DaemonClient.new.submit(authorization))
          task
        rescue DaemonError, ConfigurationError => error
          rejected = error.is_a?(DaemonError) && error.http_status.present?
          task.update!(
            status: rejected ? "failed" : "submission_unknown",
            error_code: rejected ? "daemon_rejected" : "daemon_unreachable",
            error_message: error.message,
          )
          task
        end
      end
    end
  end
end
