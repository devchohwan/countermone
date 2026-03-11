class CreateStudentReferralsAndRemoveReferrerId < ActiveRecord::Migration[8.0]
  def change
    create_table :student_referrals do |t|
      t.references :referred_student, null: false, foreign_key: { to_table: :students }
      t.references :referrer,         null: false, foreign_key: { to_table: :students }
      t.timestamps
    end

    add_index :student_referrals, [:referred_student_id, :referrer_id], unique: true

    remove_column :students, :referrer_id, :bigint
  end
end
