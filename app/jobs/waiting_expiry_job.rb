class WaitingExpiryJob < ApplicationJob
  queue_as :default

  def perform
    Student.where(status: "pending")
           .where(waiting_expires_at: ..Date.today)
           .each do |student|
      student.enrollments.each do |enrollment|
        enrollment.schedules.where(status: "scheduled").destroy_all
        enrollment.update!(status: "dropout")
      end
      student.update!(status: "dropout")
    end
  end
end
