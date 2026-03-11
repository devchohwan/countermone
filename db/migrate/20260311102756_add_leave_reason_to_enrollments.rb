class AddLeaveReasonToEnrollments < ActiveRecord::Migration[8.0]
  def change
    add_column :enrollments, :leave_reason, :string
  end
end
