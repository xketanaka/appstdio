class RemovePasswordResetTokenFromUsers < ActiveRecord::Migration[8.1]
  def change
    remove_index :users, :password_reset_token, unique: true, where: "password_reset_token IS NOT NULL"
    remove_column :users, :password_reset_token, :string
    remove_column :users, :password_reset_token_expires_at, :datetime
  end
end
