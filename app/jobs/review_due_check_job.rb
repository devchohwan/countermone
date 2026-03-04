class ReviewDueCheckJob < ApplicationJob
  queue_as :default

  def perform
    Student.where(review_due: ..Date.today)
           .where.not(review_url: [nil, ""])
           .where(review_due: Date.today)
           .each do |student|
      student.update!(contact_due: Date.today) if student.contact_due.nil?
    end

    # review_due 도래 + URL 미입력
    Student.where(review_due: ..Date.today)
           .where(review_url: [nil, ""])
           .each do |student|
      student.update!(contact_due: Date.today) unless student.contact_due
    end
  end
end
