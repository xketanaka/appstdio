module Profiles
  class AvatarsController < ApplicationController
    # 画像と、画面で調整した切り抜く範囲（crop[x] / crop[y] / crop[size]）を受け取る
    def update
      @tenant_user = current_tenant_user
      file = params.expect(:avatar)
      raise ActionController::BadRequest unless file.respond_to?(:path)

      # 画面で範囲を調整できなかったとき（ブラウザで表示できない画像）は空で届くので、中央を切り抜く
      crop = params[:crop].try(:permit, :x, :y, :size).to_h.compact_blank.symbolize_keys.transform_values(&:to_i)
      if @tenant_user.replace_avatar(file.path, crop: (crop if crop.size == 3))
        redirect_to profile_path, notice: t(".done")
      else
        render "profiles/show", status: :unprocessable_entity
      end
    end

    def destroy
      current_tenant_user.avatar.purge
      redirect_to profile_path, notice: t(".done")
    end
  end
end
