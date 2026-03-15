module DashboardData
  extend ActiveSupport::Concern

  private

  def todo_panel_data(date)
    today = date
    @payment_due_today = payment_due_list(today)
    @contact_list      = contact_due_list(today)
    @minus_enrollments = Enrollment.includes(:student).where("minus_lesson_count > 0")
    @pending_consents  = Student.where(status: "active").where(consent_form: false)
                                .or(Student.where(status: "active", second_transfer_form: false, rank: "second"))
    @attendance_events = Enrollment.where(attendance_event_pending: true).includes(:student)
    @today_schedules   = arrival_schedules_for(today)
    @today_makeups     = Schedule.includes(:student, :teacher, :makeup_teacher, :enrollment)
                                 .where(makeup_date: today)
                                 .where(status: %w[makeup_scheduled makeup_done])
  end

  def payment_due_list(date)
    results = []

    # 1. 예약금 미완납 + 오늘 첫 수업
    Payment.where(fully_paid: false, payment_type: "deposit")
           .joins(:enrollment)
           .where(enrollments: { status: "active" })
           .includes(:student, :enrollment, :schedules)
           .each do |p|
      first_schedule = p.schedules.order(:lesson_date).first
      relevant_date = first_schedule&.status == "makeup_scheduled" ? first_schedule&.makeup_date : first_schedule&.lesson_date
      if relevant_date == date
        results << { student: p.student, enrollment: p.enrollment, type: :deposit_first_lesson, payment: p }
      end
    end

    # 2. 잔여 횟수 1회(미등원) or 마지막 수업 오늘 등원완료 — 결제 안내 (등하원과 독립)
    Enrollment.where(status: "active").includes(:student, :payments).each do |e|
      next if e.payments.where(fully_paid: false).exists?  # 미완납 결제(예약금 등)가 있으면 건너뜀
      last_payment = e.payments.where(fully_paid: true).order(:created_at).last
      next unless last_payment
      remaining = last_payment.schedules.where(status: %w[scheduled makeup_scheduled])
      if remaining.count == 1
        last_remaining = remaining.first
        relevant_date = last_remaining.status == "makeup_scheduled" ? last_remaining.makeup_date : last_remaining.lesson_date
        next unless relevant_date == date
      elsif remaining.count == 0
        # 이미 등원 처리된 경우: 오늘 마지막 수업(정규 or 보강)을 출석했으면 여전히 표시
        today_done = last_payment.schedules.where(lesson_date: date, status: %w[attended late]).exists? ||
                     last_payment.schedules.where(makeup_date: date, status: "makeup_done").exists?
        next unless today_done
      else
        next
      end
      results << { student: e.student, enrollment: e, type: :next_payment_due, payment: last_payment }
    end

    # 3. 오늘 체험수업 대상자
    Schedule.where(lesson_date: date, trial: true, status: %w[scheduled attended late])
            .includes(:student, :enrollment)
            .each do |s|
      results << { student: s.student, enrollment: s.enrollment, type: :trial_lesson, schedule: s }
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

  def arrival_schedules_for(date)
    regular  = Schedule.includes(:student, :teacher, :makeup_teacher, :enrollment, :attendance)
                       .joins(:enrollment, :teacher)
                       .where(lesson_date: date, status: %w[scheduled attended late])
                       .where(enrollments: { status: "active" })
                       .where(teachers: { military: false })
    trial    = Schedule.includes(:student, :teacher, :enrollment, :attendance)
                       .where(lesson_date: date, trial: true, status: %w[scheduled attended late])
    same_day = Schedule.includes(:student, :teacher, :makeup_teacher, :enrollment, :attendance)
                       .joins(:enrollment)
                       .where(makeup_date: date, status: %w[makeup_scheduled makeup_done])
                       .where(enrollments: { status: "active" })
    (regular.to_a + trial.to_a + same_day.to_a).uniq(&:id).sort_by do |s|
      if s.status.in?(%w[makeup_scheduled makeup_done])
        [s.makeup_time&.hour.to_i, s.makeup_time&.min.to_i]
      else
        t = s.lesson_time.in_time_zone('Seoul')
        [t.hour, t.min]
      end
    end
  end
end
