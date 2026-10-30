module Management
  class UsersController < BaseController
    # 追加の画面で選べる権限。オーナーは選べない
    ROLES = %w[member admin].freeze

    def index
      @tenant_users = TenantUser.not_deleted.includes(:user).order(:id)
    end

    def show
      @tenant_user = TenantUser.not_deleted.includes(:user).find(params[:id])
      memberships = @tenant_user.group_members.includes(:group).to_a
      paths = Group.name_paths_of(memberships.map(&:group))
      # 同じ名前のグループを見分けられるよう、最上位からの並びで出す
      @memberships = memberships.sort_by { paths[it.group_id] }.map { [it, paths[it.group_id]] }
    end

    def new
      @tenant_user = TenantUser.new(role: :member)
      @group_ids = []
      load_group_choices
    end

    def create
      attributes = params.expect(tenant_user: [:email, :display_name, :role, group_ids: []])
      raise ActiveRecord::RecordNotFound unless ROLES.include?(attributes[:role])

      @group_ids = attributes.fetch(:group_ids, []).compact_blank.map(&:to_i)
      @tenant_user = TenantUser.invite(tenant: current_tenant, email: attributes[:email].to_s, group_ids: @group_ids,
        display_name: attributes[:display_name], role: attributes[:role])

      if @tenant_user.errors.empty?
        redirect_to management_user_path(@tenant_user), notice: t("messages.created")
      else
        load_group_choices
        render :new, status: :unprocessable_entity
      end
    end

    private

    # 所属グループの選択肢。有効なグループを、最上位からの並びの順に
    def load_group_choices
      groups = Group.department.active.to_a
      paths = Group.name_paths_of(groups)
      @group_choices = groups.sort_by { paths[it.id] }.map { [it, paths[it.id]] }
    end
  end
end
