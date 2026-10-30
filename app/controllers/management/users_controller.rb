module Management
  class UsersController < BaseController
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
  end
end
