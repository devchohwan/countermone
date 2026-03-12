class DashboardController < ApplicationController
  def today_arrivals
    effective = Time.current.hour >= 22 ? Date.tomorrow : Date.today
    @today_schedules = Schedule
      .includes(:student, :teacher, :enrollment, :attendance)
      .where(lesson_date: effective)
      .where(status: %w[scheduled attended late makeup_scheduled])
      .order(:lesson_time)
    render partial: "dashboard/hourly_arrival_text", locals: { schedules: @today_schedules }
  end

  def current_schedules
    effective = Time.current.hour >= 22 ? Date.tomorrow : Date.today
    @current_schedules = Schedule
      .includes(:student, :teacher, :enrollment, :attendance)
      .where(lesson_date: effective)
      .where(status: %w[scheduled attended late makeup_scheduled])
      .select { |s| s.lesson_time.in_time_zone('Seoul').hour == Time.current.hour }
    render partial: "dashboard/current_schedules"
  end

  def index
    effective_today = Time.current.hour >= 22 ? Date.tomorrow : Date.today
    @date        = params[:date].present? ? Date.parse(params[:date]) : effective_today
    @is_today    = @date == effective_today
    @current_hour = @date == Date.today ? Time.current.hour : nil

    # 시간표
    @today_schedules = Schedule
      .includes(:student, :teacher, :enrollment, :attendance)
      .where(lesson_date: @date)
      .where(status: %w[scheduled attended late makeup_scheduled])
      .order(:lesson_time)


    # 보강 일정
    @today_makeups = Schedule
      .includes(:student, :makeup_teacher, :enrollment)
      .where(makeup_date: @date)
      .where(status: %w[makeup_scheduled makeup_done])

    # 현재 시간대 수업 중 (오늘만)
    @current_schedules = @is_today ? @today_schedules.select { |s| s.lesson_time.in_time_zone('Seoul').hour == @current_hour } : []

    # 시간대별 수업 텍스트용: 수강권별 잔여 scheduled 횟수 (정규 + 보강 모두 포함)
    enrollment_ids = (@today_schedules + @today_makeups).map(&:enrollment_id).uniq
    @enrollment_remaining = Schedule.where(enrollment_id: enrollment_ids, status: "scheduled")
                                    .group(:enrollment_id).count

    # 해당일 마감 집계
    @daily_payments = Payment.where(fully_paid: true).where("DATE(updated_at) = ?", @date).includes(:student)
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

  private

  def payment_due_list(date)
    results = []

    # 1. 예약금 미완납 + 오늘 첫 수업
    Payment.where(fully_paid: false, payment_type: "deposit")
           .includes(:student, :enrollment, :schedules)
           .each do |p|
      first_schedule = p.schedules.order(:lesson_date).first
      if first_schedule&.lesson_date == date
        results << { student: p.student, enrollment: p.enrollment, type: :deposit_first_lesson, payment: p }
      end
    end

    # 2. 잔여 횟수 1회 + 마지막 수업이 오늘인 경우 (완납)
    Enrollment.where(status: "active").includes(:student, :payments).each do |e|
      last_payment = e.payments.where(fully_paid: true).order(:created_at).last
      next unless last_payment
      last_scheduled = last_payment.schedules.where(status: "scheduled").order(:lesson_date).first
      next unless last_scheduled&.lesson_date == date
      next unless last_payment.schedules.where(status: "scheduled").count == 1
      results << { student: e.student, enrollment: e, type: :next_payment_due, payment: last_payment }
    end

    results
  end

  def contact_due_list(date)
    results = []

    # contact_due 도래
    Student.where(contact_due: ..date).where.not(contact_due: nil).each do |s|
      results << { student: s, type: :contact_due }
    end

    # 휴원 복귀 예정일
    Enrollment.where(return_at: ..date).where(status: "leave").includes(:student).each do |e|
      results << { student: e.student, enrollment: e, type: :return_due }
    end

    # 2주 자리대기 만료
    Student.where(status: "pending").where(waiting_expires_at: ..date).each do |s|
      results << { student: s, type: :waiting_expired }
    end

    results
  end
end
