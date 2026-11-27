# 利用者がプロジェクトを最後に開いた日時。帯の「プロジェクト」のメニューに、最近開いたものを出すために持つ
class ProjectVisit < ApplicationRecord
  RECENT_LIMIT = 5

  belongs_to :tenant
  belongs_to :tenant_user
  belongs_to :project

  def self.record!(tenant_user:, project:)
    upsert(
      { tenant_id: project.tenant_id, tenant_user_id: tenant_user.id, project_id: project.id, visited_at: Time.current },
      unique_by: [:tenant_user_id, :project_id],
    )
  end

  # 最近開いた順の、今も参加している有効なプロジェクト
  def self.recent_projects(tenant_user)
    Project.joined_by(tenant_user).includes(:group)
      .joins(:visits).merge(where(tenant_user:))
      .order(visited_at: :desc).limit(RECENT_LIMIT)
  end
end
