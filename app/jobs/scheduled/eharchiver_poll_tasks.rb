# frozen_string_literal: true

module Jobs
  class EharchiverPollTasks < ::Jobs::Scheduled
    every 10.seconds

    def execute(_args)
      return if !SiteSetting.eharchiver_enabled

      cutoff = SiteSetting.eharchiver_status_poll_interval_seconds.seconds.ago
      Eharchiver::Task
        .active
        .where("COALESCE(last_polled_at, created_at) <= ?", cutoff)
        .limit(50)
        .find_each do |task|
          begin
            snapshot = Eharchiver::DaemonClient.new.task(task.task_id)
            task.apply_daemon_snapshot!(snapshot)
          rescue Eharchiver::DaemonError => error
            if error.http_status == 404 && task.status == "submission_unknown" &&
                 task.created_at <= SiteSetting.eharchiver_task_token_ttl_seconds.seconds.ago
              task.update!(
                status: "failed",
                error_code: "submission_not_found",
                error_message:
                  "The daemon did not accept this task before its authorization expired.",
              )
              Jobs.enqueue(:eharchiver_notify_failure, task_id: task.task_id)
            end
          rescue Eharchiver::Error
            next
          ensure
            task.update_column(:last_polled_at, Time.zone.now)
          end
        end
    end
  end
end
