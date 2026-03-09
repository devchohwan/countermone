class EnrollmentsController < ApplicationController
  before_action :set_enrollment, only: %i[show edit update destroy leave return dropout reschedule_form reschedule]
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
    if @enrollment.update(enrollment_params)
      redirect_to enrollment_path(@enrollment), notice: "클래스 정보가 수정되었습니다."
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
    @enrollment.leave!
    redirect_to enrollment_path(@enrollment), notice: "클래스 휴원 처리되었습니다."
  end

  def return
    if @enrollment.returnable?
      @enrollment.return!
      redirect_to enrollment_path(@enrollment), notice: "클래스 복귀 처리되었습니다."
    else
      redirect_to enrollment_path(@enrollment), alert: "완납 이후에만 복귀 처리가 가능합니다."
    end
  end

  def dropout
    @enrollment.dropout!
    redirect_to student_path(@enrollment.student), notice: "클래스 퇴원 처리되었습니다."
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
