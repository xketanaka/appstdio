module Management
  class UsersController < BaseController
    PER_PAGE = 30

    before_action :set_tenant_user, only: [:show, :edit, :update, :confirm_destroy, :destroy]
    before_action :deletable_required, only: [:confirm_destroy, :destroy]

    def index
      @tenant_users = TenantUser.not_deleted.includes(:user).order(:id)
    end

    def show
      memberships = @tenant_user.group_members.joins(:group).merge(Group.active).includes(:group).index_by(&:group_id)
      # 同じ名前のグループを見分けられるよう、最上位からの並びを添えて、その順に出す
      @memberships = Group.sort_by_name_path(memberships.values.map(&:group)).map { |group, path| [memberships[group.id], path] }
    end

    def new
      @tenant_user = TenantUser.new(role: :member)
      @groups = []
    end

    def create
      attributes = params.expect(tenant_user: [:email, :display_name, :role, group_ids: []])
      raise ActiveRecord::RecordNotFound unless current_tenant_user.assignable_roles.include?(attributes[:role])

      @group_ids = attributes.fetch(:group_ids, []).compact_blank.map(&:to_i).uniq
      @tenant_user = TenantUser.invite(tenant: current_tenant, email: attributes[:email].to_s, group_ids: @group_ids,
        display_name: attributes[:display_name], role: attributes[:role])

      if @tenant_user.errors.empty?
        redirect_to management_user_path(@tenant_user), notice: t("messages.created")
      else
        @groups = Group.sort_by_name_path(Group.department.active.where(id: @group_ids).to_a)
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      @groups = Group.sort_by_name_path(Group.department.active.where(id: @tenant_user.group_members.select(:group_id)).to_a)
    end

    def update
      attributes = params.expect(tenant_user: [:display_name, :role, :status, group_ids: []])
      # 変えられない権限・状態は画面に欄が無く、送られてこない
      role = attributes[:role] || @tenant_user.role
      status = attributes[:status] || @tenant_user.status
      unless current_tenant_user.role_choices_for(@tenant_user).include?(role) &&
          current_tenant_user.status_choices_for(@tenant_user).include?(status)
        raise ActiveRecord::RecordNotFound
      end

      @group_ids = attributes.fetch(:group_ids, []).compact_blank.map(&:to_i).uniq
      if @tenant_user.update_with_groups({ display_name: attributes[:display_name], role:, status: }, @group_ids)
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

    def deletable_required
      raise ActiveRecord::RecordNotFound unless @tenant_user.deletable_by?(current_tenant_user)
    end
  end
end
