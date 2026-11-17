class AddGroupDrivesToFilesDrives < ActiveRecord::Migration[8.1]
  def up
    # グループを消してもドライブの行は残す（中身は完全削除して、論理削除の行として残すため）
    add_reference :files_drives, :group, foreign_key: { on_delete: :nullify }, index: false
    add_column :files_drives, :disabled_at, :datetime
    add_index :files_drives, :group_id, unique: true, where: "group_id IS NOT NULL"

    execute <<~SQL
      ALTER TABLE files_drives DROP CONSTRAINT files_drives_kind_check;
      ALTER TABLE files_drives ADD CONSTRAINT files_drives_kind_check CHECK (
        (kind = 'shared' AND owner_id IS NULL AND group_id IS NULL AND disabled_at IS NULL)
        OR (kind = 'personal' AND owner_id IS NOT NULL AND group_id IS NULL AND disabled_at IS NULL)
        OR (kind = 'group' AND owner_id IS NULL)
      );
    SQL
  end

  def down
    execute <<~SQL
      DELETE FROM files_drives WHERE kind = 'group';
      ALTER TABLE files_drives DROP CONSTRAINT files_drives_kind_check;
      ALTER TABLE files_drives ADD CONSTRAINT files_drives_kind_check CHECK (
        (kind = 'shared' AND owner_id IS NULL) OR (kind = 'personal' AND owner_id IS NOT NULL)
      );
    SQL
    remove_index :files_drives, :group_id
    remove_column :files_drives, :disabled_at
    remove_reference :files_drives, :group, foreign_key: true, index: false
  end
end
