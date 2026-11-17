module Management
  module GroupsHelper
    # 上位グループのダイアログの状態。
    # allow_top: 「最上位」を選べるか。グループ管理者は最上位に置けないが、もともと最上位のグループはそのままにできる
    # selected: 選ばれているグループ（nil は最上位）。最上位を選べないときに上位が無ければ、ツリーの先頭を選んでおく
    # outside: 範囲の外にある今の上位。グループ管理者のツリーは範囲の中だけなので、変えずに保存できるよう別に出す
    # open_ids: 初めから開いておくグループ。最上位のほかに、選ばれているグループとその上位を開く
    def group_parent_choice(group, children)
      allow_top = group_scope.all? || (group.persisted? && group.parent_id_was.nil?)
      selected = group.parent || (children.fetch(nil, []).first unless allow_top)
      chain = selected ? selected.self_and_ancestors : []
      current = Group.find_by(id: group.parent_id_was) if group.persisted?
      outside = current if current && children.values.flatten.none? { it.id == current.id }
      { allow_top:, selected:, outside:, path: chain.reverse.map(&:name), open_ids: chain.map(&:id) }
    end
  end
end
