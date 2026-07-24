# frozen_string_literal: true

class AddEharchiverTaskPollTracking < ActiveRecord::Migration[7.2]
  def change
    add_column :eharchiver_tasks, :last_polled_at, :datetime
    add_index :eharchiver_tasks, %i[status last_polled_at]
  end
end
