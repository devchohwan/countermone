class AttendanceCheckJob < ApplicationJob
  queue_as :default

  def perform(check_type: "checkin")
    now  = Time.current
    hour = now.hour

    # 브레이크타임(18시) 제외, 운영시간 외 제외
    return if hour == 18
    return if hour < 13
    return if hour > 21

    # 월요일은 14시 이전 제외
    return if Date.today.monday? && hour < 14

    today_schedules = Schedule
      .includes(:student, :attendance, :enrollment)
      .joins(:enrollment)
      .where(lesson_date: Date.today)
      .where("EXTRACT(HOUR FROM lesson_time) = ?", hour)
      .where(status: %w[scheduled attended makeup_scheduled])
      .where(enrollments: { status: "active" })

    today_schedules.each do |schedule|
      if check_type.to_s == "checkin"
        # 정각 지나도 미등원 → 미등원 플래그 (대시보드 실시간 표시용)
        # attendance 없으면 미등원 상태 유지 (대시보드에서 badge-error로 표시)
        # 별도 알림이 필요하면 여기서 Notification 생성 가능
        next if schedule.attendance&.checked_in_at.present?
        # 미등원 상태: schedule.status는 'scheduled' 유지, 대시보드에서 실시간 확인

      elsif check_type.to_s == "checkout"
        # 55분 지나도 하원 미체크 → 대시보드 badge-warning 표시
        next unless schedule.attendance&.checked_in_at.present?
        next if schedule.attendance.checked_out_at.present?
        # 하원 미체크 상태: 대시보드 _current_schedules partial에서 Time.now.min >= 55 로 표시
        # 추가 알림이 필요하면 여기서 처리
      end
    end
  end
end
