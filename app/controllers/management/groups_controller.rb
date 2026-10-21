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
    # 下位グループのメンバーをスクロールで読み足す動きを試せるよう、人数を多めにしている
    developers = (1..70).map { |i| MockMember.new(display_name: "開発 メンバー#{i}", email: "dev#{i}@example.com") }
    MEMBERS = {
      1 => [yamada],
      2 => [yamada, sato],
      3 => [suzuki, takahashi, tanaka],
      4 => [ito, tanaka],
      6 => [watanabe] + developers,
    }.freeze
    LEADERS = {
      1 => ["yamada@example.com"],
      2 => ["sato@example.com"],
      3 => ["suzuki@example.com"],
      6 => ["watanabe@example.com"],
    }.freeze
    LABELS = {
      1 => ["本社"],
      2 => ["営業", "本部"],
      3 => ["営業", "東日本"],
      4 => ["営業", "西日本"],
      5 => ["開発", "本部"],
      6 => ["開発"],
    }.freeze
    # どのグループにも付いていないラベルも、テナントに登録されていれば候補に出る
    LABEL_NAMES = (LABELS.values.flatten + ["プロジェクト"]).uniq.freeze
    TENANT_USERS_COUNT = 12
    SUB_MEMBERS_PER_PAGE = 30

    before_action :load_tree
    before_action :set_group, only: [:show, :edit, :sub_members]

    def index
    end

    def show
      if @group.kind == :everyone
        @tenant_users_count = TENANT_USERS_COUNT
        return
      end

      @members = members_of(@group)
      @labels = LABELS.fetch(@group.id, [])
      @parent_path = path_to(@group.parent_id)
      @sub_members_count = sub_members_of(@group).size
    end

    # 下位グループのメンバーの一覧を1ページ分だけ返す。詳細の画面がスクロールに合わせて読み足す
    def sub_members
      raise ActiveRecord::RecordNotFound if @group.kind == :everyone

      page = [params[:page].to_i, 1].max
      members = sub_members_of(@group)
      @rows = members.drop((page - 1) * SUB_MEMBERS_PER_PAGE).first(SUB_MEMBERS_PER_PAGE)
      @next_page = (page + 1 if members.size > page * SUB_MEMBERS_PER_PAGE)
      render partial: "sub_member_rows", layout: false
    end

    def new
      parent = DEPARTMENTS.find { |group| group.id == params[:parent_id].to_i }
      @parent_path = path_to(parent&.id)
      @parent_options = parent_options(excluded: [])
      @labels = []
      @label_names = LABEL_NAMES
    end

    def edit
      raise ActiveRecord::RecordNotFound if @group.kind == :everyone

      @members = members_of(@group)
      @labels = LABELS.fetch(@group.id, [])
      @label_names = LABEL_NAMES
      @parent_path = path_to(@group.parent_id)
      # 自分と自分の下位を上位にすると循環する
      @parent_options = parent_options(excluded: [@group.id] + descendants_of(@group).map(&:id))
    end

    private

    def load_tree
      @everyone = EVERYONE
      @children = DEPARTMENTS.group_by(&:parent_id)
    end

    def set_group
      @group = ([EVERYONE] + DEPARTMENTS).find { |group| group.id == params[:id].to_i }
      raise ActiveRecord::RecordNotFound unless @group
    end

    # [メンバー, グループ管理者か] の組。グループ管理者を先に並べる
    def members_of(group)
      MEMBERS.fetch(group.id, [])
        .map { |member| [member, LEADERS.fetch(group.id, []).include?(member.email)] }
        .sort_by { |_, leader| leader ? 0 : 1 }
    end

    # 同じ人が複数の下位グループにいれば1行にまとめる
    def sub_members_of(group)
      descendants_of(group)
        .flat_map { |child| MEMBERS.fetch(child.id, []).map { |member| [member, child] } }
        .group_by(&:first)
        .map { |member, pairs| [member, pairs.map(&:last)] }
    end

    def descendants_of(group)
      descendants = @children.fetch(group.id, []).dup
      descendants.each { |child| descendants.concat(@children.fetch(child.id, [])) }
      descendants
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
