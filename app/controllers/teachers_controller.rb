class TeachersController < ApplicationController
  before_action :set_teacher, only: %i[show edit update destroy]

  def index
    @teachers = Teacher.includes(:teacher_subjects, :enrollments)
  end

  def show
    @enrollments = @teacher.enrollments.includes(:student).where(status: "active").order(:subject)
  end

  def new
    @teacher = Teacher.new
  end

  def create
    @teacher = Teacher.new(teacher_params)
    if @teacher.save
      save_subjects(@teacher)
      redirect_to teachers_path, notice: "선생님이 등록되었습니다."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @teacher.update(teacher_params)
      save_subjects(@teacher)
      redirect_to teachers_path, notice: "선생님 정보가 수정되었습니다."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def reorder
    ids = params[:ids]
    ids.each_with_index do |id, index|
      Teacher.where(id: id).update_all(position: index + 1)
    end
    head :ok
  end

  def destroy
    if @teacher.enrollments.where(status: "active").any?
      redirect_to teachers_path, alert: "재원 수강생이 있는 선생님은 삭제할 수 없습니다."
    else
      @teacher.destroy
      redirect_to teachers_path, notice: "선생님이 삭제되었습니다."
    end
  end

  private

  def set_teacher
    @teacher = Teacher.find(params[:id])
  end

  def teacher_params
    params.require(:teacher).permit(:name)
  end

  def save_subjects(teacher)
    selected = Array(params[:subjects]).reject(&:blank?)
    teacher.teacher_subjects.destroy_all
    selected.each do |subj|
      teacher.teacher_subjects.create!(subject: subj)
    end
  end
end
