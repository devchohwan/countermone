class TeacherSubjectsController < ApplicationController
  def create
    teacher = Teacher.find(params[:teacher_id])
    teacher.teacher_subjects.create!(subject: params[:subject])
    redirect_to edit_teacher_path(teacher), notice: "과목이 추가되었습니다."
  end

  def destroy
    ts = TeacherSubject.find(params[:id])
    teacher = ts.teacher
    ts.destroy
    redirect_to edit_teacher_path(teacher), notice: "과목이 삭제되었습니다."
  end
end
