class MakePaymentOptionalInAttendances < ActiveRecord::Migration[8.0]
  def change
    change_column_null :attendances, :payment_id, true
  end
end
