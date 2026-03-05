class ContactDueJob < ApplicationJob
  queue_as :default

  def perform
    # contact_due 당일 도래 수강생 → 연락할 리스트 자동 등록 (이미 오늘로 설정된 경우 skip)
    # contact_due가 오늘이면 대시보드 연락 탭에 자동 표시됨 (별도 처리 불필요)
    # 단, 오늘 contact_due인데 status가 leave/dropout이면 알림만
    Student.where(contact_due: Date.today)
           .where(status: %w[active leave pending])
           .each do |student|
      # 연락 기록이 필요한 경우 NotificationRecord 등으로 확장 가능
      # 현재는 contact_due 필드 자체가 연락할 리스트 역할
      # review_due 도래 + review_url 미입력이면 contact_due 갱신
      if student.review_due.present? && student.review_due <= Date.today && student.review_url.blank?
        student.update_column(:contact_due, Date.today)
      end
    end

    # waiting_expires_at 도래 수강생 → contact_due 등록 (WaitingExpiryJob과 별도)
    Student.where(status: "pending")
           .where(waiting_expires_at: Date.today)
           .each do |student|
      student.update_column(:contact_due, Date.today)
    end
  end
end
