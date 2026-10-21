class DeriveFilesNodesDriveIdFromParent < ActiveRecord::Migration[8.1]
  # ドライブをまたいで移動したとき、配下まで drive_id を付け替える。親から写すだけで、配下へは
  # 既存の files_nodes_cascade_ancestor_ids が ancestor_ids の変化に乗せて伝える
  # （別のドライブの根の下へ移れば ancestor_ids は必ず変わる）
  def up
    execute <<~SQL
      CREATE OR REPLACE FUNCTION files_nodes_set_ancestor_ids() RETURNS trigger
      LANGUAGE plpgsql AS $$
      BEGIN
        IF NEW.parent_id IS NULL THEN
          NEW.ancestor_ids := '{}';
        ELSE
          SELECT ancestor_ids || id, drive_id INTO NEW.ancestor_ids, NEW.drive_id
          FROM files_nodes WHERE id = NEW.parent_id;
          IF NEW.id = ANY(NEW.ancestor_ids) THEN
            RAISE EXCEPTION 'files_nodes % cannot be moved under itself', NEW.id
              USING ERRCODE = 'check_violation';
          END IF;
        END IF;
        RETURN NEW;
      END;
      $$;
    SQL
  end

  def down
    execute <<~SQL
      CREATE OR REPLACE FUNCTION files_nodes_set_ancestor_ids() RETURNS trigger
      LANGUAGE plpgsql AS $$
      BEGIN
        IF NEW.parent_id IS NULL THEN
          NEW.ancestor_ids := '{}';
        ELSE
          SELECT ancestor_ids || id INTO NEW.ancestor_ids FROM files_nodes WHERE id = NEW.parent_id;
          IF NEW.id = ANY(NEW.ancestor_ids) THEN
            RAISE EXCEPTION 'files_nodes % cannot be moved under itself', NEW.id
              USING ERRCODE = 'check_violation';
          END IF;
        END IF;
        RETURN NEW;
      END;
      $$;
    SQL
  end
end
