class AddApprovalToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :approved, :boolean, default: false, null: false
    add_column :users, :admin,    :boolean, default: false, null: false
    User.update_all(approved: true, admin: true)
  end
end
