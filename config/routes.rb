Rails.application.routes.draw do
  root "dashboard#index"
  get "dashboard/current_schedules", to: "dashboard#current_schedules"

  resource  :session
  resources :passwords, param: :token

  resources :students do
    collection do
      get :check_attendance_code
    end
    member do
      patch :leave
      patch :return
      patch :dropout
      patch :complete_contact
    end
    resources :enrollments, shallow: true do
      member do
        patch :leave
        patch :return
        patch :dropout
      end
    end
  end

  resources :payments do
    member do
      post  :refund
      patch :pay_balance
    end
  end

  resources :schedules do
    member do
      patch :attend
      patch :absent
      patch :late
      patch :deduct
      patch :pass
      patch :emergency_pass
      patch :makeup
      patch :approve_makeup
      patch :complete_makeup
      patch :undo_deduct
    end
  end

  resources :attendances, only: %i[create update destroy]

  get  "timetable",             to: "timetable#index"
  get  "timetable/:teacher_id", to: "timetable#show", as: :teacher_timetable
  get  "pass_sheet",            to: "timetable#pass_sheet"

  get  "keypad",          to: "keypad#index"
  post "keypad/checkin",  to: "keypad#checkin"
  post "keypad/checkout", to: "keypad#checkout"

  get "statistics",         to: "statistics#index"
  get "statistics/daily",   to: "statistics#daily"
  get "statistics/monthly", to: "statistics#monthly"

  resources :price_plans

  get "up" => "rails/health#show", as: :rails_health_check
end
