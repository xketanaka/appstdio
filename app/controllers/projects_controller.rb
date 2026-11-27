# 利用者のプロジェクトの画面（doc/projects.md の「プロジェクトの画面」）。開けるのは、参加している
# 有効なプロジェクトだけ。テナントの管理者・オーナーでも、参加していなければ開けない
class ProjectsController < ApplicationController
  before_action :projects_enabled_required

  def index
    @projects = Project.joined_by(current_tenant_user).includes(group: :labels).order("groups.name", "groups.id").to_a
    @member_counts = Project.member_counts(@projects)
    @leaders = Project.leader_names(@projects)
  end

  def show
    @project = Project.joined_by(current_tenant_user).includes(:group).find(params[:id])
    ProjectVisit.record!(tenant_user: current_tenant_user, project: @project)
    @recent_projects = ProjectVisit.recent_projects(current_tenant_user).to_a
    @labels = @project.labels.order(:name).pluck(:name)
    @members = @project.listed_members
    render layout: "project"
  end

  private

  def projects_enabled_required
    raise ActiveRecord::RecordNotFound unless current_tenant.setting.projects_enabled?
  end
end
