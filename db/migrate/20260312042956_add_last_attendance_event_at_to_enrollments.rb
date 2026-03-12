class AddLastAttendanceEventAtToEnrollments < ActiveRecord::Migration[8.0]
  def change
    add_column :enrollments, :last_attendance_event_at, :date
  end
end
