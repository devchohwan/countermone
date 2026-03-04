class EnrollmentsController < ApplicationController
  before_action :set_enrollment, only: %i[show edit update destroy leave return dropout]
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
