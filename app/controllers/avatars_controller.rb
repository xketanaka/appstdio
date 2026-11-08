# アバターの画像。見られるのは同じテナントの人だけ（tenant_users の RLS で、他のテナントの所属は見つからない）。
# Active Storage の公開ルートは誰でも見られるので使わない（doc/database.md の「テナント分離」）
class AvatarsController < ApplicationController
  def show
    attachment = TenantUser.find(params[:id]).avatar_attachment
    raise ActiveRecord::RecordNotFound unless attachment && attachment.blob_id.to_s == params[:version]

    expires_in 1.year, public: false, immutable: true
    send_data attachment.blob.download, type: attachment.blob.content_type, disposition: :inline
  end
end
