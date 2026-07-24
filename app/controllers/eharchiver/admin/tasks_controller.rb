# frozen_string_literal: true

module Eharchiver
  module Admin
    class TasksController < ::ApplicationController
      requires_plugin PLUGIN_NAME

      before_action :ensure_logged_in
      before_action :ensure_admin

      def index
        filter = params[:status].presence || "all"
        page = Integer(params[:page].presence || 0, exception: false)
        raise Discourse::InvalidParameters.new(:status) if Task::DASHBOARD_FILTERS.exclude?(filter)
        if page.nil? || page.negative? || page > Task::MAX_DASHBOARD_PAGE
          raise Discourse::InvalidParameters.new(:page)
        end

        relation =
          Task
            .for_dashboard_filter(filter)
            .includes(:user, :topic, :source_post, :reply_post, :retry_tasks)
            .order(created_at: :desc, id: :desc)
        tasks =
          relation
            .limit(Task::DASHBOARD_PAGE_SIZE + 1)
            .offset(page * Task::DASHBOARD_PAGE_SIZE)
            .to_a
        has_more = tasks.length > Task::DASHBOARD_PAGE_SIZE
        tasks.pop if has_more

        render json: {
                 tasks:
                   ActiveModel::ArraySerializer.new(
                     tasks,
                     each_serializer: TaskSerializer,
                     scope: guardian,
                   ).as_json,
                 meta: {
                   filter: filter,
                   page: page,
                   has_more: has_more,
                   plugin_enabled: SiteSetting.eharchiver_enabled,
                 },
               }
      end

      def retry
        Task::Retry.call(service_params) do
          on_success do |retry_task:|
            render(
              json: {
                task: TaskSerializer.new(retry_task, scope: guardian, root: false).as_json,
              },
              status: :created,
            )
          end
          on_failed_contract do |contract|
            render_json_error(contract.errors.full_messages, status: :bad_request)
          end
          on_failed_policy(:administrator) { raise Discourse::InvalidAccess }
          on_failed_policy(:plugin_enabled) do
            render_json_error(
              I18n.t("eharchiver.dashboard.errors.plugin_disabled"),
              status: :service_unavailable,
            )
          end
          on_model_not_found(:task) { raise Discourse::NotFound }
          on_failed_policy(:retryable) do
            render_json_error(
              I18n.t("eharchiver.dashboard.errors.not_retryable"),
              status: :conflict,
            )
          end
          on_failed_policy(:requester_still_authorized) do
            render_json_error(
              I18n.t("eharchiver.dashboard.errors.requester_not_authorized"),
              status: :forbidden,
            )
          end
          on_failed_policy(:without_active_retry) do
            render_json_error(I18n.t("eharchiver.dashboard.errors.active_retry"), status: :conflict)
          end
          on_model_errors(:retry_task) do |retry_task|
            render_json_error(retry_task, status: :unprocessable_entity)
          end
          on_failure do
            render_json_error(
              I18n.t("eharchiver.dashboard.errors.retry_failed"),
              status: :unprocessable_entity,
            )
          end
        end
      end
    end
  end
end
