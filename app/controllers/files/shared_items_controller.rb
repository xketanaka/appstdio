module Files
  class SharedItemsController < BaseController
    def index
      @entries = access.shared_items.sort_by { |node| [node.folder? ? 0 : 1, node.name] }
      @roles = access.roles(@entries)
      ActiveRecord::Associations::Preloader.new(records: @entries, associations: :creator).call
      @section = :shared_with_me
    end
  end
end
