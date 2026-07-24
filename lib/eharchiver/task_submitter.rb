# frozen_string_literal: true

require "digest"

module Eharchiver
  class TaskSubmitter
    attr_reader :task

    def initialize(user:, topic:, gallery_url:, quality: nil, source_post: nil)
      @user = user
      @topic = topic
      @gallery_url = GalleryUrl.canonicalize(gallery_url)
      @quality = quality
      @source_post = source_post
    end

    def submit!
      policy = TaskPolicy.authorize!(user: @user, topic: @topic, quality: @quality)

      DistributedMutex.synchronize(mutex_name) do
        @task = existing_task
        return @task if @task

        create_and_submit!(policy)
      end
    end

    private

    def existing_task
      return if @source_post.nil?

      Task.find_by(source_post_id: @source_post.id, gallery_url: @gallery_url)
    end

    def create_and_submit!(policy)
      task_id = SecureRandom.uuid
      @task =
        Task.create!(
          task_id: task_id,
          user: @user,
          topic: @topic,
          source_post: @source_post,
          gallery_url: @gallery_url,
          quality: policy.quality,
          max_cost_gp: policy.max_cost_gp,
          min_remaining_gp: policy.min_remaining_gp,
          status: "submitting",
        )
      authorization =
        TaskAuthorization.issue(
          task_id: task_id,
          user: @user,
          topic: @topic,
          gallery_url: @gallery_url,
          quality: policy.quality,
          max_cost_gp: policy.max_cost_gp,
          min_remaining_gp: policy.min_remaining_gp,
        )
      @task.apply_daemon_snapshot!(DaemonClient.new.submit(authorization))
    end

    def mutex_name
      identity = @source_post&.id || SecureRandom.uuid
      digest = Digest::SHA256.hexdigest(@gallery_url)
      "eharchiver-submit-#{identity}-#{digest}"
    end
  end
end
