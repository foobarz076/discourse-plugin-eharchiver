# frozen_string_literal: true

class AddDeliveryToEharchiverTasks < ActiveRecord::Migration[7.2]
  def change
    add_column :eharchiver_tasks, :source_post_id, :bigint
    add_column :eharchiver_tasks, :reply_post_id, :bigint

    add_index :eharchiver_tasks, :source_post_id
    add_index :eharchiver_tasks, :reply_post_id, unique: true
    add_index(
      :eharchiver_tasks,
      %i[source_post_id gallery_url],
      unique: true,
      where: "source_post_id IS NOT NULL",
      name: "index_eharchiver_tasks_on_source_post_and_gallery",
    )
    add_foreign_key :eharchiver_tasks, :posts, column: :source_post_id, on_delete: :nullify
    add_foreign_key :eharchiver_tasks, :posts, column: :reply_post_id, on_delete: :nullify
  end
end
