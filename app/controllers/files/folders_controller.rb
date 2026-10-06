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
      permission = access.effective_permission(@folder)
      raise ActiveRecord::RecordNotFound unless permission.readable?

      @can_edit = permission.editable?

      @entries = @folder.children.kept.includes(:creator).order(:kind, :name).to_a
      @permissions = access.effective_permissions(@entries)

      ancestors = @folder.ancestors.to_a
      ancestor_permissions = access.effective_permissions(ancestors)
      @breadcrumbs = ancestors.reverse.take_while { |node| ancestor_permissions[node].readable? }.reverse
      @via_shared = @breadcrumbs.size < ancestors.size

      @section =
        if @folder.drive.shared? then :shared_drive
        elsif @folder.drive.owner_id == current_tenant_user.id then :my_drive
        else :shared_with_me
        end
    end
  end
end
