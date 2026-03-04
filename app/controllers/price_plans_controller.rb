class PricePlansController < ApplicationController
  before_action :set_price_plan, only: %i[edit update destroy]

  def index
    @price_plans = PricePlan.order(:subject, :months)
  end

  def new
    @price_plan = PricePlan.new
  end

  def create
    @price_plan = PricePlan.new(price_plan_params)
    if @price_plan.save
      redirect_to price_plans_path, notice: "가격이 등록되었습니다."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @price_plan.update(price_plan_params)
      redirect_to price_plans_path, notice: "가격이 수정되었습니다."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @price_plan.update!(active: false)
    redirect_to price_plans_path, notice: "가격이 비활성화되었습니다."
  end

  private

  def set_price_plan
    @price_plan = PricePlan.find(params[:id])
  end

  def price_plan_params
    params.require(:price_plan).permit(:subject, :months, :amount, :active)
  end
end
