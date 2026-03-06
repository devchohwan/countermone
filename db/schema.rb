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

ActiveRecord::Schema[8.0].define(version: 2026_03_06_104212) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

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
    t.integer "remaining_on_leave", default: 0
    t.integer "minus_lesson_count", default: 0
    t.boolean "attendance_event_pending", default: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
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

  create_table "students", force: :cascade do |t|
    t.string "name", null: false
    t.string "phone", null: false
    t.integer "age"
    t.string "attendance_code", null: false
    t.string "status", default: "active", null: false
    t.string "rank", default: "first", null: false
    t.boolean "has_car", default: false
    t.boolean "consent_form", default: false
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
    t.bigint "referrer_id"
    t.boolean "referral_discount_pending", default: false
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
    t.index ["referrer_id"], name: "index_students_on_referrer_id"
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
  end

  create_table "users", force: :cascade do |t|
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "name"
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
  add_foreign_key "students", "students", column: "referrer_id"
  add_foreign_key "teacher_subjects", "teachers"
end
