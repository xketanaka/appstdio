module Files
  class TrashController < BaseController
    def index
      @entries = access.trash.sort_by(&:deleted_at).reverse
      ActiveRecord::Associations::Preloader.new(records: @entries, associations: :deleted_by).call
      @section = :trash
    end
  end
end
