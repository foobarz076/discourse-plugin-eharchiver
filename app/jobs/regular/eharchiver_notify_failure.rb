# frozen_string_literal: true

module Jobs
  class EharchiverNotifyFailure < ::Jobs::Base
    def execute(args)
      task = Eharchiver::Task.find_by(task_id: args[:task_id])
      Eharchiver::FailureNotifier.task_failed(task) if task&.status == "failed"
    end
  end
end
