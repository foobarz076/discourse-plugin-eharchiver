# frozen_string_literal: true

module Jobs
  class EharchiverFinalizeTask < ::Jobs::Base
    def execute(args)
      task = Eharchiver::Task.find_by(task_id: args[:task_id])
      return if task.nil? || task.status != "ready" || task.reply_post_id.present?

      Eharchiver::ArtifactReply.publish!(task)
    rescue StandardError => error
      Eharchiver::FailureNotifier.delivery_failed(task, error) if task
      raise
    end
  end
end
