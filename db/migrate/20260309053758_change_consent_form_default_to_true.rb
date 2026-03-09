class ChangeConsentFormDefaultToTrue < ActiveRecord::Migration[8.0]
  def change
    change_column_default :students, :consent_form, from: false, to: true
  end
end
