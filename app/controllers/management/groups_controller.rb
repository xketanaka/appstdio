module Management
  class GroupsController < BaseController
    PER_PAGE = 30

    # テナントの管理者に加えて、グループ管理者も開ける（自分の範囲の中だけ）
    skip_before_action :tenant_admin_required
    before_action :group_manager_required
    before_action :load_tree
    before_action :set_group, except: [:index, :new, :create, :suspended]
    # 「全員」は名前もメンバーも変えられず、消せない
    before_action :reject_everyone, except: [:index, :new, :create, :suspended, :show]
    # 停止中は詳細を見て再開するだけ。編集・削除・停止はできない
    before_action :reject_suspended, except: [:index, :new, :create, :suspended, :show, :sub_members, :reactivate]
    before_action :destroyable_required, only: [:confirm_destroy, :destroy]

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
      @has_children = visible_descendant_ids(@group).any?
      @sub_members_count = sub_members_of(@group).count
      @reactivation_blocker = @group.reactivation_blocker if @group.suspended?
    end

    # 利用停止中のグループの一覧。既定は起点だけを出し、include_descendants で一緒に止まった下位も出す。
    # キーワードはグループ名と、停止した時点の上位の名前の並びに当てる
    def suspended
      @query = params[:q].to_s.strip
      @include_descendants = params[:include_descendants] == "1"
      page = [params[:page].to_i, 1].max

      groups = Group.suspended
      groups = groups.where(id: @scope.ids) unless @scope.all?
      if @query.present?
        groups = groups.where("groups.name ILIKE :pattern OR array_to_string(groups.suspended_path, ' ') ILIKE :pattern",
          pattern: "%#{Group.sanitize_sql_like(@query)}%")
      end
      unless @include_descendants
        roots = groups.where("groups.suspension_root_id = groups.id")
        # 起点には見つからず、一緒に止まった下位に当てはまるものがあれば、チェックを入れるよう誘う
        @hidden_count = groups.count if @query.present? && page == 1 && !roots.exists?
        groups = roots
      end

      # 同じ停止の操作で止まった行は、起点から上位の並びの短い順（ツリーの浅い順）に並べる
      @groups = groups.includes(:suspended_by, :suspension_root)
        .order(suspended_at: :desc, suspension_root_id: :desc)
        .order(Arel.sql("cardinality(groups.suspended_path)"), :name, :id)
        .offset((page - 1) * PER_PAGE).limit(PER_PAGE + 1).to_a
      @next_page = (page + 1 if @groups.size > PER_PAGE)
      @groups = @groups.first(PER_PAGE)
      root_ids = @groups.select { it.suspension_root_id == it.id }.map(&:id)
      @co_suspended_counts = Group.where(suspension_root_id: root_ids).where("groups.id <> groups.suspension_root_id")
        .group(:suspension_root_id).count

      render partial: "suspended_rows", layout: false if page > 1
    end

    # 下位グループのメンバーの一覧を1ページ分だけ返す。詳細の画面がスクロールに合わせて読み足す
    def sub_members
      page = [params[:page].to_i, 1].max
      users = sub_members_of(@group).includes(:user).order(:display_name, :id)
        .offset((page - 1) * PER_PAGE).limit(PER_PAGE + 1).to_a
      @next_page = (page + 1 if users.size > PER_PAGE)
      users = users.first(PER_PAGE)
      groups = GroupMember.where(group_id: visible_descendant_ids(@group), tenant_user_id: users.map(&:id))
        .includes(:group).group_by(&:tenant_user_id)
      # 同じ人が複数の下位グループにいれば1行にまとめ、所属する下位グループを並べる
      @rows = users.map { |user| [user, groups.fetch(user.id).map(&:group).sort_by(&:name)] }
      render partial: "sub_member_rows", layout: false
    end

    # メンバーの追加のダイアログの候補。テナントの所属のうち有効・招待中の人を、表示名か
    # メールアドレスで探す。ダイアログがスクロールに合わせて読み足す
    def member_candidates
      page = [params[:page].to_i, 1].max
      users = TenantUser.where(status: [:active, :invited]).joins(:user).includes(:user)
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
      raise ActiveRecord::RecordNotFound unless @scope.can_place_under?(@group.parent)

      @label_names = []
    end

    def create
      @group = Group.new(tenant: current_tenant, **params.expect(group: [:name, :parent_id]))
      @label_names = label_names_param

      if save_group
        # 作ったら続けて人を入れる
        redirect_to edit_members_management_group_path(@group), notice: t("messages.created")
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      @label_names = @group.labels.order(:name).pluck(:name)
    end

    def update
      @group.assign_attributes(params.expect(group: [:name, :parent_id]))
      @label_names = label_names_param

      if save_group
        redirect_to management_group_path(@group), notice: t("messages.saved")
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def edit_members
      @members = members_of(@group)
    end

    # 足す・削除・グループ管理者の切り替えを、まとめて保存する
    def update_members
      # 行を全部削除すると members は送られてこない
      roles = params.fetch(:group, {}).permit(members: {}).fetch(:members, nil).to_h.to_h { |id, role| [id.to_i, role] }

      saved = Group.transaction do
        @group.replace_members!(roles)
        true
      rescue ActiveRecord::RecordInvalid => e
        e.record.errors.full_messages.each { @group.errors.add(:base, it) }
        raise ActiveRecord::Rollback
      end

      if saved
        # 自分のグループ管理者の印を外すと、範囲の外になって詳細（どこも管理していなければグループ管理も）を開けなくなる
        scope = GroupScope.new(current_tenant_user)
        destination =
          if scope.include?(@group) then management_group_path(@group)
          elsif scope.any? then management_groups_path
          else top_page_path
          end
        redirect_to destination, notice: t("messages.saved")
      else
        # 送られてきたとおりに出し直す
        users = TenantUser.includes(:user).where(id: roles.keys).index_by(&:id)
        @members = roles.filter_map { |id, role| users[id] && GroupMember.new(tenant_user: users[id], role:) }
        render :edit_members, status: :unprocessable_entity
      end
    end

    # 削除の確認。一緒に消える下位の数を示す
    def confirm_destroy
      @descendants_count = Group.descendant_ids_of(@group.id).size
    end

    def confirm_suspend
      @descendants_count = Group.active.where(id: Group.descendant_ids_of(@group.id)).count
    end

    def suspend
      @group.suspend!(by: current_tenant_user)
      redirect_to management_group_path(@group), notice: t(".done")
    end

    def reactivate
      raise ActiveRecord::RecordNotFound unless @group.suspended?

      if @group.reactivate
        redirect_to management_group_path(@group), notice: t(".done")
      else
        redirect_to management_group_path(@group)
      end
    end

    # 下位（停止中も）は children の dependent: :destroy でたどって消す。ファイルの共有設定は外部キーの
    # ON DELETE CASCADE で消える
    def destroy
      @group.destroy!
      redirect_to (@group.parent ? management_group_path(@group.parent) : management_groups_path),
        notice: t("messages.deleted")
    end

    private

    def group_manager_required
      @scope = GroupScope.new(current_tenant_user)
      render_not_found unless @scope.any?
    end

    # グループ管理者には範囲の中だけを出し、範囲のいちばん上のグループを根として描く。「全員」も出さない
    def load_tree
      groups = Group.department.active.order(:name).to_a
      if @scope.all?
        @everyone = Group.everyone_of(current_tenant)
        @children = groups.group_by(&:parent_id)
      else
        @children = groups.select { @scope.include?(it) }
          .group_by { @scope.ids.include?(it.parent_id) ? it.parent_id : nil }
      end
    end

    def set_group
      @group = Group.find(params[:id])
      raise ActiveRecord::RecordNotFound unless @scope.include?(@group)
    end

    def reject_everyone
      raise ActiveRecord::RecordNotFound if @group.everyone?
    end

    def reject_suspended
      raise ActiveRecord::RecordNotFound if @group.suspended?
    end

    def destroyable_required
      raise ActiveRecord::RecordNotFound unless @scope.can_destroy?(@group)
    end

    def label_names_param
      params.dig(:group, :label_names).to_s.split(/[,、]/).map(&:strip).compact_blank.uniq
    end

    # ラベルの名前が長すぎるときなどは GroupLabel の検証で落ちるので、グループの誤りとして出す
    def save_group
      # グループ管理者は、範囲の外へ移したり最上位に置いたりできない
      if (@group.new_record? || @group.parent_id_changed?) && !@scope.can_place_under?(@group.parent)
        raise ActiveRecord::RecordNotFound
      end

      Group.transaction do
        @group.save!
        @group.replace_labels!(@label_names)
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
      TenantUser.where(id: GroupMember.where(group_id: visible_descendant_ids(group)).select(:tenant_user_id))
    end

    # 詳細に出す下位。停止中の下位のメンバーは上位のメンバーとして数えない（ファイルの権限も届かない）ので、
    # 有効なグループでは有効な下位だけ。停止中のグループを見るときは、一緒に止まった下位も含めて停止した時の形で出す
    def visible_descendant_ids(group)
      ids = Group.descendant_ids_of(group.id)
      group.suspended? ? ids : Group.active.where(id: ids).ids
    end
  end
end
