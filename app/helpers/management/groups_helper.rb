module Management
  module GroupsHelper
    # 上位グループの候補。有効な部署（ツリーの @children）を、ツリーの順に字下げして並べる。
    # 字下げは option の中で普通の空白が詰められるため NBSP にする
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
      options
    end
  end
end
