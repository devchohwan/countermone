class AddMaxLessonHourToTeachers < ActiveRecord::Migration[8.0]
  def change
    add_column :teachers, :max_lesson_hour, :integer, default: 21, null: false
  end
end
