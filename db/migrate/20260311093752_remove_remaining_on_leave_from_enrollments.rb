class RemoveRemainingOnLeaveFromEnrollments < ActiveRecord::Migration[8.0]
  def change
    remove_column :enrollments, :remaining_on_leave, :integer
  end
end
