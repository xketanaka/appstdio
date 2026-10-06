class AddAncestorIdsToFilesNodes < ActiveRecord::Migration[8.1]
  def up
    add_column :files_nodes, :ancestor_ids, :bigint, array: true, null: false, default: []

    execute <<~SQL
      WITH RECURSIVE paths AS (
        SELECT id, ARRAY[]::bigint[] AS ancestor_ids FROM files_nodes WHERE parent_id IS NULL
        UNION ALL
        SELECT n.id, p.ancestor_ids || n.parent_id
        FROM files_nodes n JOIN paths p ON n.parent_id = p.id
      )
      UPDATE files_nodes SET ancestor_ids = paths.ancestor_ids
      FROM paths WHERE files_nodes.id = paths.id;

      CREATE FUNCTION files_nodes_set_ancestor_ids() RETURNS trigger
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

      CREATE FUNCTION files_nodes_cascade_ancestor_ids() RETURNS trigger
      LANGUAGE plpgsql AS $$
      BEGIN
        UPDATE files_nodes SET ancestor_ids = '{}' WHERE parent_id = NEW.id;
        RETURN NULL;
      END;
      $$;

      CREATE TRIGGER files_nodes_set_ancestor_ids
        BEFORE INSERT OR UPDATE OF parent_id, ancestor_ids ON files_nodes
        FOR EACH ROW EXECUTE FUNCTION files_nodes_set_ancestor_ids();

      CREATE TRIGGER files_nodes_cascade_ancestor_ids
        AFTER UPDATE OF parent_id, ancestor_ids ON files_nodes
        FOR EACH ROW WHEN (OLD.ancestor_ids IS DISTINCT FROM NEW.ancestor_ids)
        EXECUTE FUNCTION files_nodes_cascade_ancestor_ids();
    SQL
  end

  def down
    execute <<~SQL
      DROP TRIGGER files_nodes_cascade_ancestor_ids ON files_nodes;
      DROP TRIGGER files_nodes_set_ancestor_ids ON files_nodes;
      DROP FUNCTION files_nodes_cascade_ancestor_ids();
      DROP FUNCTION files_nodes_set_ancestor_ids();
    SQL
    remove_column :files_nodes, :ancestor_ids
  end
end
