class SplitMixingSubject < ActiveRecord::Migration[8.0]
  def up
    # TeacherSubject: 믹싱 → 믹싱1차 + 믹싱2차
    TeacherSubject.where(subject: "믹싱").each do |ts|
      ts.update_column(:subject, "믹싱1차")
      TeacherSubject.create!(teacher_id: ts.teacher_id, subject: "믹싱2차")
    end

    # PricePlan: 믹싱 → 믹싱1차 + 믹싱2차 (same prices)
    PricePlan.where(subject: "믹싱").each do |plan|
      plan.update_column(:subject, "믹싱1차")
      PricePlan.create!(subject: "믹싱2차", months: plan.months, amount: plan.amount, active: plan.active)
    end

    # Enrollment: rank == "second" → 믹싱2차, else → 믹싱1차
    Enrollment.where(subject: "믹싱").each do |e|
      new_subject = e.student.rank == "second" ? "믹싱2차" : "믹싱1차"
      e.update_column(:subject, new_subject)
    end

    # Schedule
    Schedule.where(subject: "믹싱").each do |s|
      new_subject = s.enrollment&.subject || "믹싱1차"
      s.update_column(:subject, new_subject)
    end

    # Payment
    Payment.where(subject: "믹싱").each do |p|
      new_subject = p.enrollment&.subject || "믹싱1차"
      p.update_column(:subject, new_subject)
    end
  end

  def down
    TeacherSubject.where(subject: "믹싱2차").delete_all
    TeacherSubject.where(subject: "믹싱1차").update_all(subject: "믹싱")
    PricePlan.where(subject: "믹싱2차").delete_all
    PricePlan.where(subject: "믹싱1차").update_all(subject: "믹싱")
    Enrollment.where(subject: %w[믹싱1차 믹싱2차]).update_all(subject: "믹싱")
    Schedule.where(subject: %w[믹싱1차 믹싱2차]).update_all(subject: "믹싱")
    Payment.where(subject: %w[믹싱1차 믹싱2차]).update_all(subject: "믹싱")
  end
end
