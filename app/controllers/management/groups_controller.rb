module Management
  class GroupsController < BaseController
    # 画面モック。実データは未実装で、以下はすべて仮の表示用
    MockGroup = Struct.new(:id, :name, :parent_id, keyword_init: true)
    MockMember = Struct.new(:display_name, :email, keyword_init: true)

    GROUPS = [
      MockGroup.new(id: 1, name: "全社", parent_id: nil),
      MockGroup.new(id: 2, name: "営業本部", parent_id: 1),
      MockGroup.new(id: 3, name: "第一営業部", parent_id: 2),
      MockGroup.new(id: 4, name: "第二営業部", parent_id: 2),
      MockGroup.new(id: 5, name: "開発本部", parent_id: 1),
      MockGroup.new(id: 6, name: "開発部", parent_id: 5),
    ].freeze

    MEMBERS = {
      2 => [
        MockMember.new(display_name: "山田 太郎", email: "yamada@example.com"),
        MockMember.new(display_name: "佐藤 花子", email: "sato@example.com"),
      ],
      3 => [
        MockMember.new(display_name: "鈴木 一郎", email: "suzuki@example.com"),
        MockMember.new(display_name: "高橋 次郎", email: "takahashi@example.com"),
        MockMember.new(display_name: "田中 三郎", email: "tanaka@example.com"),
      ],
    }.freeze

    before_action :load_tree

    def index
    end

    def show
      @group = GROUPS.find { |group| group.id == params[:id].to_i }
      raise ActiveRecord::RecordNotFound unless @group

      @members = MEMBERS.fetch(@group.id, [])

      # 自分と自分の下位は上位部門に選べない
      excluded = [@group.id]
      excluded.each { |id| excluded.concat(@children.fetch(id, []).map(&:id)) }
      @parent_options = []
      walk = ->(parent_id, depth) do
        @children.fetch(parent_id, []).each do |group|
          next if excluded.include?(group.id)

          @parent_options << ["  " * depth + group.name, group.id]
          walk.(group.id, depth + 1)
        end
      end
      walk.(nil, 0)
    end

    private

    def load_tree
      @children = GROUPS.group_by(&:parent_id)
    end
  end
end
