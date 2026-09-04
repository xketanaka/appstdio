module SessionsHelper
  # ログイン中のUserインスタンスを返す
  def current_user
    return @current_user if @current_user.present?
    return if session[:current_user_id].blank?

    @current_user = User.find_by_id(session[:current_user_id])
  end

  # ログイン状況のチェック（ユーザの利用機関の加入状態もチェック）
  def logged_in?
    current_user.present?
  end
end
