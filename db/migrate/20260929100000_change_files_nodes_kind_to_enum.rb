class ChangeFilesNodesKindToEnum < ActiveRecord::Migration[8.1]
  def up
    create_enum :files_node_kind, %w[folder file]

    remove_check_constraint :files_nodes, name: "files_nodes_kind_check"
    execute <<~SQL
      ALTER TABLE files_nodes
        ALTER COLUMN kind TYPE files_node_kind USING kind::files_node_kind;
    SQL
  end

  def down
    execute <<~SQL
      ALTER TABLE files_nodes
        ALTER COLUMN kind TYPE character varying USING kind::text;
    SQL
    add_check_constraint :files_nodes, "kind IN ('folder', 'file')", name: "files_nodes_kind_check"

    drop_enum :files_node_kind
  end
end
