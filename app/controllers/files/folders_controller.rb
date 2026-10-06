module Files
  class FoldersController < BaseController
    def show
      @folder =
        if params[:id]
          Node.kept.folder.find(params[:id])
        elsif params[:drive] == "personal"
          Drive.personal_root(current_tenant_user)
        else
          Drive.shared_root(current_tenant)
        end
      role = access.role(@folder)
      raise ActiveRecord::RecordNotFound unless Access.at_least_viewer?(role)

      @can_edit = Access.at_least_editor?(role)

      @entries = @folder.children.kept.includes(:creator).order(:kind, :name).to_a
      @roles = access.roles(@entries)

      ancestors = @folder.ancestors.to_a
      readable = access.roles(ancestors)
      @breadcrumbs = ancestors.reverse.take_while { |node| readable.key?(node.id) }.reverse
      @via_shared = @breadcrumbs.size < ancestors.size

      @section =
        if @folder.drive.shared? then :shared_drive
        elsif @folder.drive.owner_id == current_tenant_user.id then :my_drive
        else :shared_with_me
        end
    end
  end
end
