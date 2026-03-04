class CreateEnrollments < ActiveRecord::Migration[8.0]
  def change
    create_table :enrollments do |t|
      t.references :student,  null: false, foreign_key: true
      t.references :teacher,  null: false, foreign_key: true
      t.string  :subject,                   null: false
      t.string  :lesson_day,                null: false
      t.time    :lesson_time,               null: false
      t.string  :status,                    null: false, default: "active"
      t.date    :leave_at
      t.date    :return_at
      t.integer :remaining_on_leave,        default: 0
      t.integer :minus_lesson_count,        default: 0
      t.boolean :attendance_event_pending,  default: false
      t.timestamps
    end
  end
end
