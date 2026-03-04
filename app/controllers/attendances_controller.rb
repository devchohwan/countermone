class AttendancesController < ApplicationController
  before_action :set_attendance, only: %i[update destroy]

  def create
    @attendance = Attendance.new(attendance_params)
    if @attendance.save
      render json: { message: "출결 기록이 생성되었습니다." }
    else
      render json: { errors: @attendance.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    if @attendance.update(attendance_params)
      render json: { message: "출결 기록이 수정되었습니다." }
    else
      render json: { errors: @attendance.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    @attendance.destroy
    render json: { message: "출결 기록이 삭제되었습니다." }
  end

  private

  def set_attendance
    @attendance = Attendance.find(params[:id])
  end

  def attendance_params
    params.require(:attendance).permit(:student_id, :schedule_id, :payment_id,
                                       :checked_in_at, :checked_out_at, :error_type)
  end
end
