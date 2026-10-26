class GroupLabeling < ApplicationRecord
  belongs_to :tenant
  belongs_to :group
  belongs_to :group_label

  validates :group_label_id, uniqueness: { scope: :group_id }
end
