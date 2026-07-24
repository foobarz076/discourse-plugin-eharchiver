# frozen_string_literal: true

module Eharchiver
  class TasksController < ::ApplicationController
    requires_plugin PLUGIN_NAME

    before_action :ensure_enabled
    before_action :ensure_logged_in

    def create
      params.require(%i[topic_id gallery_url])
      topic = Topic.find(params[:topic_id])
      guardian.ensure_can_see!(topic)
      submitter =
        TaskSubmitter.new(
          user: current_user,
          topic: topic,
          gallery_url: params[:gallery_url],
          quality: params[:quality],
        )
      task = submitter.submit!
      render(
        json: {
          task: TaskSerializer.new(task, scope: guardian, root: false).as_json,
        },
        status: :accepted,
      )
    rescue DaemonError => error
      task ||= submitter&.task
      rejected = error.http_status.present?
      task&.update!(
        status: rejected ? "failed" : "submission_unknown",
        error_code: rejected ? "daemon_rejected" : "daemon_unreachable",
        error_message: error.message,
      )
      response_status = rejected ? :unprocessable_entity : :bad_gateway
      render(
        json: {
          task: task && TaskSerializer.new(task, scope: guardian, root: false).as_json,
          error: error.message,
        },
        status: response_status,
      )
    rescue ConfigurationError => error
      render json: { error: error.message }, status: :service_unavailable
    rescue PolicyDenied => error
      render json: { error: error.message }, status: :forbidden
    end

    def show
      task = find_visible_task
      daemon_reachable = true
      if !task.terminal?
        begin
          task.apply_daemon_snapshot!(DaemonClient.new.task(task.task_id))
        rescue DaemonError, ConfigurationError
          daemon_reachable = false
        end
      end
      render(
        json: {
          task: TaskSerializer.new(task, scope: guardian, root: false).as_json,
          daemon_reachable: daemon_reachable,
        },
      )
    end

    def cancel
      task = find_visible_task
      task.apply_daemon_snapshot!(DaemonClient.new.cancel(task.task_id))
      render(json: { task: TaskSerializer.new(task, scope: guardian, root: false).as_json })
    rescue DaemonError => error
      status = error.http_status == 409 ? :conflict : :bad_gateway
      render json: { error: error.message }, status: status
    rescue ConfigurationError => error
      render json: { error: error.message }, status: :service_unavailable
    end

    private

    def ensure_enabled
      raise Discourse::NotFound if !SiteSetting.eharchiver_enabled
    end

    def find_visible_task
      task = Task.find_by!(task_id: params[:task_id])
      raise Discourse::InvalidAccess if task.user_id != current_user.id && !current_user.staff?

      task
    end
  end
end
