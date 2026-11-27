class Operator < ApplicationRecord
  PASSWORD_RESET_EXPIRES_IN = 30.minutes

  # 再設定のトークンはパスワードの salt を含めて署名するので、パスワードを変えると使えなくなる
  has_secure_password reset_token: { expires_in: PASSWORD_RESET_EXPIRES_IN }
  # ログインのセッションに入れる印。パスワードの salt を含めて署名するので、パスワードを変えると他の端末のログインも切れる
  generates_token_for(:session) { password_salt&.last(10) }

  enum :status, { invited: "invited", active: "active", suspended: "suspended" }, validate: true

  normalizes :email, with: ->(email) { email.to_s.strip }

  validates :email,
    presence: true,
    length: { maximum: 255 },
    format: { with: URI::MailTo::EMAIL_REGEXP },
    uniqueness: true
  validates :password, length: { minimum: 8 }, allow_nil: true
  validates :display_name, presence: true, length: { maximum: 255 }

  # パスワード再設定のメールを送る。メールは後で送る。
  # URL はここで組み立てて渡す。メールのジョブは運営者画面のルートを持たないプロセス（利用者側）で動くことも
  # あるため。リクエストのホスト名は Host ヘッダで偽れるので使わず、OPS_URL から作る
  def send_password_reset
    url = Rails.application.routes.url_helpers.edit_ops_password_reset_url(password_reset_token,
      **Settings.url_options(Settings.ops_url))
    OperatorMailer.password_reset(to: email, url:, expires_at: PASSWORD_RESET_EXPIRES_IN.from_now).deliver_later
  end

  # 再設定のメールの URL から新しいパスワードを決める
  def reset_password(password:, password_confirmation:)
    # 空のパスワードは has_secure_password が黙って捨てるので、ここで弾く
    if password.empty?
      errors.add(:password, :blank)
      return false
    end
    update(password:, password_confirmation:)
  end
end
