module Management
  class GroupsController < BaseController
    PER_PAGE = 30

    before_action :load_tree
    before_action :set_group, only: [:show, :edit, :update, :sub_members, :member_candidates]
    # 「全員」は名前もメンバーも変えられない
    before_action :reject_everyone, only: [:edit, :update, :sub_members, :member_candidates]

    def index
    end

    def show
      if @group.everyone?
        @tenant_users_count = TenantUser.active.where(tenant: current_tenant).count
        return
      end

      @members = members_of(@group)
      @labels = @group.labels.order(:name).pluck(:name)
      @parent_path = @group.self_and_ancestors.drop(1).reverse
      @has_children = Group.exists?(parent_id: @group.id)
      @sub_members_count = sub_members_of(@group).count
    end

    # 下位グループのメンバーの一覧を1ページ分だけ返す。詳細の画面がスクロールに合わせて読み足す
    def sub_members
      page = [params[:page].to_i, 1].max
      users = sub_members_of(@group).includes(:user).order(:display_name, :id)
        .offset((page - 1) * PER_PAGE).limit(PER_PAGE + 1).to_a
      @next_page = (page + 1 if users.size > PER_PAGE)
      users = users.first(PER_PAGE)
      groups = GroupMember.where(group_id: Group.descendant_ids_of(@group.id), tenant_user_id: users.map(&:id))
        .includes(:group).group_by(&:tenant_user_id)
      # 同じ人が複数の下位グループにいれば1行にまとめ、所属する下位グループを並べる
      @rows = users.map { |user| [user, groups.fetch(user.id).map(&:group).sort_by(&:name)] }
      render partial: "sub_member_rows", layout: false
    end

    # メンバーの追加のダイアログの候補。テナントの所属のうち有効・招待中の人を、表示名か
    # メールアドレスで探す。ダイアログがスクロールに合わせて読み足す。
    # tenant_users は RLS でも自分の他のテナントでの所属が見える（テナントの切り替えのため）ので、テナントで絞る
    def member_candidates
      page = [params[:page].to_i, 1].max
      users = TenantUser.where(tenant: current_tenant, status: [:active, :invited]).joins(:user).includes(:user)
      if params[:q].present?
        pattern = "%#{TenantUser.sanitize_sql_like(params[:q].strip)}%"
        users = users.where("tenant_users.display_name ILIKE :pattern OR users.email ILIKE :pattern", pattern:)
      end
      users = users.order(:display_name, :id)
        .offset((page - 1) * PER_PAGE).limit(PER_PAGE + 1).to_a
      @next_page = (page + 1 if users.size > PER_PAGE)
      @candidates = users.first(PER_PAGE)
      render partial: "member_candidates", layout: false
    end

    def new
      @group = Group.new(parent: Group.department.active.find_by(id: params[:parent_id]))
      @label_names = []
    end

    def create
      @group = Group.new(tenant: current_tenant, **params.expect(group: [:name, :parent_id]))
      @label_names = label_names_param

      if save_group
        redirect_to management_group_path(@group), notice: t("messages.created")
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      @members = members_of(@group)
      @label_names = @group.labels.order(:name).pluck(:name)
    end

    def update
      @group.assign_attributes(params.expect(group: [:name, :parent_id]))
      @label_names = label_names_param
      # 行を全部外すと members は送られてこない
      roles = params.fetch(:group, {}).permit(members: {}).fetch(:members, nil).to_h.to_h { |id, role| [id.to_i, role] }

      if save_group { @group.replace_members!(roles) }
        redirect_to management_group_path(@group), notice: t("messages.saved")
      else
        # 送られてきたとおりに出し直す
        users = TenantUser.includes(:user).where(tenant: current_tenant, id: roles.keys).index_by(&:id)
        @members = roles.filter_map { |id, role| users[id] && GroupMember.new(tenant_user: users[id], role:) }
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def load_tree
      @everyone = Group.everyone_of(current_tenant)
      @children = Group.department.active.order(:name).group_by(&:parent_id)
    end

    def set_group
      @group = Group.find(params[:id])
    end

    def reject_everyone
      raise ActiveRecord::RecordNotFound if @group.everyone?
    end

    def label_names_param
      params.dig(:group, :label_names).to_s.split(/[,、]/).map(&:strip).compact_blank.uniq
    end

    # ラベルの名前が長すぎるときなどは GroupLabel の検証で落ちるので、グループの誤りとして出す
    def save_group
      Group.transaction do
        @group.save!
        @group.replace_labels!(@label_names)
        yield if block_given?
        true
      rescue ActiveRecord::RecordInvalid => e
        e.record.errors.full_messages.each { @group.errors.add(:base, it) } unless e.record == @group
        raise ActiveRecord::Rollback
      end
    end

    # グループ管理者を先に、それぞれ表示名の順に並べる
    def members_of(group)
      group.group_members.includes(tenant_user: :user).to_a
        .sort_by { |member| [member.leader? ? 0 : 1, member.tenant_user.display_name, member.id] }
    end

    def sub_members_of(group)
      TenantUser.where(id: GroupMember.where(group_id: Group.descendant_ids_of(group.id)).select(:tenant_user_id))
    end
  end
end
