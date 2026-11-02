class RemovePurgeAfterFromFilesNodes < ActiveRecord::Migration[8.1]
  def change
    remove_column :files_nodes, :purge_after, :datetime
  end
end
