class SchedulesController < ApplicationController
  before_action :set_schedule, only: %i[show attend checkout late deduct pass emergency_pass holiday makeup approve_makeup complete_makeup undo_deduct undo_attend makeup_slots cancel_pass]

  def index
    date = params[:date] ? Date.parse(params[:date]) : Date.today
    @schedules = Schedule.includes(:student, :teacher, :enrollment, :attendance)
                         .where(lesson_date: date)
                         .where(status: %w[scheduled attended late makeup_scheduled makeup_done deducted])
                         .order(:lesson_time)
  end

  def show; end

  def attend
    # 완납필요: 예약금 미완납 + 첫 수업이면 등원 차단
    if @schedule.payment.fully_paid == false && @schedule.payment.payment_type == "deposit"
      first = @schedule.payment.schedules.order(:lesson_date, :id).first
      if first&.id == @schedule.id
        return redirect_back fallback_location: root_path, alert: "완납 후 등원 처리 가능합니다."
      end
    end

    remove_pass_schedule_if_needed(@schedule)
    @schedule.update!(status: "attended")
    create_attendance_record(@schedule)
    check_consecutive_weeks(@schedule)
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.replace("current_schedules", partial: "dashboard/current_schedules"),
          turbo_stream.replace("hourly_arrival",    partial: "dashboard/hourly_arrival_text",
                               locals: { schedules: today_arrival_schedules })
        ]
      end
      format.html { tab_redirect(notice: "출석 처리되었습니다.") }
    end
  end

  def checkout
    attendance = @schedule.attendance
    if attendance
      attendance.update!(checked_out_at: Time.current)
    end
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.replace("current_schedules", partial: "dashboard/current_schedules"),
          turbo_stream.replace("hourly_arrival",    partial: "dashboard/hourly_arrival_text",
                               locals: { schedules: today_arrival_schedules })
        ]
      end
      format.html { redirect_back fallback_location: root_path, notice: "하원 처리되었습니다." }
    end
  end

  def late
    remove_pass_schedule_if_needed(@schedule)
    @schedule.update!(status: "late")
    create_attendance_record(@schedule)
    tab_redirect(notice: "지각 처리되었습니다.")
  end

  def deduct
    # 패스 → 차감 전환 시 from_pass schedule 삭제
    remove_pass_schedule_if_needed(@schedule)
    @schedule.update!(status: "deducted",
                      makeup_date: nil, makeup_time: nil, makeup_teacher_id: nil)
    tab_redirect(notice: "결석 차감 처리되었습니다.")
  end

  def pass
    enrollment = @schedule.enrollment

    # 당일 패스 → 보강 유도 → 차감 3단계 안내
    if @schedule.lesson_date == Date.today
      range = @schedule.makeup_available_range
      if range
        return redirect_to schedule_path(@schedule),
          alert: "당일 패스는 불가합니다. 보강 등록을 먼저 시도해 보세요. 보강도 불가하면 결석 차감으로 처리하세요."
      else
        return redirect_back fallback_location: schedules_path,
          alert: "당일 패스 및 보강이 불가합니다. 결석 차감으로 처리해 주세요."
      end
    end

    # 믹싱 패스 불가 → 보강 유도
    if enrollment.subject == "믹싱"
      range = @schedule.makeup_available_range
      if range
        return redirect_to schedule_path(@schedule),
          alert: "믹싱 수업은 패스 불가합니다. 보강 등록을 시도해 보세요. 불가하면 결석 차감으로 처리하세요."
      else
        return redirect_back fallback_location: schedules_path,
          alert: "믹싱 패스 및 보강이 불가합니다. 결석 차감으로 처리해 주세요."
      end
    end

    available = available_passes(enrollment)
    if available <= 0
      return redirect_back fallback_location: schedules_path, alert: "잔여 패스가 없습니다."
    end

    # 2주 이상 선패스: 잔여 횟수 체크
    weeks_ahead = (@schedule.lesson_date - Date.today).to_i / 7
    if weeks_ahead >= 2
      remaining = enrollment.student.remaining_lessons_for(enrollment)
      if remaining <= weeks_ahead
        return redirect_back fallback_location: schedules_path,
          alert: "선패스 경고: #{weeks_ahead}주 후 수업이나 잔여 횟수가 #{remaining}회입니다. 결제 먼저 진행하세요."
      end
    end

    # 보강 → 패스 전환 시 보강 정보 초기화
    if @schedule.status == "makeup_scheduled"
      @schedule.update!(makeup_date: nil, makeup_time: nil, makeup_teacher_id: nil, makeup_approved: false)
    end

    @schedule.update!(status: "pass", pass_reason: params[:pass_reason])
    create_pass_schedule(@schedule)
    tab_redirect(notice: "패스 처리되었습니다. ⚠️ 개근 카운트가 리셋됩니다.")
  end

  def emergency_pass
    @schedule.update!(status: "emergency_pass", pass_reason: params[:pass_reason])
    create_pass_schedule(@schedule)
    tab_redirect(notice: "긴급패스 처리되었습니다.")
  end

  def holiday
    @schedule.update!(status: "holiday", pass_reason: params[:pass_reason])
    create_pass_schedule(@schedule)
    tab_redirect(notice: "공휴일 처리되었습니다.")
  end

  def cancel_pass
    unless @schedule.status.in?(%w[pass emergency_pass holiday])
      return redirect_back fallback_location: schedules_path, alert: "패스 상태가 아닙니다."
    end
    remove_pass_schedule_if_needed(@schedule)
    @schedule.update!(status: "scheduled", pass_reason: nil)
    tab_redirect(notice: "패스가 취소되었습니다.")
  end

  def makeup
    makeup_date = Date.parse(params[:makeup_date])
    makeup_time = params[:makeup_time]
    teacher_id  = params[:makeup_teacher_id].to_i

    range = @schedule.makeup_available_range
    if range && !range.cover?(makeup_date)
      return redirect_back fallback_location: schedules_path,
        alert: "보강 가능 기간 외입니다. (#{range.first} ~ #{range.last})"
    end

    slot = Schedule.slot_count(teacher_id, @schedule.subject, makeup_date)
    if slot >= 3
      return redirect_back fallback_location: schedules_path, alert: "해당 슬롯이 이미 3명입니다."
    end

    # 패스 → 보강 전환 시 from_pass schedule 삭제
    remove_pass_schedule_if_needed(@schedule)

    # 믹싱 보강 승인 플로우
    needs_approval = @schedule.subject == "믹싱"
    approved = true
    if needs_approval
      rank = @schedule.enrollment.student.rank
      if rank == "first"
        # 1차전직: 같은 주차 미라쿠도 반 슬롯 확인
        week_start = makeup_date.beginning_of_week(:monday)
        week_end   = makeup_date.end_of_week(:monday)
        same_week_slot = Schedule.where(
          teacher_id:  teacher_id,
          subject:     @schedule.subject,
          lesson_date: week_start..week_end
        ).where.not(id: @schedule.id).exists?

        approved = same_week_slot
      else
        # 2차전직: 항상 승인 대기
        approved = false
      end
    end

    @schedule.update!(
      status:            "makeup_scheduled",
      makeup_date:       makeup_date,
      makeup_time:       makeup_time,
      makeup_teacher_id: teacher_id,
      makeup_approved:   approved
    )

    notice = "보강 일정이 등록되었습니다. "
    if needs_approval && !approved
      rank = @schedule.enrollment.student.rank
      notice += "믹싱 #{rank == 'second' ? '2차전직 — 상담원 승인 필요' : '1차전직 — 같은 주차 슬롯 없음, 상담원 확인 필요'}."
    end
    tab_redirect(notice: notice)
  end

  def approve_makeup
    @schedule.update!(makeup_approved: true)
    redirect_back fallback_location: schedules_path, notice: "보강 승인 완료."
  end

  def complete_makeup
    @schedule.update!(status: "makeup_done")
    create_attendance_record(@schedule)
    redirect_back fallback_location: schedules_path, notice: "보강 완료 처리되었습니다."
  end

  def makeup_slots
    range = @schedule.makeup_available_range
    result = {
      range_min:   range&.first&.to_s,
      range_max:   range&.last&.to_s,
      lesson_time: @schedule.lesson_time.strftime("%H:%M")
    }

    if range
      subject     = @schedule.subject
      range_dates = range.to_a
      teachers    = Teacher.by_position.joins(:teacher_subjects)
                           .where(teacher_subjects: { subject: subject })
      teacher_ids = teachers.map(&:id)

      # 정규 수업: (teacher_id, date, time) → count
      regulars = Schedule.where(
        teacher_id: teacher_ids, subject: subject, lesson_date: range_dates
      ).where(status: %w[scheduled attended]).pluck(:teacher_id, :lesson_date, :lesson_time)

      # 보강 수업: (makeup_teacher_id, makeup_date, makeup_time) → count
      makeups = Schedule.where(
        makeup_teacher_id: teacher_ids, subject: subject, makeup_date: range_dates
      ).where(status: %w[makeup_scheduled makeup_done]).pluck(:makeup_teacher_id, :makeup_date, :makeup_time)

      # grid[teacher_id][date][time] = count
      grid     = {}
      all_times = [ @schedule.lesson_time.strftime("%H:%M") ]

      regulars.each do |tid, date, time|
        next unless time
        ts = time.strftime("%H:%M"); ds = date.to_s; key = tid.to_s
        grid[key] ||= {}; grid[key][ds] ||= {}
        grid[key][ds][ts] = (grid[key][ds][ts] || 0) + 1
        all_times << ts
      end

      makeups.each do |tid, date, time|
        next unless time
        ts = time.strftime("%H:%M"); ds = date.to_s; key = tid.to_s
        grid[key] ||= {}; grid[key][ds] ||= {}
        grid[key][ds][ts] = (grid[key][ds][ts] || 0) + 1
        all_times << ts
      end

      result[:teachers] = teachers.map { |t| { id: t.id, name: t.name } }
      result[:dates]    = range_dates.map(&:to_s)
      result[:times]    = all_times.uniq.sort
      result[:grid]     = grid
    end

    render json: result
  end

  def undo_deduct
    unless @schedule.status == "deducted"
      return redirect_back fallback_location: schedules_path, alert: "차감 상태인 수업만 취소 가능합니다."
    end

    @schedule.update!(status: "scheduled")

    range = @schedule.makeup_available_range
    period_expired = range.nil? || range.last < Date.today

    if period_expired
      tab_redirect(notice: "차감 취소되었습니다. ⚠️ 보강 가능 기간이 만료되어 보강/패스 전환이 불가합니다.")
    else
      tab_redirect(notice: "차감 취소되었습니다. 보강 또는 패스 전환이 가능합니다. (보강 기간: #{range.first} ~ #{range.last})")
    end
  end

  def undo_attend
    unless @schedule.status.in?(%w[attended late])
      return redirect_back fallback_location: schedules_path, alert: "출석/지각 상태인 수업만 취소 가능합니다."
    end

    enrollment = @schedule.enrollment

    ActiveRecord::Base.transaction do
      # 개근처리가 완료됐으면 함께 취소
      if enrollment.last_attendance_event_at.present?
        last_payment = enrollment.payments.where(fully_paid: true).order(:created_at).last
        if last_payment
          event_discount = last_payment.discounts.where(discount_type: "attendance_event").order(:created_at).last
          if event_discount
            # 개근처리로 추가된 수업 = 해당 결제의 가장 마지막 예정 수업
            event_schedule = last_payment.schedules.where(status: "scheduled").order(lesson_date: :desc).first
            event_schedule&.destroy
            event_discount.destroy
          end
        end
        enrollment.update!(last_attendance_event_at: nil, attendance_event_pending: false)
      end

      # 출석 기록 삭제 (하원 포함)
      @schedule.attendance&.destroy

      # 상태 되돌리기
      @schedule.update!(status: "scheduled")

      # 연속개근 12주 여부 재검사
      count = enrollment.student.consecutive_weeks_for(enrollment)
      enrollment.update!(attendance_event_pending: count >= 12)
    end

    tab_redirect(notice: "등원 취소되었습니다.")
  end

  private

  def set_schedule
    @schedule = Schedule.find(params[:id])
  end

  # 수강생 상세 페이지에서 온 경우 해당 클래스 탭을 유지해서 리다이렉트
  def tab_redirect(notice: nil, alert: nil)
    if request.referer&.match?(%r{/students/\d+})
      redirect_to student_path(@schedule.student, tab: @schedule.enrollment_id),
                  notice: notice, alert: alert
    else
      redirect_back fallback_location: schedules_path, notice: notice, alert: alert
    end
  end

  def create_attendance_record(schedule)
    schedule.create_attendance!(
      student:       schedule.student,
      payment:       schedule.payment,
      checked_in_at: Time.current
    )
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    # 이미 출석 기록 존재 — 오류 무시
  end

  # 패스 사용 시 결제분 마지막 수업 + 7일에 추가 Schedule 생성
  def create_pass_schedule(schedule)
    payment = schedule.payment
    last_s  = payment.schedules.order(lesson_date: :desc).first
    return unless last_s

    payment.schedules.create!(
      student:     schedule.student,
      enrollment:  schedule.enrollment,
      teacher:     schedule.teacher,
      lesson_date: last_s.lesson_date + 7.days,
      lesson_time: schedule.lesson_time,
      subject:     schedule.subject,
      status:      "scheduled",
      sequence:    payment.schedules.maximum(:sequence).to_i + 1,
      from_pass:   true
    )
  end

  # 패스/긴급패스/공휴일 → 다른 상태 전환 시 from_pass schedule 삭제
  def remove_pass_schedule_if_needed(schedule)
    return unless schedule.status.in?(%w[pass emergency_pass holiday])
    schedule.payment.schedules.where(from_pass: true).order(lesson_date: :desc).first&.destroy
  end

  def today_arrival_schedules
    Schedule.includes(:student, :teacher, :enrollment, :attendance)
            .where(lesson_date: Date.today)
            .where(status: %w[scheduled attended late makeup_scheduled])
            .order(:lesson_time)
  end

  def available_passes(enrollment)
    total_months = enrollment.payments.where(fully_paid: true).sum(:months)
    used_passes  = enrollment.schedules.where(status: "pass").count
    total_months - used_passes
  end

  def check_consecutive_weeks(schedule)
    enrollment = schedule.enrollment
    count      = enrollment.student.consecutive_weeks_for(enrollment)
    if count >= 12
      enrollment.update_column(:attendance_event_pending, true)
    end
  end

  def check_gift_voucher(schedule)
    enrollment = schedule.enrollment
    weeks      = schedule.student.gift_voucher_eligible_weeks_for(enrollment)
    return unless weeks == 24
    return if GiftVoucher.where(enrollment: enrollment).exists?

    GiftVoucher.create!(
      student:    schedule.student,
      enrollment: enrollment,
      issued_at:  Date.today,
      expires_at: Date.today + 6.months
    )
    schedule.student.update!(gift_voucher_issued: true)
  end
end
