module Management
  class GroupsController < BaseController
    # 画面モック。実データは未実装で、以下はすべて仮の表示用
    MockGroup = Struct.new(:id, :name, :parent_id, :kind, keyword_init: true) do
      # パスのヘルパーに渡したとき、ActiveRecord と同じく id を URL に使わせる
      def to_param = id.to_s
    end
    MockMember = Struct.new(:display_name, :email, keyword_init: true)

    EVERYONE = MockGroup.new(id: 100, name: "全員", parent_id: nil, kind: :everyone)
    DEPARTMENTS = [
      MockGroup.new(id: 1, name: "全社", parent_id: nil, kind: :department),
      MockGroup.new(id: 2, name: "営業本部", parent_id: 1, kind: :department),
      MockGroup.new(id: 3, name: "第一営業部", parent_id: 2, kind: :department),
      MockGroup.new(id: 4, name: "第二営業部", parent_id: 2, kind: :department),
      MockGroup.new(id: 5, name: "開発本部", parent_id: 1, kind: :department),
      MockGroup.new(id: 6, name: "開発部", parent_id: 5, kind: :department),
    ].freeze

    yamada = MockMember.new(display_name: "山田 太郎", email: "yamada@example.com")
    sato = MockMember.new(display_name: "佐藤 花子", email: "sato@example.com")
    suzuki = MockMember.new(display_name: "鈴木 一郎", email: "suzuki@example.com")
    takahashi = MockMember.new(display_name: "高橋 次郎", email: "takahashi@example.com")
    tanaka = MockMember.new(display_name: "田中 三郎", email: "tanaka@example.com")
    ito = MockMember.new(display_name: "伊藤 美咲", email: "ito@example.com")
    watanabe = MockMember.new(display_name: "渡辺 健", email: "watanabe@example.com")
    MEMBERS = {
      1 => [yamada],
      2 => [yamada, sato],
      3 => [suzuki, takahashi, tanaka],
      4 => [ito, tanaka],
      6 => [watanabe],
    }.freeze
    TENANT_USERS_COUNT = 12

    before_action :load_tree

    def index
    end

    def show
      @group = ([EVERYONE] + DEPARTMENTS).find { |group| group.id == params[:id].to_i }
      raise ActiveRecord::RecordNotFound unless @group
      if @group.kind == :everyone
        @tenant_users_count = TENANT_USERS_COUNT
        return
      end

      @members = MEMBERS.fetch(@group.id, [])

      descendants = @children.fetch(@group.id, []).dup
      descendants.each { |group| descendants.concat(@children.fetch(group.id, [])) }

      # 同じ人が複数のサブグループにいれば1行にまとめる
      @sub_members = descendants
        .flat_map { |group| MEMBERS.fetch(group.id, []).map { |member| [member, group] } }
        .group_by(&:first)
        .map { |member, pairs| [member, pairs.map(&:last)] }
      @total_count = (@members + @sub_members.map(&:first)).uniq.size

      @parent_path = path_to(@group.parent_id)
      # 自分と自分の下位を上位にすると循環する
      @parent_options = parent_options(excluded: [@group.id] + descendants.map(&:id))
    end

    def new
      parent = DEPARTMENTS.find { |group| group.id == params[:parent_id].to_i }
      @parent_path = path_to(parent&.id)
      @parent_options = parent_options(excluded: [])
    end

    private

    def load_tree
      @everyone = EVERYONE
      @children = DEPARTMENTS.group_by(&:parent_id)
    end

    # 最上位から指定したグループまでの系列（指定したグループを含む）
    def path_to(group_id)
      path = []
      while group_id
        group = DEPARTMENTS.find { |department| department.id == group_id }
        path.unshift(group)
        group_id = group.parent_id
      end
      path
    end

    # 「全員」は親にしないので選択肢に入れない
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
