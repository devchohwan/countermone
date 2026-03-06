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
      .includes(:student, :teacher, :makeup_teacher, :enrollment)
      .where(makeup_date: @date)
      .where(status: %w[makeup_scheduled makeup_done])
      .order(:makeup_time)

    # 잔여 횟수 배치 조회 (N+1 방지)
    enrollment_ids = (@today_schedules.map(&:enrollment_id) + @today_makeups.map(&:enrollment_id)).uniq
    @remaining_by_enrollment = Schedule
      .where(enrollment_id: enrollment_ids, status: "scheduled")
      .group(:enrollment_id).count

    # 오늘만: 결제 예정
    @payment_due_today = @is_today ? payment_due_list : []

    # 선생님 정렬 (regular + makeup 포함)
    teacher_ids = (@today_schedules.map(&:teacher_id) + @today_makeups.map(&:makeup_teacher_id)).uniq
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
end
