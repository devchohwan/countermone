# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2026_03_13_083752) do
  create_table "attendances", force: :cascade do |t|
    t.bigint "student_id", null: false
    t.bigint "schedule_id", null: false
    t.bigint "payment_id", null: false
    t.datetime "checked_in_at"
    t.datetime "checked_out_at"
    t.string "error_type"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["payment_id"], name: "index_attendances_on_payment_id"
    t.index ["schedule_id"], name: "index_attendances_on_schedule_id"
    t.index ["student_id"], name: "index_attendances_on_student_id"
  end

  create_table "breaktime_openings", force: :cascade do |t|
    t.bigint "teacher_id", null: false
    t.date "date", null: false
    t.string "created_by"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["teacher_id"], name: "index_breaktime_openings_on_teacher_id"
  end

  create_table "discounts", force: :cascade do |t|
    t.bigint "payment_id", null: false
    t.string "discount_type", null: false
    t.integer "amount", null: false
    t.text "memo"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["payment_id"], name: "index_discounts_on_payment_id"
  end

  create_table "enrollments", force: :cascade do |t|
    t.bigint "student_id", null: false
    t.bigint "teacher_id", null: false
    t.string "subject", null: false
    t.string "lesson_day", null: false
    t.time "lesson_time", null: false
    t.string "status", default: "active", null: false
    t.date "leave_at"
    t.date "return_at"
    t.integer "minus_lesson_count", default: 0
    t.boolean "attendance_event_pending", default: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "leave_reason"
    t.date "last_attendance_event_at"
    t.integer "consecutive_weeks_offset", default: 0, null: false
    t.integer "gift_voucher_eligible_offset", default: 0, null: false
    t.integer "pass_offset", default: 0, null: false
    t.date "last_review_discount_at"
    t.boolean "review_gift_eligible", default: false
    t.index ["student_id"], name: "index_enrollments_on_student_id"
    t.index ["teacher_id"], name: "index_enrollments_on_teacher_id"
  end

  create_table "gift_vouchers", force: :cascade do |t|
    t.bigint "student_id", null: false
    t.bigint "enrollment_id", null: false
    t.date "issued_at"
    t.boolean "used", default: false
    t.string "used_class"
    t.date "expires_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.date "used_at"
    t.index ["enrollment_id"], name: "index_gift_vouchers_on_enrollment_id"
    t.index ["student_id"], name: "index_gift_vouchers_on_student_id"
  end

  create_table "payments", force: :cascade do |t|
    t.bigint "student_id", null: false
    t.bigint "enrollment_id", null: false
    t.string "payment_type", null: false
    t.string "subject", null: false
    t.integer "months"
    t.integer "total_lessons", null: false
    t.integer "amount", null: false
    t.string "payment_method", null: false
    t.boolean "before_lesson", default: false
    t.integer "deposit_amount", default: 0
    t.datetime "deposit_paid_at"
    t.integer "balance_amount", default: 0
    t.datetime "balance_paid_at"
    t.boolean "fully_paid", default: false
    t.boolean "refunded", default: false
    t.integer "refund_amount", default: 0
    t.text "refund_reason"
    t.date "starts_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["enrollment_id"], name: "index_payments_on_enrollment_id"
    t.index ["student_id"], name: "index_payments_on_student_id"
  end

  create_table "price_plans", force: :cascade do |t|
    t.string "subject", null: false
    t.integer "months", null: false
    t.integer "amount", null: false
    t.boolean "active", default: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "schedules", force: :cascade do |t|
    t.bigint "student_id", null: false
    t.bigint "enrollment_id", null: false
    t.bigint "payment_id", null: false
    t.bigint "teacher_id", null: false
    t.date "lesson_date", null: false
    t.time "lesson_time", null: false
    t.string "subject", null: false
    t.string "status", default: "scheduled", null: false
    t.integer "sequence", null: false
    t.date "makeup_date"
    t.time "makeup_time"
    t.bigint "makeup_teacher_id"
    t.boolean "makeup_approved", default: false
    t.text "pass_reason"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "from_pass", default: false
    t.index ["enrollment_id"], name: "index_schedules_on_enrollment_id"
    t.index ["lesson_date"], name: "index_schedules_on_lesson_date"
    t.index ["makeup_date"], name: "index_schedules_on_makeup_date"
    t.index ["makeup_teacher_id"], name: "index_schedules_on_makeup_teacher_id"
    t.index ["payment_id"], name: "index_schedules_on_payment_id"
    t.index ["student_id"], name: "index_schedules_on_student_id"
    t.index ["teacher_id"], name: "index_schedules_on_teacher_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "ip_address"
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "solid_queue_blocked_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.string "concurrency_key", null: false
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.index ["concurrency_key", "priority", "job_id"], name: "index_solid_queue_blocked_executions_for_release"
    t.index ["expires_at", "concurrency_key"], name: "index_solid_queue_blocked_executions_for_maintenance"
    t.index ["job_id"], name: "index_solid_queue_blocked_executions_on_job_id", unique: true
  end

  create_table "solid_queue_claimed_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.bigint "process_id"
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_claimed_executions_on_job_id", unique: true
    t.index ["process_id", "job_id"], name: "index_solid_queue_claimed_executions_on_process_id_and_job_id"
  end

  create_table "solid_queue_failed_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.text "error"
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_failed_executions_on_job_id", unique: true
  end

  create_table "solid_queue_jobs", force: :cascade do |t|
    t.string "queue_name", null: false
    t.string "class_name", null: false
    t.text "arguments"
    t.integer "priority", default: 0, null: false
    t.string "active_job_id"
    t.datetime "scheduled_at"
    t.datetime "finished_at"
    t.string "concurrency_key"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active_job_id"], name: "index_solid_queue_jobs_on_active_job_id"
    t.index ["class_name"], name: "index_solid_queue_jobs_on_class_name"
    t.index ["finished_at"], name: "index_solid_queue_jobs_on_finished_at"
    t.index ["queue_name", "finished_at"], name: "index_solid_queue_jobs_for_filtering"
    t.index ["scheduled_at", "finished_at"], name: "index_solid_queue_jobs_for_alerting"
  end

  create_table "solid_queue_pauses", force: :cascade do |t|
    t.string "queue_name", null: false
    t.datetime "created_at", null: false
    t.index ["queue_name"], name: "index_solid_queue_pauses_on_queue_name", unique: true
  end

  create_table "solid_queue_processes", force: :cascade do |t|
    t.string "kind", null: false
    t.datetime "last_heartbeat_at", null: false
    t.bigint "supervisor_id"
    t.integer "pid", null: false
    t.string "hostname"
    t.text "metadata"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.index ["last_heartbeat_at"], name: "index_solid_queue_processes_on_last_heartbeat_at"
    t.index ["name", "supervisor_id"], name: "index_solid_queue_processes_on_name_and_supervisor_id", unique: true
    t.index ["supervisor_id"], name: "index_solid_queue_processes_on_supervisor_id"
  end

  create_table "solid_queue_ready_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_ready_executions_on_job_id", unique: true
    t.index ["priority", "job_id"], name: "index_solid_queue_poll_all"
    t.index ["queue_name", "priority", "job_id"], name: "index_solid_queue_poll_by_queue"
  end

  create_table "solid_queue_recurring_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "task_key", null: false
    t.datetime "run_at", null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_recurring_executions_on_job_id", unique: true
    t.index ["task_key", "run_at"], name: "index_solid_queue_recurring_executions_on_task_key_and_run_at", unique: true
  end

  create_table "solid_queue_recurring_tasks", force: :cascade do |t|
    t.string "key", null: false
    t.string "schedule", null: false
    t.string "command", limit: 2048
    t.string "class_name"
    t.text "arguments"
    t.string "queue_name"
    t.integer "priority", default: 0
    t.boolean "static", default: true, null: false
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_solid_queue_recurring_tasks_on_key", unique: true
    t.index ["static"], name: "index_solid_queue_recurring_tasks_on_static"
  end

  create_table "solid_queue_scheduled_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.datetime "scheduled_at", null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_scheduled_executions_on_job_id", unique: true
    t.index ["scheduled_at", "priority", "job_id"], name: "index_solid_queue_dispatch_all"
  end

  create_table "solid_queue_semaphores", force: :cascade do |t|
    t.string "key", null: false
    t.integer "value", default: 1, null: false
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["expires_at"], name: "index_solid_queue_semaphores_on_expires_at"
    t.index ["key", "value"], name: "index_solid_queue_semaphores_on_key_and_value"
    t.index ["key"], name: "index_solid_queue_semaphores_on_key", unique: true
  end

  create_table "student_referrals", force: :cascade do |t|
    t.integer "referred_student_id", null: false
    t.integer "referrer_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["referred_student_id", "referrer_id"], name: "index_student_referrals_on_referred_student_id_and_referrer_id", unique: true
    t.index ["referred_student_id"], name: "index_student_referrals_on_referred_student_id"
    t.index ["referrer_id"], name: "index_student_referrals_on_referrer_id"
  end

  create_table "students", force: :cascade do |t|
    t.string "name", null: false
    t.string "phone", null: false
    t.integer "age"
    t.string "attendance_code", null: false
    t.string "status", default: "active", null: false
    t.string "rank", default: "first", null: false
    t.boolean "has_car", default: false
    t.boolean "consent_form", default: true
    t.boolean "second_transfer_form", default: false
    t.boolean "cover_recorded", default: false
    t.text "reason_for_joining"
    t.text "own_problem"
    t.text "desired_goal"
    t.date "first_enrolled_at"
    t.boolean "expected_return"
    t.text "leave_reason"
    t.text "real_leave_reason"
    t.date "contact_due"
    t.boolean "refund_leave", default: false
    t.boolean "review_discount_applied", default: false
    t.string "review_url"
    t.date "review_due"
    t.boolean "interview_discount_applied", default: false
    t.boolean "interview_completed", default: false
    t.boolean "gift_voucher_issued", default: false
    t.date "waiting_expires_at"
    t.text "memo"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "referral_discount_pending", default: 0, null: false
  end

  create_table "teacher_subjects", force: :cascade do |t|
    t.bigint "teacher_id", null: false
    t.string "subject", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["teacher_id"], name: "index_teacher_subjects_on_teacher_id"
  end

  create_table "teachers", force: :cascade do |t|
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "position"
    t.integer "max_lesson_hour", default: 21, null: false
    t.integer "monday_max_lesson_hour", default: 17, null: false
  end

  create_table "users", force: :cascade do |t|
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "name"
    t.boolean "approved", default: false, null: false
    t.boolean "admin", default: false, null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  add_foreign_key "attendances", "payments"
  add_foreign_key "attendances", "schedules"
  add_foreign_key "attendances", "students"
  add_foreign_key "breaktime_openings", "teachers"
  add_foreign_key "discounts", "payments"
  add_foreign_key "enrollments", "students"
  add_foreign_key "enrollments", "teachers"
  add_foreign_key "gift_vouchers", "enrollments"
  add_foreign_key "gift_vouchers", "students"
  add_foreign_key "payments", "enrollments"
  add_foreign_key "payments", "students"
  add_foreign_key "schedules", "enrollments"
  add_foreign_key "schedules", "payments"
  add_foreign_key "schedules", "students"
  add_foreign_key "schedules", "teachers"
  add_foreign_key "schedules", "teachers", column: "makeup_teacher_id"
  add_foreign_key "sessions", "users"
  add_foreign_key "solid_queue_blocked_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_claimed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_failed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_ready_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_recurring_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_scheduled_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "student_referrals", "students", column: "referred_student_id"
  add_foreign_key "student_referrals", "students", column: "referrer_id"
  add_foreign_key "teacher_subjects", "teachers"
end
