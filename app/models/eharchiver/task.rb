# frozen_string_literal: true

module Eharchiver
  class Task < ActiveRecord::Base
    self.table_name = "eharchiver_tasks"

    TERMINAL_STATUSES = %w[ready failed cancelled].freeze
    DAEMON_STATUSES = %w[queued downloading ready failed cancelled].freeze
    ACTIVE_STATUSES = %w[submitting submission_unknown queued downloading].freeze
    DASHBOARD_FILTERS = %w[all active failed completed].freeze
    DASHBOARD_PAGE_SIZE = 50
    MAX_DASHBOARD_PAGE = 10_000

    belongs_to :user
    belongs_to :topic, -> { with_deleted }
    belongs_to :source_post, -> { with_deleted }, class_name: "Post", optional: true
    belongs_to :reply_post, -> { with_deleted }, class_name: "Post", optional: true
    belongs_to :retried_from_task,
               class_name: "Eharchiver::Task",
               foreign_key: :retried_from_task_id,
               primary_key: :task_id,
               optional: true
    has_many :retry_tasks,
             class_name: "Eharchiver::Task",
             foreign_key: :retried_from_task_id,
             primary_key: :task_id

    validates :task_id, presence: true, uniqueness: true
    validates :gallery_url, :quality, :status, presence: true
    validates :max_cost_gp,
              :min_remaining_gp,
              numericality: {
                only_integer: true,
                greater_than_or_equal_to: 0,
              }

    scope :active, -> { where.not(status: TERMINAL_STATUSES) }
    scope :for_dashboard_filter,
          ->(filter) do
            case filter
            when "active"
              where(status: ACTIVE_STATUSES)
            when "failed"
              where(status: "failed")
            when "completed"
              where(status: "ready")
            else
              all
            end
          end

    def terminal?
      TERMINAL_STATUSES.include?(status)
    end

    def retryable?
      status == "failed" && !active_retry?
    end

    def active_retry?
      if retry_tasks.loaded?
        retry_tasks.any? { |retry_task| !retry_task.terminal? }
      else
        retry_tasks.active.exists?
      end
    end

    def dashboard_stage
      case status
      when "submitting"
        "submitting"
      when "submission_unknown"
        "confirming"
      when "queued"
        "queued"
      when "downloading"
        "downloading"
      when "ready"
        reply_post_id.present? ? "completed" : "publishing"
      when "failed"
        "failed"
      when "cancelled"
        "cancelled"
      else
        "unknown"
      end
    end

    def apply_daemon_snapshot!(snapshot)
      raise DaemonError, "Daemon task identity does not match." if snapshot["task_id"] != task_id
      validate_snapshot_identity!(snapshot)

      daemon_status = snapshot["status"]
      version = Integer(snapshot["status_version"], exception: false)
      if DAEMON_STATUSES.exclude?(daemon_status) || version.nil? || version <= 0
        raise DaemonError, "Daemon returned an invalid task snapshot."
      end
      return self if version <= daemon_status_version

      remote_error = snapshot["error"].is_a?(Hash) ? snapshot["error"] : {}
      result = snapshot["result"].is_a?(Hash) ? snapshot["result"] : {}
      validate_result!(daemon_status, result)
      update!(
        status: daemon_status,
        daemon_status_version: version,
        daemon_updated_at: parse_time(snapshot["updated_at"]),
        cost_gp: result["cost_gp"],
        artifact_size_bytes: result["size_bytes"],
        artifact_sha256: result["sha256"],
        error_code: remote_error["code"],
        error_message: remote_error["message"],
      )
      enqueue_lifecycle_job
      self
    end

    private

    def enqueue_lifecycle_job
      case status
      when "ready"
        Jobs.enqueue(:eharchiver_finalize_task, task_id: task_id)
      when "failed"
        Jobs.enqueue(:eharchiver_notify_failure, task_id: task_id)
      end
    end

    def validate_snapshot_identity!(snapshot)
      matches =
        Integer(snapshot["requester_user_id"], exception: false) == user_id &&
          Integer(snapshot["topic_id"], exception: false) == topic_id &&
          snapshot["gallery_url"] == gallery_url && snapshot["quality"] == quality
      raise DaemonError, "Daemon task fields do not match the local authorization." if !matches
    end

    def validate_result!(daemon_status, result)
      return if daemon_status != "ready"

      size = Integer(result["size_bytes"], exception: false)
      cost = Integer(result["cost_gp"], exception: false)
      sha256 = result["sha256"].to_s
      if size.nil? || size <= 0 || cost.nil? || cost < 0 || !/\A[0-9a-f]{64}\z/.match?(sha256)
        raise DaemonError, "Daemon returned an invalid artifact result."
      end
    end

    def parse_time(value)
      parsed = Time.iso8601(value) if value.present?
      raise DaemonError, "Daemon returned an invalid task timestamp." if parsed.nil?

      parsed
    rescue ArgumentError
      raise DaemonError, "Daemon returned an invalid task timestamp."
    end
  end
end
