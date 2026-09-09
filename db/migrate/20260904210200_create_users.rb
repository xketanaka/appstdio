class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.citext :email, null: false
      t.string :password_digest, null: false

      # メール到達確認
      t.datetime :email_verified_at
      t.string :email_verification_token
      t.datetime :email_verification_token_expires_at

      # パスワード再設定
      t.string :password_reset_token
      t.datetime :password_reset_token_expires_at

      t.datetime :last_signed_in_at

      t.timestamps

      t.index :email, unique: true
      t.index :email_verification_token,
        unique: true,
        where: "email_verification_token IS NOT NULL"
      t.index :password_reset_token,
        unique: true,
        where: "password_reset_token IS NOT NULL"
    end
  end
end
