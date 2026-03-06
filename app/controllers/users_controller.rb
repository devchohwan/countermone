class UsersController < ApplicationController
  allow_unauthenticated_access only: %i[new create]

  def new
    @user = User.new
  end

  def create
    @user = User.new(user_params)
    if @user.save
      start_new_session_for @user
      redirect_to root_path, notice: "#{@user.name}님, 환영합니다!"
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def user_params
    params.expect(user: [:name, :email_address, :password, :password_confirmation])
  end
end
