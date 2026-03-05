class AddFromPassToSchedules < ActiveRecord::Migration[8.0]
  def change
    add_column :schedules, :from_pass, :boolean, default: false
  end
end
