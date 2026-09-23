class ProfilesController < ApplicationController
  def show
    @tenant_user = current_tenant_user
  end

  def update
    @tenant_user = current_tenant_user

    if @tenant_user.update(params.expect(tenant_user: [:display_name]))
      redirect_to profile_path, notice: t("messages.updated")
    else
      render :show, status: :unprocessable_entity
    end
  end
end
