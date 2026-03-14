class SchedulesController < ApplicationController
  before_action :set_schedule, only: %i[show attend checkout late deduct pass emergency_pass holiday makeup approve_makeup complete_makeup undo_deduct undo_attend makeup_slots cancel_pass move_date destroy]

  def index
    date = params[:date] ? Date.parse(params[:date]) : Date.today
    @schedules = Schedule.includes(:student, :teacher, :enrollment, :attendance)
                         .where(lesson_date: date)
                         .where(status: %w[scheduled attended late makeup_scheduled makeup_done deducted])
                         .order(:lesson_time)
  end

  def show; end

  def attend
    # 완납필요: 예약금 미완납 + 첫 수업이면 등원 차단 (trial 수업은 payment 없으므로 스킵)
    if @schedule.payment && @schedule.payment.fully_paid == false && @schedule.payment.payment_type == "deposit"
      first = @schedule.payment.schedules.order(:lesson_date, :id).first
      if first&.id == @schedule.id
        respond_to do |format|
          format.turbo_stream do
            toast_html = <<~HTML.html_safe
              <div id="flash-toast-alert" class="toast toast-top toast-end z-50">
                <div class="alert alert-error shadow-md">
                  <span class="text-sm">먼저 완납처리 부탁드립니다!</span>
                  <button onclick="this.closest('#flash-toast-alert').remove()" class="btn btn-xs btn-ghost">✕</button>
                </div>
              </div>
              <script>setTimeout(() => document.getElementById('flash-toast-alert')?.remove(), 6000)</script>
            HTML
            render turbo_stream: turbo_stream.replace("flash-toast-alert", html: toast_html)
          end
          format.html { redirect_back fallback_location: root_path, alert: "먼저 완납처리 부탁드립니다!" }
        end
        return
      end
    end

    remove_pass_schedule_if_needed(@schedule)
    new_status = @schedule.status == "makeup_scheduled" ? "makeup_done" : "attended"
    @schedule.update!(status: new_status)
    create_attendance_record(@schedule)
    check_consecutive_weeks(@schedule) unless new_status == "makeup_done"
    check_review_milestones(@schedule)
    respond_to do |format|
      format.turbo_stream do
        attendance_events = Enrollment.where(attendance_event_pending: true).includes(:student)
        count = attendance_events.count
        badge_html = (count > 0 ? "<div class=\"badge badge-accent gap-1\">🔥 개근달성 #{count}명</div>" : "").html_safe
        tab_label  = "🎯 개근 (#{count})"
        enrollment = @schedule.enrollment
        student    = enrollment.student
        payment    = @schedule.payment
        @current_date = @schedule.lesson_date
        streams = [
          # 대시보드 타깃
          turbo_stream.replace("current_schedules", partial: "dashboard/current_schedules"),
          turbo_stream.replace("hourly_arrival", method: :morph,    partial: "dashboard/hourly_arrival_text",
                               locals: { schedules: today_arrival_schedules }),
          turbo_stream.replace("attendance-events-panel", partial: "dashboard/attendance_events_panel",
                               locals: { attendance_events: attendance_events }),
          turbo_stream.update("keungeun-alert-badge", html: badge_html),
          turbo_stream.replace("keungeun-tab-radio",
            html: "<input type='radio' name='todo-tabs' role='tab' class='tab' id='keungeun-tab-radio' aria-label='#{tab_label}' #{count > 0 ? 'checked' : ''} onchange=\"switchTodoCopy('keungeun')\">".html_safe),
          # 학생 페이지 타깃
          turbo_stream.replace("schedule-badge-#{@schedule.id}",
            partial: "students/schedule_badge", locals: { s: @schedule, enrollment: enrollment }),
          turbo_stream.replace("enrollment-stats-#{enrollment.id}",
            partial: "students/enrollment_stats", locals: { student: student, enrollment: enrollment })
        ]
        # trial 수업은 payment 없으므로 payment-chunk-header 업데이트 스킵
        if payment
          streams << turbo_stream.replace("payment-chunk-header-#{payment.id}",
            partial: "students/payment_chunk_header", locals: { payment: payment, is_open: true })
        end
        # 시간대별 수업 패널 업데이트
        hs = hourly_schedule_locals
        streams << turbo_stream.replace("hourly_schedule",
          partial: "dashboard/hourly_schedule_text",
          locals: { schedules: hs[:schedules], makeups: hs[:makeups],
                    deducted_schedules: hs[:deducted_schedules],
                    passed_schedules: hs[:passed_schedules],
                    enrollment_remaining: hs[:enrollment_remaining] })
        render turbo_stream: streams
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
          turbo_stream.replace("hourly_arrival", method: :morph,    partial: "dashboard/hourly_arrival_text",
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
    check_consecutive_weeks(@schedule)
    check_review_milestones(@schedule)
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

    # 믹싱 패스 불가 → 보강 유도
    if enrollment.subject.in?(%w[믹싱1차 믹싱2차])
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
    respond_to do |format|
      format.turbo_stream do
        enrollment = @schedule.enrollment
        student    = enrollment.student
        payment    = @schedule.payment
        hs = hourly_schedule_locals
        render turbo_stream: [
          turbo_stream.replace("hourly_arrival", method: :morph, partial: "dashboard/hourly_arrival_text",
                               locals: { schedules: today_arrival_schedules }),
          turbo_stream.replace("schedule-badge-#{@schedule.id}",
            partial: "students/schedule_badge", locals: { s: @schedule, enrollment: enrollment }),
          turbo_stream.replace("enrollment-stats-#{enrollment.id}",
            partial: "students/enrollment_stats", locals: { student: student, enrollment: enrollment }),
          turbo_stream.replace("payment-chunk-header-#{payment.id}",
            partial: "students/payment_chunk_header", locals: { payment: payment, is_open: true }),
          turbo_stream.replace("hourly_schedule",
            partial: "dashboard/hourly_schedule_text",
            locals: { schedules: hs[:schedules], makeups: hs[:makeups],
                      deducted_schedules: hs[:deducted_schedules],
                      passed_schedules: hs[:passed_schedules],
                      enrollment_remaining: hs[:enrollment_remaining] })
        ]
      end
      format.html do
        if request.referer&.match?(%r{/students/\d+})
          redirect_to student_path(@schedule.student, tab: @schedule.enrollment_id), notice: "긴급패스 처리되었습니다."
        else
          redirect_back fallback_location: schedules_path, notice: "긴급패스 처리되었습니다."
        end
      end
    end
  end

  def holiday
    @schedule.update!(status: "holiday", pass_reason: params[:pass_reason])
    create_pass_schedule(@schedule)
    tab_redirect(notice: "공휴일 처리되었습니다.")
  end

  def move_date
    new_date = Date.parse(params[:new_date])
    old_date = @schedule.lesson_date
    @schedule.update!(lesson_date: new_date)
    tab_redirect(notice: "수업 날짜가 #{old_date.strftime('%-m/%-d')} → #{new_date.strftime('%-m/%-d')}로 변경되었습니다.")
  end

  def destroy
    student = @schedule.enrollment.student
    @schedule.attendance&.destroy
    @schedule.destroy!
    redirect_to student_path(student), notice: "스케줄이 삭제되었습니다."
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

    military = params[:military] == "1"
    unless military
      range = @schedule.makeup_available_range
      if range && !range.cover?(makeup_date)
        upper_str = range.end ? range.end.to_s : "상한 없음"
        return redirect_back fallback_location: schedules_path,
          alert: "보강 가능 기간 외입니다. (#{range.first} ~ #{upper_str})"
      end
    end

    slot = Schedule.slot_count(teacher_id, @schedule.subject, makeup_date, makeup_time)
    if slot >= 3
      return redirect_back fallback_location: schedules_path, alert: "해당 슬롯이 이미 3명입니다."
    end

    # 다과목 선생님: 해당 시간대에 다른 과목 있으면 보강 불가
    makeup_teacher = Teacher.find(teacher_id)
    if makeup_teacher.teacher_subjects.count > 1 &&
       Schedule.subject_conflict?(teacher_id, @schedule.subject, makeup_date, makeup_time)
      return redirect_back fallback_location: schedules_path,
        alert: "해당 시간에 다른 과목 수업이 있어 보강을 등록할 수 없습니다."
    end

    # 패스 → 보강 전환 시 from_pass schedule 삭제
    remove_pass_schedule_if_needed(@schedule)

    # 믹싱 보강 승인 플로우
    needs_approval = @schedule.subject.in?(%w[믹싱1차 믹싱2차])
    approved = true
    if needs_approval
      if @schedule.subject == "믹싱1차"
        # 1차전직: 같은 주차 슬롯 확인
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
      notice += "믹싱 #{@schedule.subject == '믹싱2차' ? '2차전직 — 상담원 승인 필요' : '1차전직 — 같은 주차 슬롯 없음, 상담원 확인 필요'}."
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
      range_max:   range&.end&.to_s,  # nil이면 상한 없음
      lesson_time: @schedule.lesson_time.strftime("%H:%M")
    }

    if range
      subject     = @schedule.subject
      # 상한이 nil(무제한)이면 시간표 표시용으로 90일로 cap
      display_upper = range.end || (range.first + 90.days)
      display_range = range.first..display_upper
      teachers    = Teacher.by_position.non_military.joins(:teacher_subjects)
                           .where(teacher_subjects: { subject: subject })
      teacher_ids = teachers.map(&:id)

      # 정규 수업: (teacher_id, date, time) → count
      regulars = Schedule.where(
        teacher_id: teacher_ids, subject: subject, lesson_date: display_range
      ).where(status: %w[scheduled attended]).pluck(:teacher_id, :lesson_date, :lesson_time)

      # 보강 수업: (makeup_teacher_id, makeup_date, makeup_time) → count
      makeups = Schedule.where(
        makeup_teacher_id: teacher_ids, subject: subject, makeup_date: display_range
      ).where(status: %w[makeup_scheduled makeup_done]).pluck(:makeup_teacher_id, :makeup_date, :makeup_time)

      # grid[teacher_id][date][time] = count
      grid      = {}
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

      range_dates = (display_range.first..display_range.end).map(&:to_s)
      result[:teachers] = teachers.map { |t| { id: t.id, name: t.name } }
      result[:dates]    = range_dates
      result[:times]    = all_times.uniq.sort
      result[:grid]     = grid

      # 다과목 선생님: 다른 과목 점유 슬롯을 conflict_grid에 표시 (값 = "conflict")
      multi_subject_teacher_ids = teachers.select { |t| t.teacher_subjects.count > 1 }.map { |t| t.id.to_s }
      if multi_subject_teacher_ids.any?
        conflict_grid = {}
        conflict_regulars = Schedule.where(teacher_id: multi_subject_teacher_ids.map(&:to_i), lesson_date: display_range)
                                    .where(status: %w[scheduled attended late])
                                    .where.not(subject: subject)
                                    .pluck(:teacher_id, :lesson_date, :lesson_time)
        conflict_makeups  = Schedule.where(makeup_teacher_id: multi_subject_teacher_ids.map(&:to_i), makeup_date: display_range)
                                    .where(status: %w[makeup_scheduled makeup_done])
                                    .where.not(subject: subject)
                                    .pluck(:makeup_teacher_id, :makeup_date, :makeup_time)

        (conflict_regulars + conflict_makeups).each do |tid, date, time|
          next unless time
          ts = time.strftime("%H:%M"); ds = date.to_s; key = tid.to_s
          conflict_grid[key] ||= {}; conflict_grid[key][ds] ||= {}
          conflict_grid[key][ds][ts] = "conflict"
        end
        result[:conflict_grid] = conflict_grid
      end
    end

    render json: result
  end

  def undo_deduct
    unless @schedule.status == "deducted"
      return redirect_back fallback_location: schedules_path, alert: "차감 상태인 수업만 취소 가능합니다."
    end

    @schedule.update!(status: "scheduled")

    range = @schedule.makeup_available_range
    period_expired = range.nil? || (range.end.present? && range.end < Date.today)

    if period_expired
      tab_redirect(notice: "차감 취소되었습니다. ⚠️ 보강 가능 기간이 만료되어 보강/패스 전환이 불가합니다.")
    else
      upper_str = range.end ? range.end.to_s : "상한 없음"
      tab_redirect(notice: "차감 취소되었습니다. 보강 또는 패스 전환이 가능합니다. (보강 기간: #{range.first} ~ #{upper_str})")
    end
  end

  def undo_attend
    is_makeup = @schedule.status == "makeup_done"
    unless @schedule.status.in?(%w[attended late makeup_done])
      return redirect_back fallback_location: schedules_path, alert: "출석/지각/보강완료 상태인 수업만 취소 가능합니다."
    end

    enrollment = @schedule.enrollment

    ActiveRecord::Base.transaction do
      unless is_makeup
        # 개근처리가 완료됐으면 함께 취소 (정규 수업만)
        if enrollment.last_attendance_event_at.present?
          last_payment = enrollment.payments.where(fully_paid: true).order(:created_at).last
          if last_payment
            event_discount = last_payment.discounts.where(discount_type: "attendance_event").order(:created_at).last
            if event_discount
              event_schedule = last_payment.schedules.where(status: "scheduled").order(lesson_date: :desc).first
              event_schedule&.destroy
              event_discount.destroy
            end
          end
          enrollment.update_columns(last_attendance_event_at: nil, attendance_event_pending: false)
        end
      end

      # 출석 기록 삭제
      @schedule.attendance&.destroy

      # 상태 되돌리기 (보강완료 → 보강예정, 정규 → 예정)
      revert_status = is_makeup ? "makeup_scheduled" : "scheduled"
      @schedule.update_column(:status, revert_status)

      unless is_makeup
        count = enrollment.student.consecutive_weeks_for(enrollment)
        enrollment.update_column(:attendance_event_pending, count >= 12)
      end
    end

    tab_redirect(notice: "등원 취소되었습니다.")
  end

  private

  def set_schedule
    @schedule = Schedule.find(params[:id])
  end

  # 수강생 상세 페이지에서 온 경우 해당 클래스 탭을 유지해서 리다이렉트
  def tab_redirect(notice: nil, alert: nil, extra_streams: [])
    respond_to do |format|
      format.turbo_stream do
        enrollment = @schedule.enrollment
        student    = enrollment.student
        payment    = @schedule.payment
        streams = [
          turbo_stream.replace("hourly_arrival", method: :morph, partial: "dashboard/hourly_arrival_text",
                               locals: { schedules: today_arrival_schedules }),
          turbo_stream.replace("schedule-badge-#{@schedule.id}",
            partial: "students/schedule_badge", locals: { s: @schedule, enrollment: enrollment }),
          turbo_stream.replace("enrollment-stats-#{enrollment.id}",
            partial: "students/enrollment_stats", locals: { student: student, enrollment: enrollment })
        ]
        # trial 수업은 payment 없으므로 payment-chunk-header 업데이트 스킵
        if payment
          streams << turbo_stream.replace("payment-chunk-header-#{payment.id}",
            partial: "students/payment_chunk_header", locals: { payment: payment, is_open: true })
        end
        hs = hourly_schedule_locals
        streams << turbo_stream.replace("hourly_schedule",
          partial: "dashboard/hourly_schedule_text",
          locals: { schedules: hs[:schedules], makeups: hs[:makeups],
                    deducted_schedules: hs[:deducted_schedules],
                    passed_schedules: hs[:passed_schedules],
                    enrollment_remaining: hs[:enrollment_remaining] })
        streams.concat(extra_streams)
        render turbo_stream: streams
      end
      format.html do
        if request.referer&.match?(%r{/students/\d+})
          redirect_to student_path(@schedule.student, tab: @schedule.enrollment_id),
                      notice: notice, alert: alert
        elsif params[:from_student_id].present?
          redirect_to student_path(params[:from_student_id], tab: params[:from_enrollment_id]),
                      notice: notice, alert: alert
        else
          redirect_back fallback_location: schedules_path, notice: notice, alert: alert
        end
      end
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

  def hourly_schedule_locals
    effective = Time.current.hour >= 21 ? Date.tomorrow : Date.today
    schedules  = today_arrival_schedules
    makeups    = Schedule.includes(:student, :teacher, :makeup_teacher, :enrollment)
                         .where(makeup_date: effective, status: %w[makeup_scheduled makeup_done])
    deducted   = Schedule.includes(:student, :teacher, :enrollment)
                         .joins(:enrollment, :teacher)
                         .where(lesson_date: effective, status: "deducted")
                         .where(enrollments: { status: "active" })
                         .where(teachers: { military: false })
    raw_passed = Schedule.includes(:student, :teacher, :enrollment)
                         .joins(:enrollment, :teacher)
                         .where(lesson_date: effective, status: %w[pass emergency_pass holiday makeup_scheduled])
                         .where(enrollments: { status: "active" })
                         .where(teachers: { military: false })
                         .where(trial: false)
    passed = raw_passed.to_a.reject { |s| s.status == "makeup_scheduled" && s.makeup_date == effective }
    enrollment_ids = (schedules + makeups.to_a + deducted.to_a + passed).map(&:enrollment_id).uniq
    remaining = Schedule.where(enrollment_id: enrollment_ids, status: %w[scheduled makeup_scheduled], trial: false)
                        .group(:enrollment_id).count
    { schedules: schedules, makeups: makeups, deducted_schedules: deducted, passed_schedules: passed, enrollment_remaining: remaining }
  end

  def today_arrival_schedules
    today    = Date.today
    regular  = Schedule.includes(:student, :teacher, :makeup_teacher, :enrollment, :attendance)
                       .joins(:enrollment, :teacher)
                       .where(lesson_date: today, status: %w[scheduled attended late])
                       .where(enrollments: { status: "active" })
                       .where(teachers: { military: false })
    trial    = Schedule.includes(:student, :teacher, :enrollment, :attendance)
                       .where(lesson_date: today, trial: true, status: %w[scheduled attended late])
    same_day = Schedule.includes(:student, :teacher, :makeup_teacher, :enrollment, :attendance)
                       .joins(:enrollment)
                       .where(makeup_date: today, status: %w[makeup_scheduled makeup_done])
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

  def available_passes(enrollment)
    total_months = enrollment.payments.where(fully_paid: true).sum(:months)
    used_passes  = enrollment.schedules.where(status: "pass").count
    [total_months - used_passes + (enrollment.pass_offset || 0), 0].max
  end

  def check_consecutive_weeks(schedule)
    enrollment = schedule.enrollment
    count      = enrollment.student.consecutive_weeks_for(enrollment)
    if count >= 12
      enrollment.update_column(:attendance_event_pending, true)
    end
  end

  def check_review_milestones(schedule)
    enrollment = schedule.enrollment
    weeks      = schedule.student.review_weeks_for(enrollment)
    if weeks >= 24 && !GiftVoucher.where(enrollment: enrollment).exists?
      enrollment.update_column(:review_gift_eligible, true)
    end
  end
end
