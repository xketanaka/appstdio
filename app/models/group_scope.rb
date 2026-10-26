# グループ管理で、ある利用者が扱えるグループの範囲。テナントの管理者はすべて。グループ管理者は
# 自分が管理者のグループとその下位（停止中も含む）。範囲の外のグループは、見ることもできない
class GroupScope
  def initialize(tenant_user)
    @tenant_user = tenant_user
  end

  def all?
    @tenant_user.admin_or_owner?
  end

  def any?
    all? || led_ids.any?
  end

  def include?(group)
    all? || ids.include?(group.id)
  end

  def ids
    @ids ||= led_ids | Group.descendant_ids_of(led_ids)
  end

  def led_ids
    @led_ids ||= GroupMember.leader.where(tenant_user: @tenant_user).pluck(:group_id)
  end

  # 自分が管理者であるグループそのものは、テナントの管理者にしか消せない（戻せないので）
  def can_destroy?(group)
    include?(group) && (all? || led_ids.exclude?(group.id))
  end

  # 上位に置けるか。最上位（parent が nil）に置けるのはテナントの管理者だけ
  def can_place_under?(parent)
    parent.nil? ? all? : include?(parent)
  end
end
