module Management
  module GroupsHelper
    # 上位グループの候補。有効な部署（ツリーの @children）を、ツリーの順に字下げして並べる。
    # 字下げは option の中で普通の空白が詰められるため NBSP にする。
    # グループ管理者のツリーは範囲の中だけなので、範囲の外にある今の上位は先頭に足す（変えずに保存できるように）
    def group_parent_options(group, children)
      excluded = group.persisted? ? [group.id, *Group.descendant_ids_of(group.id)] : []
      options = []
      walk = ->(parent_id, depth) do
        children.fetch(parent_id, []).each do |child|
          next if excluded.include?(child.id)

          options << ["  " * depth + child.name, child.id]
          walk.(child.id, depth + 1)
        end
      end
      walk.(nil, 0)
      current = group.persisted? ? Group.find_by(id: group.parent_id_was) : nil
      options.unshift([current.name, current.id]) if current && options.none? { it.last == current.id }
      options
    end
  end
end
