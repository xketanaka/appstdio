module Files
  module Api
    class TrashController < BaseController
      # 削除した人・日時・サイズは、項目を閲覧できるかに関わらず返す（doc/files.md の「ゴミ箱」）
      def index
        entries = access.trash.sort_by(&:deleted_at).reverse
        ActiveRecord::Associations::Preloader.new(records: entries, associations: :deleted_by).call

        render json: {
          entries: entries.map do |node|
            {
              id: node.id,
              kind: node.kind,
              name: node.name,
              deleted_by: node.deleted_by&.display_name,
              deleted_at: node.deleted_at,
              byte_size: (node.byte_size if node.file?),
            }
          end,
        }
      end
    end
  end
end
