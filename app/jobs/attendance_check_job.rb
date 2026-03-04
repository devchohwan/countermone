class AttendanceCheckJob < ApplicationJob
  queue_as :default

  def perform(check_type: :checkin)
    now  = Time.current
    hour = now.hour
    return if hour == 18 # 브레이크타임 제외

    today_schedules = Schedule
      .includes(:student, :attendance)
      .where(lesson_date: Date.today, lesson_time: Time.current.change(min: 0)..Time.current.change(min: 59))

    today_schedules.each do |schedule|
      if check_type == :checkin
        # 정각 지나도 checked_in_at nil → 미등원 강조 (대시보드에서 처리)
        next if schedule.attendance&.checked_in_at
        # 미등원 표시는 대시보드에서 실시간으로 처리됨
      elsif check_type == :checkout
        # 55분 이후 checked_out_at nil → 하원 미체크 알림
        next unless schedule.attendance&.checked_in_at
        next if schedule.attendance&.checked_out_at
        # 하원 미체크 강조 처리 (대시보드 실시간 렌더링)
      end
    end
  end
end
