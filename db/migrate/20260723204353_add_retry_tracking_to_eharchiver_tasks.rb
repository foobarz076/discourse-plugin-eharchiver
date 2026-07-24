# frozen_string_literal: true

class AddRetryTrackingToEharchiverTasks < ActiveRecord::Migration[8.0]
  SOURCE_INDEX = "index_eharchiver_tasks_on_source_post_and_gallery"
  ACTIVE_RETRY_INDEX = "index_eharchiver_tasks_on_active_retry"

  def up
    add_column :eharchiver_tasks, :retried_from_task_id, :string, limit: 36

    remove_index :eharchiver_tasks, name: SOURCE_INDEX
    add_index(
      :eharchiver_tasks,
      %i[source_post_id gallery_url],
      unique: true,
      where: "source_post_id IS NOT NULL AND retried_from_task_id IS NULL",
      name: SOURCE_INDEX,
    )
    add_index :eharchiver_tasks, :retried_from_task_id
    add_index(
      :eharchiver_tasks,
      :retried_from_task_id,
      unique: true,
      where: "retried_from_task_id IS NOT NULL AND status NOT IN ('ready', 'failed', 'cancelled')",
      name: ACTIVE_RETRY_INDEX,
    )
  end

  def down
    remove_index :eharchiver_tasks, name: ACTIVE_RETRY_INDEX
    remove_index :eharchiver_tasks, :retried_from_task_id
    remove_index :eharchiver_tasks, name: SOURCE_INDEX
    add_index(
      :eharchiver_tasks,
      %i[source_post_id gallery_url],
      unique: true,
      where: "source_post_id IS NOT NULL",
      name: SOURCE_INDEX,
    )

    remove_column :eharchiver_tasks, :retried_from_task_id
  end
end
