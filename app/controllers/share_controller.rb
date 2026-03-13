class ShareController < ApplicationController
  skip_before_action :require_authentication
  layout "share"

  def timetable
    @teacher    = Teacher.find(params[:teacher_id])
    @date       = params[:date] ? Date.parse(params[:date]) : Date.today
    @week_start = @date.beginning_of_week(:monday)
    @week_days  = (0..6).map { |i| @week_start + i.days }
    @schedule_data = weekly_schedules_for(@teacher, @week_days)
  end

  private

  def weekly_schedules_for(teacher, week_days)
    regular = Schedule
      .includes(:student, :enrollment, :teacher)
      .joins(:enrollment)
      .where(teacher: teacher, lesson_date: week_days)
      .where(status: %w[scheduled attended late pass emergency_pass holiday makeup_scheduled])
      .where(enrollments: { status: "active" })

    makeups = Schedule
      .includes(:student, :enrollment, :makeup_teacher)
      .where(makeup_teacher: teacher, makeup_date: week_days)
      .where(status: %w[makeup_scheduled makeup_done])

    { regular: regular, makeups: makeups }
  end
end
