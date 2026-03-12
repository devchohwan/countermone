Rails.application.routes.draw do
  root "dashboard#index"
  get "slot_check", to: "slots#check"
  get "dashboard/current_schedules", to: "dashboard#current_schedules"
  get "dashboard/today_arrivals",    to: "dashboard#today_arrivals"

  resource  :session
  resources :passwords, param: :token

  get  "signup", to: "users#new",    as: :signup
  post "signup", to: "users#create"

  get    "approvals",          to: "users#approvals", as: :approvals
  patch  "users/:id/approve",  to: "users#approve",   as: :approve_user
  delete "users/:id/reject",   to: "users#reject",    as: :reject_user

  resources :students do
    collection do
      get :check_attendance_code
      get :search
    end
    member do
      patch :leave
      patch :return
      patch :dropout
      patch :complete_contact
      patch :update_memo
    end
    resources :enrollments, shallow: true do
      member do
        patch :leave
        patch :return
        patch :dropout
        patch :dismiss_attendance_event
        patch :add_lesson
        get   :reschedule_form
        patch :reschedule
        patch :update_stat
      end
    end
  end

  resources :payments do
    member do
      post  :refund
      patch :pay_balance
      patch :complete_deposit
    end
  end

  resources :schedules do
    member do
      patch :attend
      patch :checkout
      patch :late
      get   :makeup_slots
      patch :deduct
      patch :pass
      patch :emergency_pass
      patch :holiday
      patch :makeup
      patch :approve_makeup
      patch :complete_makeup
      patch :undo_deduct
      patch :undo_attend
      patch :cancel_pass
      patch :move_date
    end
  end

  resources :attendances, only: %i[create update destroy]

  resources :gift_vouchers, only: [:create] do
    member do
      patch :use
    end
  end

  get  "timetable",             to: "timetable#index"
  get  "timetable/:teacher_id", to: "timetable#show", as: :teacher_timetable
  get  "pass_sheet",            to: "timetable#pass_sheet"

  get  "keypad",          to: "keypad#index"
  post "keypad/checkin",  to: "keypad#checkin"
  post "keypad/checkout", to: "keypad#checkout"

  get "statistics",         to: "statistics#index"
  get "statistics/daily",   to: "statistics#daily"
  get "statistics/monthly", to: "statistics#monthly"

  resources :price_plans, except: [:show]

  resources :teachers do
    resources :teacher_subjects, only: %i[create destroy], shallow: true
    collection do
      patch :reorder
    end
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
