class EnrollmentsController < ApplicationController
  before_action :set_enrollment, only: %i[show edit update destroy leave return dropout reschedule_form reschedule dismiss_attendance_event add_lesson update_stat]
  before_action :set_student,    only: %i[new create]

  def show
    @schedules = @enrollment.schedules.includes(:teacher).order(:lesson_date)
    @payments  = @enrollment.payments.includes(:discounts).order(:created_at)
  end

  def new
    @enrollment = @student.enrollments.build
    @teachers   = Teacher.includes(:teacher_subjects).all
  end

  def create
    @student    = Student.find(params[:student_id])
    @enrollment = @student.enrollments.build(enrollment_params)

    if @enrollment.save
      if params[:modal] == '1'
        render inline: "<script>window.parent.postMessage('enrollment_created', '*'); window.parent.location.reload();</script>"
      else
        redirect_to student_path(@student), notice: "클래스가 등록되었습니다."
      end
    else
      @teachers = Teacher.includes(:teacher_subjects).all
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @teachers = Teacher.includes(:teacher_subjects).all
  end

  def update
    old_teacher_id = @enrollment.teacher_id
    if @enrollment.update(enrollment_params)
      # 선생님이 바뀌었으면 예정 수업 일괄 업데이트
      if @enrollment.teacher_id != old_teacher_id
        @enrollment.schedules.where(status: "scheduled", teacher_id: old_teacher_id)
                   .update_all(teacher_id: @enrollment.teacher_id)
      end
      redirect_to student_path(@enrollment.student, anchor: "enrollment-#{@enrollment.id}"),
                  notice: "클래스 정보가 수정되었습니다."
    else
      @teachers = Teacher.includes(:teacher_subjects).all
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @enrollment.destroy
    redirect_to student_path(@enrollment.student), notice: "클래스가 삭제되었습니다."
  end

  def leave
    @enrollment.leave!(params[:leave_reason].presence)
    redirect_to student_path(@enrollment.student, tab: @enrollment.id), notice: "클래스 휴원 처리되었습니다."
  end

  def return
    return_date    = params[:return_date].present? ? Date.parse(params[:return_date]) : Date.today
    new_day        = params[:lesson_day].presence   || @enrollment.lesson_day
    new_time_str   = params[:lesson_time].presence
    new_teacher_id = params[:teacher_id].present? ? params[:teacher_id].to_i : @enrollment.teacher_id

    if @enrollment.returnable?
      # 요일/시간/선생님이 변경된 경우 return! 전에 먼저 업데이트
      changed = new_day != @enrollment.lesson_day ||
                new_teacher_id != @enrollment.teacher_id ||
                (new_time_str && new_time_str != @enrollment.lesson_time.strftime('%H:%M'))
      if changed
        time_val = new_time_str.present? ? Time.zone.parse(new_time_str) : @enrollment.lesson_time
        @enrollment.update_columns(lesson_day: new_day, lesson_time: time_val, teacher_id: new_teacher_id)
      end
      @enrollment.return!(return_date)
      redirect_to student_path(@enrollment.student, tab: @enrollment.id), notice: "#{@enrollment.subject} 복귀 처리되었습니다. (#{return_date.strftime('%m/%d')}부터)"
    else
      redirect_to student_path(@enrollment.student, tab: @enrollment.id), alert: "결제 내역이 없어 복귀할 수 없습니다."
    end
  end

  def dropout
    @enrollment.dropout!
    redirect_to student_path(@enrollment.student), notice: "클래스 퇴원 처리되었습니다."
  end

  def dismiss_attendance_event
    payment = @enrollment.payments.where(fully_paid: true).order(:created_at).last
    unless payment
      return redirect_back fallback_location: root_path, alert: "완납 결제 내역이 없어 수업을 추가할 수 없습니다."
    end

    last_schedule = payment.schedules.order(lesson_date: :desc).first
    unless last_schedule
      return redirect_back fallback_location: root_path, alert: "스케줄이 없어 수업을 추가할 수 없습니다."
    end

    new_date = last_schedule.lesson_date + 7.days
    payment.schedules.create!(
      student:     @enrollment.student,
      enrollment:  @enrollment,
      teacher:     last_schedule.teacher,
      lesson_date: new_date,
      lesson_time: last_schedule.lesson_time,
      subject:     @enrollment.subject,
      status:      "scheduled",
      sequence:    payment.schedules.maximum(:sequence).to_i + 1,
      from_pass:   false
    )

    payment.discounts.create!(
      discount_type: "attendance_event",
      amount: 0,
      memo: "12주 개근 1회 무료"
    )

    @enrollment.update_columns(attendance_event_pending: false, last_attendance_event_at: Date.today + 1.day)
    new_raw = @enrollment.student.consecutive_weeks_for_raw(@enrollment)
    @enrollment.update_column(:consecutive_weeks_offset, -new_raw)
    if request.referer&.include?("/students/")
      redirect_to student_path(@enrollment.student, tab: @enrollment.id), notice: "개근 처리 완료. #{new_date.strftime('%m/%d')} 수업 1회 추가되었습니다."
    else
      redirect_to root_path(todo_tab: "keungeun"), notice: "개근 처리 완료. #{new_date.strftime('%m/%d')} 수업 1회 추가되었습니다."
    end
  end

  def add_lesson
    payment = @enrollment.payments.where(fully_paid: true).order(:created_at).last
    unless payment
      return redirect_to student_path(@enrollment.student, tab: @enrollment.id),
             alert: "완납 결제 내역이 없어 수업을 추가할 수 없습니다."
    end

    last_schedule = payment.schedules.order(lesson_date: :desc).first
    unless last_schedule
      return redirect_to student_path(@enrollment.student, tab: @enrollment.id),
             alert: "스케줄이 없어 수업을 추가할 수 없습니다."
    end

    new_date = last_schedule.lesson_date + 7.days
    payment.schedules.create!(
      student:     @enrollment.student,
      enrollment:  @enrollment,
      teacher:     last_schedule.teacher,
      lesson_date: new_date,
      lesson_time: last_schedule.lesson_time,
      subject:     @enrollment.subject,
      status:      "scheduled",
      sequence:    payment.schedules.maximum(:sequence).to_i + 1,
      from_pass:   false
    )

    redirect_to student_path(@enrollment.student, tab: @enrollment.id),
                notice: "수업 1회 추가되었습니다. (#{new_date.strftime('%m/%d')})"
  end

  def reschedule_form
    @teachers = Teacher.includes(:teacher_subjects)
                       .joins(:teacher_subjects)
                       .where(teacher_subjects: { subject: @enrollment.subject })
                       .by_position
  end

  def reschedule
    change_date    = Date.parse(params[:change_date])
    new_day        = params[:lesson_day]
    new_time       = params[:lesson_time]
    new_teacher_id = params[:teacher_id].to_i

    schedules_to_change = @enrollment.schedules
                                     .where(status: "scheduled")
                                     .where("lesson_date >= ?", change_date)
                                     .order(:lesson_date)

    @enrollment.update!(lesson_day: new_day, lesson_time: new_time, teacher_id: new_teacher_id)

    day_map = { "monday" => 1, "tuesday" => 2, "wednesday" => 3,
                "thursday" => 4, "friday" => 5, "saturday" => 6, "sunday" => 0 }
    target_wday = day_map[new_day]

    first_date = change_date.dup
    first_date += 1.day until first_date.wday == target_wday

    schedules_to_change.each_with_index do |s, i|
      s.update!(lesson_date: first_date + (i * 7).days,
                lesson_time: new_time,
                teacher_id:  new_teacher_id)
    end

    redirect_to student_path(@enrollment.student, tab: @enrollment.id),
                notice: "수업 일정이 변경되었습니다. (#{schedules_to_change.size}회)"
  end

  def update_stat
    stat = params[:stat]
    value = params[:value].to_i

    allowed = %w[consecutive_weeks gift_voucher_eligible pass]
    return render json: { error: "invalid stat" }, status: :unprocessable_entity unless allowed.include?(stat)

    student = @enrollment.student

    case stat
    when "consecutive_weeks"
      computed = student.consecutive_weeks_for_raw(@enrollment)
      cols = { consecutive_weeks_offset: value - computed }
      cols[:attendance_event_pending] = true if value >= 12
      @enrollment.update_columns(cols)
    when "gift_voucher_eligible"
      computed = student.review_weeks_for_raw(@enrollment)
      cols = { gift_voucher_eligible_offset: value - computed }
      if value >= 24 && !GiftVoucher.where(enrollment: @enrollment).exists?
        cols[:review_gift_eligible] = true
      end
      @enrollment.update_columns(cols)
    when "pass"
      total_months = @enrollment.payments.where(fully_paid: true).sum(:months)
      used_passes  = @enrollment.schedules.where(status: "pass").count
      computed_passes = total_months - used_passes
      @enrollment.update_columns(pass_offset: value - computed_passes)
    end

    if stat == "gift_voucher_eligible"
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "enrollment-stats-#{@enrollment.id}",
            partial: "students/enrollment_stats",
            locals: { student: student, enrollment: @enrollment }
          )
        end
        format.json { render json: { ok: true, value: value } }
      end
    else
      render json: { ok: true, value: value }
    end
  end

  private

  def set_enrollment
    @enrollment = Enrollment.find(params[:id])
  end

  def set_student
    @student = Student.find(params[:student_id])
  end

  def enrollment_params
    params.require(:enrollment).permit(:teacher_id, :subject, :lesson_day, :lesson_time, :status)
  end
end
