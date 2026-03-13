class GiftVouchersController < ApplicationController
  before_action :set_voucher, only: [:use, :trial_slots, :schedule_trial]

  def create
    enrollment = Enrollment.find(params[:enrollment_id])
    student    = enrollment.student

    GiftVoucher.create!(
      student:    student,
      enrollment: enrollment,
      issued_at:  Date.today,
      expires_at: Date.today + 6.months
    )
    enrollment.update_column(:review_gift_eligible, false)
    redirect_to student_path(student), notice: "#{student.name} — #{enrollment.subject} 지류상품권 발급 완료."
  end

  def use
    if @voucher.used?
      return redirect_back fallback_location: root_path, alert: "이미 사용된 상품권입니다."
    end
    if @voucher.expires_at < Date.today
      return redirect_back fallback_location: root_path, alert: "만료된 상품권입니다."
    end

    used_class = params[:used_class].to_s.strip
    if used_class.blank?
      return redirect_back fallback_location: root_path, alert: "사용 과목을 선택해주세요."
    end
    if used_class == @voucher.enrollment.subject
      return redirect_back fallback_location: root_path, alert: "발급 과목(#{used_class})에는 사용할 수 없습니다."
    end

    @voucher.update!(used: true, used_at: Date.today, used_class: used_class)
    redirect_back fallback_location: root_path, notice: "상품권 사용 처리 완료 (#{used_class})."
  end

  def trial_slots
    subject = params[:subject].presence || @voucher.enrollment.subject
    teachers = Teacher.by_position.joins(:teacher_subjects)
                      .where(teacher_subjects: { subject: subject })
    teacher_ids = teachers.map(&:id)

    display_range = Date.today..(Date.today + 90.days)

    regulars = Schedule.where(
      teacher_id: teacher_ids, subject: subject, lesson_date: display_range
    ).where(status: %w[scheduled attended]).pluck(:teacher_id, :lesson_date, :lesson_time)

    makeups = Schedule.where(
      makeup_teacher_id: teacher_ids, subject: subject, makeup_date: display_range
    ).where(status: %w[makeup_scheduled makeup_done]).pluck(:makeup_teacher_id, :makeup_date, :makeup_time)

    grid      = {}
    all_times = []

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

    render json: {
      subject:   subject,
      teachers:  teachers.map { |t| { id: t.id, name: t.name } },
      dates:     (display_range.first..display_range.end).map(&:to_s),
      times:     all_times.uniq.sort,
      grid:      grid,
      range_min: nil,
      range_max: nil
    }
  end

  def schedule_trial
    existing = @voucher.trial_schedule

    if existing && existing.status.in?(%w[attended late makeup_done])
      return respond_to do |format|
        format.turbo_stream { render turbo_stream: turbo_stream.replace("flash-notice", html: "<div class='alert alert-error text-sm'>이미 완료된 체험수업은 변경할 수 없습니다.</div>".html_safe) }
        format.html { redirect_back fallback_location: root_path, alert: "이미 완료된 체험수업은 변경할 수 없습니다." }
        format.json { render json: { error: "이미 완료된 체험수업은 변경할 수 없습니다." }, status: :unprocessable_entity }
      end
    end

    teacher     = Teacher.find(params[:teacher_id])
    date        = Date.parse(params[:date])
    time_str    = params[:time]
    lesson_time = Time.zone.parse("#{date} #{time_str}")
    subject     = params[:subject].presence || @voucher.enrollment.subject

    if existing
      existing.update!(
        teacher:     teacher,
        lesson_date: date,
        lesson_time: lesson_time,
        subject:     subject,
        status:      "scheduled"
      )
    else
      Schedule.create!(
        student:      @voucher.student,
        enrollment:   @voucher.enrollment,
        teacher:      teacher,
        lesson_date:  date,
        lesson_time:  lesson_time,
        subject:      subject,
        status:       "scheduled",
        trial:        true,
        gift_voucher: @voucher,
        sequence:     0
      )
    end

    # 대시보드 실시간 반영: 체험 수업 날짜가 오늘이면 즉각 broadcast
    effective = Time.current.hour >= 21 ? Date.tomorrow : Date.today
    if date == effective
      Turbo::StreamsChannel.broadcast_replace_to(
        "dashboard_current",
        target: "hourly_arrival",
        partial: "dashboard/hourly_arrival_text",
        locals: { schedules: trial_aware_arrivals(effective) }
      )
    end

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "gift-vouchers-#{@voucher.student_id}",
          partial: "students/gift_vouchers",
          locals: { student: @voucher.student }
        )
      end
      format.html do
        redirect_to student_path(@voucher.student), notice: "체험수업이 #{date.strftime('%m/%d')} #{time_str}으로 등록되었습니다."
      end
    end
  end

  private

  def set_voucher
    @voucher = GiftVoucher.find(params[:id])
  end

  def trial_aware_arrivals(date)
    regular  = Schedule.includes(:student, :teacher, :makeup_teacher, :enrollment, :attendance)
                       .joins(:enrollment)
                       .where(lesson_date: date, status: %w[scheduled attended late])
                       .where(enrollments: { status: "active" })
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
        t = s.lesson_time.in_time_zone("Seoul")
        [t.hour, t.min]
      end
    end
  end
end
