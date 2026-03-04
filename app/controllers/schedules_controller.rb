class SchedulesController < ApplicationController
  before_action :set_schedule, only: %i[show edit update destroy attend late absent deduct pass emergency_pass makeup complete_makeup]

  def index
    @schedules = Schedule.includes(:student, :teacher, :enrollment)
                         .where(lesson_date: Date.today)
                         .order(:lesson_time)
  end

  def show; end

  def attend
    @schedule.update!(status: "attended")
    create_attendance_record(@schedule)
    check_consecutive_weeks(@schedule)
    check_gift_voucher(@schedule)
    redirect_back fallback_location: schedules_path, notice: "출석 처리되었습니다."
  end

  def late
    @schedule.update!(status: "late")
    create_attendance_record(@schedule)
    redirect_back fallback_location: schedules_path, notice: "지각 처리되었습니다."
  end

  def absent
    @schedule.update!(status: "absent")
    redirect_back fallback_location: schedules_path, notice: "결강 처리되었습니다."
  end

  def deduct
    @schedule.update!(status: "deducted")
    redirect_back fallback_location: schedules_path, notice: "결석 차감 처리되었습니다."
  end

  def pass
    enrollment = @schedule.enrollment
    available  = available_passes(enrollment)
    if available <= 0
      return redirect_back fallback_location: schedules_path, alert: "잔여 패스가 없습니다."
    end
    if @schedule.lesson_date == Date.today
      return redirect_back fallback_location: schedules_path, alert: "당일 패스는 불가합니다."
    end
    if enrollment.subject == "믹싱"
      return redirect_back fallback_location: schedules_path, alert: "믹싱 수업은 패스 불가합니다."
    end
    @schedule.update!(status: "pass", pass_reason: params[:pass_reason])
    redirect_back fallback_location: schedules_path, notice: "패스 처리되었습니다. 개근 카운트가 리셋됩니다."
  end

  def emergency_pass
    @schedule.update!(status: "emergency_pass", pass_reason: params[:pass_reason])
    redirect_back fallback_location: schedules_path, notice: "긴급패스 처리되었습니다."
  end

  def makeup
    makeup_date = Date.parse(params[:makeup_date])
    makeup_time = params[:makeup_time]
    teacher_id  = params[:makeup_teacher_id]

    range = @schedule.makeup_available_range
    if range && !range.cover?(makeup_date)
      return redirect_back fallback_location: schedules_path, alert: "보강 가능 기간 외입니다. (#{range.first} ~ #{range.last})"
    end

    slot = Schedule.slot_count(teacher_id.to_i, @schedule.subject, makeup_date)
    if slot >= 3
      return redirect_back fallback_location: schedules_path, alert: "해당 슬롯이 이미 3명입니다."
    end

    @schedule.update!(
      status:           "makeup_scheduled",
      makeup_date:      makeup_date,
      makeup_time:      makeup_time,
      makeup_teacher_id: teacher_id
    )
    redirect_back fallback_location: schedules_path, notice: "보강 일정이 등록되었습니다."
  end

  def complete_makeup
    @schedule.update!(status: "makeup_done")
    create_attendance_record(@schedule)
    redirect_back fallback_location: schedules_path, notice: "보강 완료 처리되었습니다."
  end

  private

  def set_schedule
    @schedule = Schedule.find(params[:id])
  end

  def create_attendance_record(schedule)
    schedule.create_attendance!(
      student:      schedule.student,
      payment:      schedule.payment,
      checked_in_at: Time.current
    )
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    # 이미 출석 기록 존재 — 오류 무시
  end

  def available_passes(enrollment)
    total_months = enrollment.payments.where(fully_paid: true).sum(:months)
    used_passes  = enrollment.schedules.where(status: %w[pass emergency_pass]).count
    total_months - used_passes
  end

  def check_consecutive_weeks(schedule)
    enrollment = schedule.enrollment
    count      = enrollment.student.consecutive_weeks_for(enrollment)
    if count >= 12
      enrollment.update!(attendance_event_pending: true)
      # TODO: 상담원 알림 (ActionCable or Notification model)
    end
  end

  def check_gift_voucher(schedule)
    enrollment   = schedule.enrollment
    total_weeks  = enrollment.student.total_attended_weeks_for(enrollment)
    if total_weeks > 0 && (total_weeks % 24).zero?
      GiftVoucher.create!(
        student:    schedule.student,
        enrollment: enrollment,
        issued_at:  Date.today,
        expires_at: Date.today + 6.months
      )
      schedule.student.update!(gift_voucher_issued: true)
      # TODO: 상담원 알림
    end
  end
end
