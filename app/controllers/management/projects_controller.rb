module Management
  # プロジェクト管理。プロジェクトの名前・ラベル・メンバー・利用停止・削除を扱う（doc/projects.md）。
  # 中身はグループ（kind: project）なので、ラベルとメンバーの保存はグループのものを使う
  class ProjectsController < BaseController
    PER_PAGE = 30

    before_action :projects_enabled_required
    before_action :set_project, except: [:index, :suspended, :new, :create]
    before_action :project_root_required, only: [:new, :create]
    # 停止中は詳細を見て再開するだけ。編集・削除・停止はできない（グループと同じ。消したいときは再開してから）
    before_action :reject_suspended, except: [:index, :suspended, :new, :create, :show, :reactivate]

    def index
      @projects = Project.active.includes(group: :labels).order("groups.name", "groups.id").to_a
      group_ids = @projects.map(&:group_id)
      @member_counts = GroupMember.without_suspended_users.where(group_id: group_ids).group(:group_id).count
      @leaders = GroupMember.leader.without_suspended_users.where(group_id: group_ids).includes(:tenant_user)
        .group_by(&:group_id).transform_values { |members| members.map { it.tenant_user.display_name }.sort }
    end

    # 利用停止中のプロジェクトの一覧。新しく止めた順に30件ずつ出し、下までスクロールすると読み足す
    def suspended
      @query = params[:q].to_s.strip
      page = [params[:page].to_i, 1].max

      projects = Project.suspended.includes(group: :suspended_by)
      projects = projects.where("groups.name ILIKE ?", "%#{Group.sanitize_sql_like(@query)}%") if @query.present?
      projects = projects.order("groups.suspended_at DESC", id: :desc).offset((page - 1) * PER_PAGE).limit(PER_PAGE + 1).to_a
      @next_page = (page + 1 if projects.size > PER_PAGE)
      @projects = projects.first(PER_PAGE)

      render partial: "suspended_rows", layout: false if page > 1
    end

    def show
      @labels = @project.labels.order(:name).pluck(:name)
      @members = members_of(@project)
      @reactivation_blocker = @project.reactivation_blocker if @project.suspended?
    end

    def new
      @project = Project.build(tenant: current_tenant)
      @label_names = []
    end

    def create
      @project = Project.build(tenant: current_tenant)
      @label_names = label_names_param

      if @project.save_with(name: params.dig(:project, :name).to_s, label_names: @label_names)
        # 作ったら続けて人を入れる（グループと同じ）
        redirect_to edit_members_management_project_path(@project), notice: t("messages.created")
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      @label_names = @project.labels.order(:name).pluck(:name)
    end

    def update
      @label_names = label_names_param

      if @project.save_with(name: params.dig(:project, :name).to_s, label_names: @label_names)
        redirect_to management_project_path(@project), notice: t("messages.saved")
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def edit_members
      @members = members_of(@project)
    end

    def update_members
      # 行を全部削除すると members は送られてこない
      roles = params.fetch(:group, {}).permit(members: {}).fetch(:members, nil).to_h.to_h { |id, role| [id.to_i, role] }

      if @project.group.replace_members(roles)
        redirect_to management_project_path(@project), notice: t("messages.saved")
      else
        users = TenantUser.includes(:user, :avatar_attachment).where(id: roles.keys).index_by(&:id)
        @members = roles.filter_map { |id, role| users[id] && GroupMember.new(tenant_user: users[id], role:) }
        render :edit_members, status: :unprocessable_entity
      end
    end

    def confirm_suspend
    end

    def suspend
      @project.suspend!(by: current_tenant_user)
      redirect_to management_project_path(@project), notice: t(".done")
    end

    def reactivate
      raise ActiveRecord::RecordNotFound unless @project.suspended?

      if @project.reactivate
        redirect_to management_project_path(@project), notice: t(".done")
      else
        redirect_to management_project_path(@project)
      end
    end

    def confirm_destroy
    end

    def destroy
      @project.destroy_with_group!
      redirect_to management_projects_path, notice: t("messages.deleted")
    end

    private

    def projects_enabled_required
      render_not_found unless current_tenant.setting.projects_enabled?
    end

    # 最上位の「プロジェクト」グループは、プロジェクト機能を利用するにしたときに作る。作れなかった（同じ名前の
    # 最上位の部署があった）ときは、ここで作り直しを試み、だめなら案内する
    def project_root_required
      Group.project_root_of!(current_tenant)
    rescue ActiveRecord::RecordInvalid
      redirect_to management_projects_path, alert: t("management.projects.root_name_taken", name: t("groups.project_root"))
    end

    def set_project
      @project = Project.includes(:group).find(params[:id])
    end

    def reject_suspended
      raise ActiveRecord::RecordNotFound if @project.suspended?
    end

    def label_names_param
      params.dig(:project, :label_names).to_s.split(/[,、]/).map(&:strip).compact_blank.uniq
    end

    # プロジェクトの管理者（グループ管理者）を先に、それぞれ表示名の順に並べる。利用停止中の人は出さない
    def members_of(project)
      project.group.group_members.without_suspended_users.includes(tenant_user: [:user, :avatar_attachment]).to_a
        .sort_by { |member| [member.leader? ? 0 : 1, member.tenant_user.display_name, member.id] }
    end
  end
end
