module Files
  module Api
    class TrashController < BaseController
      # 削除した人・日時・サイズは、項目を閲覧できるかに関わらず返す（doc/files.md の「ゴミ箱」）
      def index
        entries = access.trash.sort_by(&:deleted_at).reverse
        ActiveRecord::Associations::Preloader.new(records: entries, associations: :deleted_by).call

        render json: { entries: entries.map { trash_entry_json(it) } }
      end
    end
  end
end
