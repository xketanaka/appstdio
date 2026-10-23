module Management
  class GroupsController < BaseController
    SUB_MEMBERS_PER_PAGE = 30

    before_action :load_tree
    before_action :set_group, only: [:show, :edit, :sub_members]

    def index
    end

    def show
      if @group.everyone?
        @tenant_users_count = TenantUser.active.count
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
      raise ActiveRecord::RecordNotFound if @group.everyone?

      page = [params[:page].to_i, 1].max
      users = sub_members_of(@group).includes(:user).order(:display_name, :id)
        .offset((page - 1) * SUB_MEMBERS_PER_PAGE).limit(SUB_MEMBERS_PER_PAGE + 1).to_a
      @next_page = (page + 1 if users.size > SUB_MEMBERS_PER_PAGE)
      users = users.first(SUB_MEMBERS_PER_PAGE)
      groups = GroupMember.where(group_id: Group.descendant_ids_of(@group.id), tenant_user_id: users.map(&:id))
        .includes(:group).group_by(&:tenant_user_id)
      # 同じ人が複数の下位グループにいれば1行にまとめ、所属する下位グループを並べる
      @rows = users.map { |user| [user, groups.fetch(user.id).map(&:group).sort_by(&:name)] }
      render partial: "sub_member_rows", layout: false
    end

    def new
      parent = Group.department.active.find_by(id: params[:parent_id])
      @parent_path = parent ? parent.self_and_ancestors.reverse : []
      @parent_options = parent_options(excluded: [])
      @labels = []
      @label_names = GroupLabel.order(:name).pluck(:name)
    end

    def edit
      raise ActiveRecord::RecordNotFound if @group.everyone?

      @members = members_of(@group)
      @labels = @group.labels.order(:name).pluck(:name)
      @label_names = GroupLabel.order(:name).pluck(:name)
      @parent_path = @group.self_and_ancestors.drop(1).reverse
      # 自分と自分の下位を上位にすると循環する
      @parent_options = parent_options(excluded: [@group.id, *Group.descendant_ids_of(@group.id)])
    end

    private

    def load_tree
      @everyone = Group.everyone_of(current_tenant)
      @children = Group.department.active.order(:name).group_by(&:parent_id)
    end

    def set_group
      @group = Group.find(params[:id])
    end

    # グループ管理者を先に、それぞれ表示名の順に並べる
    def members_of(group)
      group.group_members.includes(tenant_user: :user).to_a
        .sort_by { |member| [member.leader? ? 0 : 1, member.tenant_user.display_name, member.id] }
    end

    def sub_members_of(group)
      TenantUser.where(id: GroupMember.where(group_id: Group.descendant_ids_of(group.id)).select(:tenant_user_id))
    end

    # 有効な部署を、ツリーの順に字下げして並べる。「全員」と停止中は上位に選べない
    def parent_options(excluded:)
      options = []
      walk = ->(parent_id, depth) do
        @children.fetch(parent_id, []).each do |group|
          next if excluded.include?(group.id)

          options << ["\u00A0\u00A0" * depth + group.name, group.id]
          walk.(group.id, depth + 1)
        end
      end
      walk.(nil, 0)
      options
    end
  end
end
