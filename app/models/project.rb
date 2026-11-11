# プロジェクト。グループ（kind: project）と1対1で、名前・ラベル・メンバー・利用停止はグループのものを使う。
# プロジェクトにだけある項目が増えたら、この表に持たせる（doc/projects.md）
class Project < ApplicationRecord
  belongs_to :tenant
  belongs_to :group

  delegate :name, :labels, :suspended?, :suspended_at, :suspended_by, to: :group

  scope :active, -> { joins(:group).merge(Group.active) }
  scope :suspended, -> { joins(:group).merge(Group.suspended) }

  # 新しいプロジェクト。グループは「プロジェクト」の下に置く（無ければ作る）
  def self.build(tenant:)
    new(tenant:, group: Group.new(tenant:, kind: :project, parent: Group.project_root_of!(tenant)))
  end

  # 名前とラベルをグループに保存する。作るときはプロジェクトの行も作る。保存できなければ false で、
  # グループの誤りをプロジェクトの誤りとして持たせる（名前の訳を「プロジェクト名」にするため）
  def save_with(name:, label_names:)
    group.name = name
    transaction do
      unless group.save_with_labels(label_names)
        group.errors.each { it.attribute == :name ? errors.add(:name, it.type, **it.options) : errors.add(:base, it.message) }
        raise ActiveRecord::Rollback
      end
      save!
      true
    end
  end

  # 利用停止・再開はグループに対して行う（グループ管理からはできない）
  def suspend!(by:)
    group.suspend!(by:)
  end

  def reactivation_blocker
    group.reactivation_blocker
  end

  def reactivate
    group.reactivate
  end

  # グループを消す。プロジェクトの行は外部キーの ON DELETE CASCADE で消える。ファイルの共有設定も同じ
  def destroy_with_group!
    group.destroy!
  end
end
