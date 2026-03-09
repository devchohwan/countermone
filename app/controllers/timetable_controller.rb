class TimetableController < ApplicationController
  def index
    first_teacher = Teacher.by_position.first
    redirect_to teacher_timetable_path(first_teacher.id, date: params[:date])
  end

  def show
    @teachers   = Teacher.by_position
    @teacher    = Teacher.find(params[:teacher_id])
    @date       = params[:date] ? Date.parse(params[:date]) : Date.today
    @week_start = @date.beginning_of_week(:monday)
    @week_days  = (0..6).map { |i| @week_start + i.days }
    @schedule_data = weekly_schedules_for(@teacher, @week_days)
    @breaktime_openings = BreaktimeOpening.where(teacher: @teacher, date: @week_days).pluck(:date)
  end

  def pass_sheet
    @teachers = Teacher.by_position
    @month    = params[:month] ? Date.parse("#{params[:month]}-01") : Date.today.beginning_of_month
    range     = @month.beginning_of_month..@month.end_of_month

    @pass_data = @teachers.map do |teacher|
      passes = Schedule.includes(:student, :enrollment)
                       .where(teacher: teacher, lesson_date: range)
                       .where(status: %w[pass emergency_pass holiday])
                       .order(:lesson_date)
      { teacher: teacher, passes: passes }
    end.reject { |d| d[:passes].empty? }
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
