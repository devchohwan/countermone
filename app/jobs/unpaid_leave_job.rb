class UnpaidLeaveJob < ApplicationJob
  queue_as :default

  def perform
    # 연장결제 연락두절 수강생 → 상담원 알림 (휴원 수동 처리 유도)
    # 조건: status=active, 마지막 결제의 ends_at이 오늘 이전, 잔여 scheduled 없음
    Enrollment.where(status: "active").includes(:student, :payments).each do |enrollment|
      last_payment = enrollment.payments.where(fully_paid: true).order(:starts_at).last
      next unless last_payment

      ends = last_payment.ends_at
      next unless ends.present? && ends < Date.today

      remaining = last_payment.schedules.where(status: "scheduled").count
      next unless remaining == 0

      # contact_due가 없거나 오래됐으면 오늘로 설정 → 대시보드 연락할 탭에 표시
      student = enrollment.student
      if student.contact_due.nil? || student.contact_due < Date.today - 7.days
        student.update_column(:contact_due, Date.today)
      end
    end
  end
end
