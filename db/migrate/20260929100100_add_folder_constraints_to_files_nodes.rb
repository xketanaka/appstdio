class AddFolderConstraintsToFilesNodes < ActiveRecord::Migration[8.1]
  # フォルダは版もサイズも持たない。一覧のサイズ表示（フォルダは "-"）が
  # この前提に依存している
  def change
    add_check_constraint :files_nodes, "kind = 'file' OR current_version_id IS NULL",
      name: "files_nodes_folder_version_check"
    add_check_constraint :files_nodes, "kind = 'file' OR byte_size = 0",
      name: "files_nodes_folder_size_check"
  end
end
