module Management
  class UsersController < BaseController
    PER_PAGE = 30

    before_action :set_tenant_user, except: [:index, :suspended, :new, :create, :group_candidates]
    # 停止中の人は詳細を見て、再開か削除をするだけ。編集はできない
    before_action :reject_suspended, only: [:edit, :update]
    before_action :deletable_required, only: [:confirm_destroy, :destroy]
    before_action :suspendable_required, only: [:confirm_suspend, :suspend]

    # 停止中の人は「利用停止中の利用者」に分けて出す
    def index
      @tenant_users = TenantUser.where(status: [:invited, :active]).includes(:user, :labels, :avatar_attachment).order(:id)
    end

    # 利用停止中の利用者の一覧。新しく止めた順に30件ずつ出し、下までスクロールすると読み足す。
    # キーワードは表示名とメールアドレスに当てる
    def suspended
      @query = params[:q].to_s.strip
      page = [params[:page].to_i, 1].max

      users = TenantUser.suspended.joins(:user).includes(:user, :suspended_by, :avatar_attachment)
      if @query.present?
        users = users.where("tenant_users.display_name ILIKE :pattern OR users.email ILIKE :pattern",
          pattern: "%#{TenantUser.sanitize_sql_like(@query)}%")
      end
      users = users.order(suspended_at: :desc, id: :desc).offset((page - 1) * PER_PAGE).limit(PER_PAGE + 1).to_a
      @next_page = (page + 1 if users.size > PER_PAGE)
      @tenant_users = users.first(PER_PAGE)

      render partial: "suspended_rows", layout: false if page > 1
    end

    def show
      @labels = @tenant_user.labels.order(:name).pluck(:name)
      memberships = @tenant_user.group_members.joins(:group).merge(Group.active).includes(:group).index_by(&:group_id)
      # 同じ名前のグループを見分けられるよう、最上位からの並びを添えて、その順に出す
      @memberships = Group.sort_by_name_path(memberships.values.map(&:group)).map { |group, path| [memberships[group.id], path] }
    end

    def new
      @tenant_user = TenantUser.new(role: :member)
      @groups = []
      @label_names = []
    end

    def create
      attributes = params.expect(tenant_user: [:email, :display_name, :role, :label_names, group_ids: []])
      raise ActiveRecord::RecordNotFound unless current_tenant_user.assignable_roles.include?(attributes[:role])

      @group_ids = attributes.fetch(:group_ids, []).compact_blank.map(&:to_i).uniq
      @label_names = label_names_from(attributes[:label_names])
      @tenant_user = TenantUser.invite(tenant: current_tenant, email: attributes[:email].to_s, group_ids: @group_ids,
        label_names: @label_names, display_name: attributes[:display_name], role: attributes[:role])

      if @tenant_user.errors.empty?
        redirect_to management_user_path(@tenant_user), notice: t("messages.created")
      else
        @groups = Group.sort_by_name_path(Group.department.active.where(id: @group_ids).to_a)
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      @label_names = @tenant_user.labels.order(:name).pluck(:name)
      @groups = Group.sort_by_name_path(Group.department.active.where(id: @tenant_user.group_members.select(:group_id)).to_a)
    end

    def update
      attributes = params.expect(tenant_user: [:display_name, :role, :status, :label_names, group_ids: []])
      # 変えられない権限・状態は画面に欄が無く、送られてこない
      role = attributes[:role] || @tenant_user.role
      status = attributes[:status] || @tenant_user.status
      unless current_tenant_user.role_choices_for(@tenant_user).include?(role) &&
          current_tenant_user.status_choices_for(@tenant_user).include?(status)
        raise ActiveRecord::RecordNotFound
      end

      @group_ids = attributes.fetch(:group_ids, []).compact_blank.map(&:to_i).uniq
      @label_names = label_names_from(attributes[:label_names])
      attributes = { display_name: attributes[:display_name], role:, status: }
      if @tenant_user.update_with(attributes, group_ids: @group_ids, label_names: @label_names)
        # 自分の権限をメンバーに下げると、管理の画面を開けなくなる
        if @tenant_user.id == current_tenant_user.id && !@tenant_user.admin_or_owner?
          redirect_to top_page_path, notice: t("messages.saved")
        else
          redirect_to management_user_path(@tenant_user), notice: t("messages.saved")
        end
      else
        @groups = Group.sort_by_name_path(Group.department.active.where(id: @group_ids).to_a)
        render :edit, status: :unprocessable_entity
      end
    end

    # 所属グループの追加のダイアログの候補。有効なグループをグループ名で探し、最上位からの並びの順に
    # 30件ずつ返す。ダイアログがスクロールに合わせて読み足す。並べるために当てはまるものを全件読むが、
    # グループ管理のツリーも全件を読んで描いているので、同じ前提に立つ
    def group_candidates
      page = [params[:page].to_i, 1].max
      groups = Group.department.active
      groups = groups.where("groups.name ILIKE ?", "%#{Group.sanitize_sql_like(params[:q].strip)}%") if params[:q].present?
      candidates = Group.sort_by_name_path(groups.to_a).drop((page - 1) * PER_PAGE)
      @next_page = (page + 1 if candidates.size > PER_PAGE)
      @candidates = candidates.first(PER_PAGE)
      render partial: "group_candidates", layout: false
    end

    def confirm_suspend
    end

    def suspend
      if @tenant_user.suspend(by: current_tenant_user)
        redirect_to management_user_path(@tenant_user), notice: t(".done")
      else
        render :confirm_suspend, status: :unprocessable_entity
      end
    end

    def reactivate
      raise ActiveRecord::RecordNotFound unless @tenant_user.reactivatable_by?(current_tenant_user)

      @tenant_user.reactivate!
      redirect_to management_user_path(@tenant_user), notice: t(".done")
    end

    def confirm_destroy
    end

    def destroy
      @tenant_user.mark_deleted!
      redirect_to management_users_path, notice: t("messages.deleted")
    end

    private

    def set_tenant_user
      @tenant_user = TenantUser.not_deleted.includes(:user).find(params[:id])
    end

    # ラベルの欄の入力（カンマか読点で区切る）を名前の並びにする
    def label_names_from(text)
      text.to_s.split(/[,、]/).map(&:strip).compact_blank.uniq
    end

    def reject_suspended
      raise ActiveRecord::RecordNotFound if @tenant_user.suspended?
    end

    def deletable_required
      raise ActiveRecord::RecordNotFound unless @tenant_user.deletable_by?(current_tenant_user)
    end

    def suspendable_required
      raise ActiveRecord::RecordNotFound unless @tenant_user.suspendable_by?(current_tenant_user)
    end
  end
end
