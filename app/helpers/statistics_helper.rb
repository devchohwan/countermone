module StatisticsHelper
  def generate_closing_message(assigns)
    date     = assigns["date"] || Date.today
    tomorrow = date + 1.day
    payments    = assigns["daily_payments"] || []
    first_p     = assigns["first_payments"] || []
    extra_p     = assigns["extra_payments"] || []
    leaves      = assigns["daily_leaves"] || []
    dropouts    = assigns["daily_dropouts"] || []
    returns     = assigns["daily_returns"] || []
    leaves_before = assigns["daily_leaves_before"] || []
    leaves_short  = assigns["daily_leaves_short"]  || []
    leaves_long   = assigns["daily_leaves_long"]   || []
    otto_clean    = assigns["otto_students_clean"]
    otto_nonclean = assigns["otto_students_nonclean"]

    # 익일 결제 예정
    tomorrow_payments = payment_due_tomorrow(tomorrow)
    # 익일 보강 예정
    tomorrow_makeups = Schedule.where(makeup_date: tomorrow)
                               .where(status: "makeup_scheduled")
                               .includes(:student, :makeup_teacher)

    lines = []
    lines << "📊 #{date.strftime('%m/%d(%a)')} 마감"
    lines << ""

    lines << "💳 결제  #{payments.count}건 / #{number_with_delimiter(payments.sum(&:amount))}원"
    lines << "  첫결제 #{first_p.count}건 / 추가 #{extra_p.count}건"
    payments.each do |p|
      lines << "  · #{p.student.name} — #{p.subject} #{p.months}개월 #{number_with_delimiter(p.amount)}원"
    end
    lines << ""

    lines << "📋 휴원/퇴원/복귀"
    lines << "  휴원 #{leaves.count}명 (시작전 #{leaves_before.count} / 3개월이하 #{leaves_short.count} / 3개월초과 #{leaves_long.count})"
    lines << "  퇴원 #{dropouts.count}명 / 복귀 #{returns.count}명"
    lines << ""

    if tomorrow_payments.any?
      lines << "📅 #{tomorrow.strftime('%m/%d')} 결제 예정"
      tomorrow_payments.each do |info|
        lines << "  · #{info[:student].name} — #{info[:enrollment].subject} #{info[:type_label]}"
      end
      lines << ""
    end

    if tomorrow_makeups.any?
      lines << "🔄 #{tomorrow.strftime('%m/%d')} 보강 예정"
      tomorrow_makeups.each do |s|
        teacher_note = s.makeup_teacher ? "(#{s.makeup_teacher.name})" : ""
        lines << "  · #{s.student.name} — #{s.subject} #{teacher_note}"
      end
      lines << ""
    end

    if otto_clean || otto_nonclean
      lines << "👤 오또 재원자"
      lines << "  클린 #{otto_clean || 0}명 / 비클린 #{otto_nonclean || 0}명"
      lines << ""
    end

    lines << "✏️ 특이사항"
    lines << "(직접 입력)"
    lines.join("\n")
  end

  private

  def payment_due_tomorrow(tomorrow)
    results = []

    # 예약금 미완납 + 내일 첫 수업
    Payment.where(fully_paid: false, payment_type: "deposit")
           .includes(:student, :enrollment, :schedules)
           .each do |p|
      first = p.schedules.order(:lesson_date).first
      if first&.lesson_date == tomorrow
        results << { student: p.student, enrollment: p.enrollment, type_label: "예약금 (내일 첫수업)" }
      end
    end

    # 잔여 횟수 1회 → 내일 마지막 수업
    Enrollment.where(status: "active").includes(:student, :payments).each do |e|
      last_p = e.payments.where(fully_paid: true).order(:created_at).last
      next unless last_p
      last_s = last_p.schedules.where(status: "scheduled").order(:lesson_date).first
      if last_s&.lesson_date == tomorrow
        results << { student: e.student, enrollment: e, type_label: "다음 결제 예정 (마지막 수업일)" }
      end
    end

    results
  end
end
