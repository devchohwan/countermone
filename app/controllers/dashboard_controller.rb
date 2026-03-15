class DashboardController < ApplicationController
  include DashboardData

  def today_arrivals
    effective = Time.current.hour >= 21 ? Date.tomorrow : Date.today
    render partial: "dashboard/hourly_arrival_text", locals: { schedules: arrival_schedules_for(effective) }
  end

  def current_schedules
    effective = params[:date].present? ? Date.parse(params[:date]) : (Time.current.hour >= 21 ? Date.tomorrow : Date.today)
    @current_date = effective
    @current_schedules = Schedule
      .includes(:student, :teacher, :enrollment, :attendance)
      .joins(:teacher)
      .where(lesson_date: effective)
      .where(status: %w[scheduled attended late])
      .where(teachers: { military: false })
      .select { |s| s.lesson_time.in_time_zone('Seoul').hour == Time.current.hour }
    render partial: "dashboard/current_schedules"
  end

  def index
    effective_today  = Time.current.hour >= 21 ? Date.tomorrow : Date.today
    @date            = params[:date].present? ? Date.parse(params[:date]) : effective_today
    @dual_date_mode  = Time.current.hour >= 21 || Time.current.hour < 3  # 21:00~02:59: 오늘·내일 동시 처리 구간
    @prev_date       = effective_today - 1.day
    @is_today        = @date == effective_today || (@dual_date_mode && @date == @prev_date)
    @effective_today = effective_today
    @current_hour    = @is_today ? Time.current.hour : nil
    @current_date    = @date

    # 시간표 (당일 보강 포함)
    @today_schedules = arrival_schedules_for(@date)

    # 보강 일정 (당일 보강은 시간대별 등하원에도 표시되지만, 보강 섹션에서도 유지)
    @today_makeups = Schedule
      .includes(:student, :teacher, :makeup_teacher, :enrollment)
      .where(makeup_date: @date)
      .where(status: %w[makeup_scheduled makeup_done])

    # 현재 시간대 수업 중 (오늘만)
    @current_schedules = @is_today ? @today_schedules.select { |s|
      hour = s.status.in?(%w[makeup_scheduled makeup_done]) ? s.makeup_time&.hour.to_i : s.lesson_time.in_time_zone('Seoul').hour
      hour == @current_hour
    } : []

    # 시간대별 수업 텍스트용: 당일 결석차감 수업
    @today_deducted = Schedule.includes(:student, :teacher, :enrollment)
                              .joins(:enrollment, :teacher)
                              .where(lesson_date: @date, status: "deducted")
                              .where(enrollments: { status: "active" })
                              .where(teachers: { military: false })

    # 시간대별 수업 텍스트용: 당일 패스/긴급패스/공휴일/보강등록 처리된 수업
    raw_passed = Schedule.includes(:student, :teacher, :enrollment)
                         .joins(:enrollment, :teacher)
                         .where(lesson_date: @date, status: %w[pass emergency_pass holiday makeup_scheduled])
                         .where(enrollments: { status: "active" })
                         .where(teachers: { military: false })
                         .where(trial: false)
    @today_passed = raw_passed.to_a.reject { |s| s.status == "makeup_scheduled" && s.makeup_date == @date }

    # 시간대별 수업 텍스트용: 수강권별 잔여 scheduled 횟수 (정규 + 보강 모두 포함)
    enrollment_ids = (@today_schedules + @today_makeups + @today_deducted.to_a + @today_passed).map(&:enrollment_id).uniq
    @enrollment_remaining = Schedule.where(enrollment_id: enrollment_ids, status: %w[scheduled makeup_scheduled], trial: false)
                                    .group(:enrollment_id).count

    # 해당일 마감 집계
    @daily_payments = Payment.where(created_at: @date.all_day).includes(:student)
    daily_leaves    = Enrollment.includes(:student, :schedules).where(leave_at: @date)
    @daily_leaves_short = daily_leaves.select { |e| e.student.total_attended_weeks_for(e) <= 12 }
    @daily_leaves_long  = daily_leaves.select { |e| e.student.total_attended_weeks_for(e) > 12 }
    @daily_returns  = Enrollment.where(return_at: @date).where(status: "active")

    # 개근 달성자
    @attendance_events = Enrollment.where(attendance_event_pending: true).includes(:student)

    # 오늘만: 할 일 목록
    if @is_today
      @payment_due_today = payment_due_list(@date)
      @contact_list      = contact_due_list(@date)
      @minus_enrollments = Enrollment.includes(:student).where("minus_lesson_count > 0")
      @pending_consents  = Student.where(status: "active").where(consent_form: false)
                                  .or(Student.where(status: "active", second_transfer_form: false, rank: "second"))
    end

    # 선생님별 그룹
    teacher_ids = Schedule.where(lesson_date: @date).distinct.pluck(:teacher_id)
    @teachers_today = Teacher.by_position.where(id: teacher_ids)
  end

  def refresh_panels
    date = Date.today
    daily_payments = Payment.where(created_at: date.all_day).includes(:student)
    todo_panel_data(date)
    render turbo_stream: [
      turbo_stream.replace("daily_payments",
        partial: "dashboard/daily_payments",
        locals: { daily_payments: daily_payments }),
      turbo_stream.replace("todo_panel",
        partial: "dashboard/todo_panel")
    ]
  end
end
