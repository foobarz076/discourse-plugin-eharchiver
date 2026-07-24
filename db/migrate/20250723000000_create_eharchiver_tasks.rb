# frozen_string_literal: true

class CreateEharchiverTasks < ActiveRecord::Migration[7.2]
  def change
    create_table :eharchiver_tasks do |t|
      t.string :task_id, null: false, limit: 36
      t.bigint :user_id, null: false
      t.bigint :topic_id, null: false
      t.text :gallery_url, null: false
      t.string :quality, null: false, limit: 16
      t.integer :max_cost_gp, null: false, default: 0
      t.integer :min_remaining_gp, null: false, default: 0
      t.string :status, null: false, limit: 32
      t.integer :daemon_status_version, null: false, default: 0
      t.datetime :daemon_updated_at
      t.integer :cost_gp
      t.bigint :artifact_size_bytes
      t.string :artifact_sha256, limit: 64
      t.string :error_code, limit: 100
      t.text :error_message
      t.timestamps null: false
    end

    add_index :eharchiver_tasks, :task_id, unique: true
    add_index :eharchiver_tasks, %i[user_id created_at]
    add_index :eharchiver_tasks, %i[status updated_at]
    add_foreign_key :eharchiver_tasks, :users, column: :user_id
    add_foreign_key :eharchiver_tasks, :topics, column: :topic_id
  end
end
