module Files
  module Api
    # 共有設定で加える相手の候補。テナントの所属の人（有効・招待中）と、有効なグループ（「全員」を含む）。
    # 利用停止中のグループは新しく選べない（doc/groups.md の「利用停止」）
    class ShareCandidatesController < BaseController
      LIMIT = 10

      def index
        pattern = "%#{TenantUser.sanitize_sql_like(params[:q].to_s.strip)}%"
        groups = Group.active.where("name ILIKE ?", pattern).order(:kind, :name).limit(LIMIT)
        paths = Group.name_paths_of(groups.to_a)
        users = TenantUser.where(status: [:active, :invited]).joins(:user)
          .where("tenant_users.display_name ILIKE :pattern OR users.email ILIKE :pattern", pattern:)
          .includes(:user).order(:display_name).limit(LIMIT)

        render json: {
          candidates: groups.map { { type: "group", id: it.id, name: it.name, everyone: it.everyone?, suspended: false, deleted: false, path: paths.fetch(it.id), detail: nil } } +
            users.map { { type: "tenant_user", id: it.id, name: it.display_name, everyone: false, suspended: false, deleted: false, path: nil, detail: it.user.email } },
        }
      end
    end
  end
end
