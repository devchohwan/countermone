class AddReviewFieldsToEnrollments < ActiveRecord::Migration[8.0]
  def change
    add_column :enrollments, :last_review_discount_at, :date
    add_column :enrollments, :review_gift_eligible, :boolean, default: false
  end
end
