class DashboardController < ApplicationController
  def current_schedules
    @current_schedules = Schedule
      .includes(:student, :teacher, :enrollment, :attendance)
      .where(lesson_date: Date.today)
      .where(status: %w[scheduled attended late makeup_scheduled])
      .select { |s| s.lesson_time.hour == Time.now.hour }
    render partial: "dashboard/current_schedules"
  end

  def index
    @date     = params[:date].present? ? Date.parse(params[:date]) : Date.today
    @is_today = @date == Date.today
    @current_hour = @is_today ? Time.now.hour : nil

    # 시간표
    @today_schedules = Schedule
      .includes(:student, :teacher, :enrollment)
      .where(lesson_date: @date)
      .where(status: %w[scheduled attended late makeup_scheduled])
      .order(:lesson_time)

    # 보강 일정
    @today_makeups = Schedule
      .includes(:student, :makeup_teacher, :enrollment)
      .where(makeup_date: @date)
      .where(status: %w[makeup_scheduled makeup_done])

    # 현재 시간대 수업 중 (오늘만)
    @current_schedules = @is_today ? @today_schedules.select { |s| s.lesson_time.hour == @current_hour } : []

    # 해당일 마감 집계
    @daily_payments = Payment.where(fully_paid: true).where("DATE(updated_at) = ?", @date)
    @daily_leaves   = Enrollment.where(leave_at: @date)
    @daily_returns  = Enrollment.where(return_at: @date).where(status: "active")
    @daily_dropouts = Enrollment.where(status: "dropout").where("DATE(updated_at) = ?", @date)

    # 개근 달성자
    @attendance_events = Enrollment.where(attendance_event_pending: true).includes(:student)

    # 오늘만: 할 일 목록
    if @is_today
      @payment_due_today = payment_due_list
      @contact_list      = contact_due_list
      @minus_enrollments = Enrollment.includes(:student).where("minus_lesson_count > 0")
      @pending_consents  = Student.where(status: "active").where(consent_form: false)
                                  .or(Student.where(status: "active", second_transfer_form: false, rank: "second"))
    end

    # 선생님별 그룹
    teacher_ids = Schedule.where(lesson_date: @date).distinct.pluck(:teacher_id)
    @teachers_today = Teacher.by_position.where(id: teacher_ids)
  end

  private

  def payment_due_list
    results = []

    # 1. 예약금 미완납 + 오늘 첫 수업
    Payment.where(fully_paid: false, payment_type: "deposit")
           .includes(:student, :enrollment, :schedules)
           .each do |p|
      first_schedule = p.schedules.order(:lesson_date).first
      if first_schedule&.lesson_date == Date.today
        results << { student: p.student, enrollment: p.enrollment, type: :deposit_first_lesson, payment: p }
      end
    end

    # 2. 잔금 미납 (첫 수업 아닌 경우)
    Payment.where(fully_paid: false, payment_type: "deposit")
           .includes(:student, :enrollment, :schedules)
           .each do |p|
      first_schedule = p.schedules.order(:lesson_date).first
      unless first_schedule&.lesson_date == Date.today
        results << { student: p.student, enrollment: p.enrollment, type: :balance_due, payment: p }
      end
    end

    # 3. 잔여 횟수 1회 (완납)
    Enrollment.where(status: "active").includes(:student, :payments).each do |e|
      last_payment = e.payments.where(fully_paid: true).order(:created_at).last
      next unless last_payment
      remaining = last_payment.schedules.where(status: "scheduled").count
      if remaining == 1
        results << { student: e.student, enrollment: e, type: :next_payment_due, payment: last_payment }
      end
    end

    results
  end

  def contact_due_list
    results = []

    # contact_due 도래
    Student.where(contact_due: ..Date.today).where.not(contact_due: nil).each do |s|
      results << { student: s, type: :contact_due }
    end

    # 휴원 복귀 예정일
    Enrollment.where(return_at: ..Date.today).where(status: "leave").includes(:student).each do |e|
      results << { student: e.student, enrollment: e, type: :return_due }
    end

    # 2주 자리대기 만료
    Student.where(status: "pending").where(waiting_expires_at: ..Date.today).each do |s|
      results << { student: s, type: :waiting_expired }
    end

    results
  end
end
