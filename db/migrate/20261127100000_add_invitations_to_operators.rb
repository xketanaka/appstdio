class AddInvitationsToOperators < ActiveRecord::Migration[8.1]
  def up
    remove_check_constraint :operators, name: "operators_status_check"
    add_check_constraint :operators, "status IN ('invited', 'active', 'suspended')", name: "operators_status_check"
    add_column :operators, :invitation_sent_at, :datetime
  end

  def down
    remove_column :operators, :invitation_sent_at
    remove_check_constraint :operators, name: "operators_status_check"
    add_check_constraint :operators, "status IN ('active', 'suspended')", name: "operators_status_check"
  end
end
