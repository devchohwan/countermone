class KeypadController < ApplicationController
  skip_before_action :require_authentication
  rate_limit to: 60, within: 1.minute, with: -> {
    render json: { error: "요청이 너무 많습니다. 잠시 후 다시 시도하세요." }, status: :too_many_requests
  }

  def index; end

  def checkin
    code     = params[:code]
    student  = Student.find_by(attendance_code: code, status: "active")

    unless student
      render json: { error: "등록되지 않은 코드입니다." }, status: :not_found and return
    end

    now   = Time.current
    today = Date.today

    # 이미 등원했고 하원 안 한 경우 → 하원 처리
    pending_checkout = Attendance.joins(:schedule)
                                 .where(student: student)
                                 .where(schedules: { lesson_date: today })
                                 .where(checked_out_at: nil)
                                 .order(checked_in_at: :desc)
                                 .first
    if pending_checkout
      pending_checkout.update!(checked_out_at: now)
      render json: { message: "하원 처리되었습니다.", student: student.name } and return
    end

    # 클래스 선택 후 schedule_id가 넘어온 경우
    if params[:schedule_id].present?
      schedule = Schedule.find_by(id: params[:schedule_id], student: student,
                                  lesson_date: today, status: %w[scheduled makeup_scheduled])
      unless schedule
        render json: { error: "유효하지 않은 수업입니다." }, status: :not_found and return
      end
      ends = schedule.payment.ends_at
      if ends && Date.today > ends
        render json: { error: "수강 종료일(#{ends.strftime('%m/%d')})이 지났습니다. 상담원에게 문의하세요.", error_type: "expired_date" } and return
      end
      return process_checkin(schedule, now)
    end

    schedules  = Schedule.includes(:enrollment)
                         .where(student: student, lesson_date: today)
                         .where(status: %w[scheduled makeup_scheduled])
                         .where("lesson_time <= ?", now.strftime("%H:%M"))

    if schedules.empty?
      render json: { error: "오늘 해당 시간대 수업이 없습니다." }, status: :not_found and return
    end

    if schedules.count > 1
      render json: {
        action:   "select_class",
        student:  { name: student.name },
        schedules: schedules.map { |s| { id: s.id, subject: s.subject, teacher: s.teacher&.name } }
      } and return
    end

    schedule = schedules.first

    # 수강 종료일 초과 오류 감지
    ends = schedule.payment.ends_at
    if ends && Date.today > ends
      Attendance.create!(
        student: student, schedule: schedule, payment: schedule.payment,
        checked_in_at: now, error_type: "expired_date"
      ) rescue nil
      render json: {
        error: "수강 종료일(#{ends.strftime('%m/%d')})이 지났습니다. 상담원에게 문의하세요.",
        error_type: "expired_date"
      } and return
    end

    process_checkin(schedule, now)
  end

  def checkout
    code    = params[:code]
    student = Student.find_by(attendance_code: code, status: "active")

    unless student
      render json: { error: "등록되지 않은 코드입니다." }, status: :not_found and return
    end

    attendance = Attendance.joins(:schedule)
                           .where(student: student)
                           .where(schedules: { lesson_date: Date.today })
                           .where(checked_out_at: nil)
                           .order(checked_in_at: :desc)
                           .first

    unless attendance
      render json: { error: "하원할 출석 기록이 없습니다." }, status: :not_found and return
    end

    attendance.update!(checked_out_at: Time.current)
    render json: { message: "하원 처리되었습니다.", student: student.name }
  end

  private

  def process_checkin(schedule, time)
    if schedule.attendance.present?
      schedule.attendance.update!(error_type: "double_checkin")
      render json: { error: "이미 출석 처리된 수업입니다. 상담원에게 문의하세요.", error_type: "double_checkin" } and return
    end

    status = time <= Time.parse("#{Date.today} #{schedule.lesson_time.strftime('%H:%M')}") + 1.minute ? "attended" : "late"
    schedule.update!(status: status)
    Attendance.create!(
      student:      schedule.student,
      schedule:     schedule,
      payment:      schedule.payment,
      checked_in_at: time
    )

    render json: {
      message:  "#{status == 'attended' ? '출석' : '지각'} 처리되었습니다.",
      student:  schedule.student.name,
      subject:  schedule.subject,
      sequence: schedule.sequence
    }
  end
end
