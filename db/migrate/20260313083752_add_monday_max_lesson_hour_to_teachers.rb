class AddMondayMaxLessonHourToTeachers < ActiveRecord::Migration[8.0]
  def change
    add_column :teachers, :monday_max_lesson_hour, :integer, default: 17, null: false
  end
end
