class UsersController < ApplicationController
  allow_unauthenticated_access only: %i[new create]
  before_action :require_admin, only: %i[approvals approve reject]
  rate_limit to: 3, within: 10.minutes, only: [:create], with: -> {
    redirect_to signup_path, alert: "잠시 후 다시 시도해주세요."
  }

  def new
    @user = User.new
  end

  def create
    @user = User.new(user_params)
    if @user.save
      redirect_to new_session_path, notice: "가입이 완료되었습니다. 관리자 승인 후 로그인할 수 있습니다."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def approvals
    @pending_users = User.pending_approval.order(created_at: :asc)
  end

  def approve
    User.find(params[:id]).update!(approved: true)
    redirect_to approvals_path, notice: "승인되었습니다."
  end

  def reject
    User.find(params[:id]).destroy!
    redirect_to approvals_path, notice: "거절되었습니다."
  end

  private

  def user_params
    params.expect(user: [:name, :email_address, :password, :password_confirmation])
  end

  def require_admin
    redirect_to root_path, alert: "권한이 없습니다." unless Current.user&.admin?
  end
end
