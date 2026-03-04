class StudentsController < ApplicationController
  before_action :set_student, only: %i[show edit update destroy leave return dropout]

  def index
    @students = Student.includes(:enrollments, :teachers)
    @students = @students.where(status: params[:status]) if params[:status].present?
    @students = @students.where("name LIKE ?", "%#{params[:q]}%") if params[:q].present?
    @students = @students.order(:name)
  end

  def show
    @enrollments = @student.enrollments.includes(:teacher, :payments, :schedules)
  end

  def new
    @student = Student.new
    @student.attendance_code = suggest_attendance_code(@student)
    @student.enrollments.build.payments.build
    @teachers = Teacher.includes(:teacher_subjects).all
  end

  def create
    @student = Student.new(student_params)
    @student.status ||= "active"
    @student.first_enrolled_at ||= Date.today
    @student.waiting_expires_at = Date.today + 14.days if @student.status == "pending"

    ActiveRecord::Base.transaction do
      @student.enrollments.each do |enrollment|
        enrollment.status = "active"
        enrollment.payments.each do |payment|
          payment.student = @student
          payment.subject = enrollment.subject
          payment.fully_paid = (payment.payment_type == "new")
        end
      end
      
      if @student.save
        redirect_to @student, notice: "수강생이 등록되었습니다."
      else
        @teachers = Teacher.includes(:teacher_subjects).all
        render :new, status: :unprocessable_entity
      end
    end
  rescue ActiveRecord::RecordInvalid => e
    @teachers = Teacher.includes(:teacher_subjects).all
    @student.errors.add(:base, e.message)
    render :new, status: :unprocessable_entity
  end

  def edit
    @teachers = Teacher.includes(:teacher_subjects).all
  end

  def update
    if @student.update(student_params)
      redirect_to @student, notice: "수강생 정보가 수정되었습니다."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @student.destroy
    redirect_to students_path, notice: "수강생이 삭제되었습니다."
  end

  def leave
    @student.enrollments.where(status: "active").each(&:leave!)
    redirect_to @student, notice: "휴원 처리되었습니다."
  end

  def return
    ActiveRecord::Base.transaction do
      if params[:new_attendance_code].present?
        @student.attendance_code = params[:new_attendance_code]
        @student.save!
      end
      
      @student.enrollments.where(status: "leave").each do |e|
        if e.returnable?
          e.return!
        else
          raise ActiveRecord::Rollback, "완납 이후에만 복귀 처리가 가능합니다."
        end
      end
    end
    redirect_to @student, notice: "복귀 처리되었습니다."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to @student, alert: e.message
  rescue ActiveRecord::Rollback => e
    redirect_to @student, alert: e.message
  end

  def dropout
    @student.enrollments.where(status: %w[active leave]).each(&:dropout!)
    redirect_to @student, notice: "퇴원 처리되었습니다."
  end

  def check_attendance_code
    code = params[:code]
    student_id = params[:student_id]
    
    duplicate = Student.where(attendance_code: code, status: "active")
    duplicate = duplicate.where.not(id: student_id) if student_id.present?
    
    if duplicate.exists?
      render json: { available: false, student_name: duplicate.first.name }
    else
      render json: { available: true }
    end
  end

  private

  def set_student
    @student = Student.find(params[:id])
  end

  def student_params
    params.require(:student).permit(
      :name, :phone, :age, :attendance_code, :status, :rank,
      :has_car, :consent_form, :second_transfer_form, :cover_recorded,
      :reason_for_joining, :own_problem, :desired_goal, :first_enrolled_at,
      :expected_return, :leave_reason, :real_leave_reason, :contact_due,
      :refund_leave, :referrer_id, :review_discount_applied, :review_url,
      :review_due, :interview_discount_applied, :interview_completed,
      :memo, :waiting_expires_at,
      enrollments_attributes: [
        :id, :teacher_id, :subject, :lesson_day, :lesson_time, :status,
        payments_attributes: [
          :id, :payment_type, :subject, :months, :total_lessons, :amount,
          :payment_method, :starts_at, :deposit_amount, :deposit_paid_at,
          :balance_amount, :balance_paid_at, :fully_paid
        ]
      ]
    )
  end

  def suggest_attendance_code(student)
    return "" if student.phone.blank?
    base = student.phone.last(4)
    return base unless Student.where(attendance_code: base, status: "active").exists?
    extended = base + base.last
    return extended unless Student.where(attendance_code: extended, status: "active").exists?
    base[1..3] + base[0]
  end
end
