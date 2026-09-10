class ApplicationController < ActionController::Base
  include FormatUtils
  include SessionsHelper
  # login_required より先に include すること。
  # around_action が後続のコールバックとアクションを包む必要がある。
  include TenantContextFilter
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  # Prevent CSRF attacks by raising an exception.
  # For APIs, you may want to use :null_session instead.
  protect_from_forgery with: :exception
  before_action :login_required
  before_action :tenant_required

  class BaseForm
    include ActiveModel::Model
    # include ::Mixin::PathBuilder
    attr_accessor :user, :count

    def initialize(args = nil)
      args_hash = args.respond_to?(:to_unsafe_hash) ? args.to_unsafe_hash : args
      super(args_hash ? self.initial.merge(args_hash) : self.initial)
      self.page ||= 1
    end

    def initial
      {}
    end

    def self.form_name
      self.model_name.singular
    end

    def to_hash
      form_name = self.class.form_name
      instance_variables
        .map { |var| var.to_s.tr('@', '') }
        .select { |var| self.class.method_defined?("#{var}=") && self.class.method_defined?(var) }
        .each_with_object({}) do |var, hash|
        next if var === "user"

        hash["#{form_name}[#{var}]".to_sym] = instance_variable_get("@#{var}".to_sym)
      end
    end
  end

  def login_required
    return if logged_in?

    # fullpath は必ず自サイト内のパスなので、オープンリダイレクトにならない
    session[:return_to] = request.fullpath if request.get?
    redirect_to login_path
  end

  # ログイン済みでもテナントを選ぶまでは業務画面に入れない
  def tenant_required
    return if current_tenant_user.present?

    redirect_to select_tenant_path
  end

  rescue_from ActiveRecord::RecordNotFound do |e|
    Utils.error_log(e, logger)
    render_error(403, e)
  end

  rescue_from ActiveRecord::RecordNotUnique do |e|
    Utils.error_log(e, logger)
    flash[:error] = I18n.t("messages.record_dupplicated")
    redirect_to top_page_path
  end

  def render_error(status, e)
    if request.xhr?
      render js: "alert('#{I18n.t("messages.http.errors.js.#{status}")}')", status: status
    else
      render file: Rails.root.join("public/#{status}.html"), status: status, layout: false
    end
  end
end
