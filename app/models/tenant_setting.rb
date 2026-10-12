class TenantSetting < ApplicationRecord
  # SVG はスクリプトを埋め込めるので受け付けない
  LOGO_CONTENT_TYPES = ["image/png", "image/jpeg", "image/gif", "image/webp"].freeze
  LOGO_MAX_BYTES = 1.megabyte
  # 未設定のときのヘッダーの背景（bg-white）と同じ色。カラーピッカーの初期値にも使う
  DEFAULT_TITLE_COLOR = "#ffffff"

  belongs_to :tenant
  has_one_attached :logo

  normalizes :title_label, with: ->(label) { label.strip.presence }
  normalizes :title_color, with: ->(color) { color.strip.downcase.presence }

  validates :tenant_id, uniqueness: true
  validates :title_label, length: { maximum: 255 }
  validates :title_color, format: { with: /\A#[0-9a-f]{6}\z/ }, allow_nil: true
  validate :logo_must_be_small_image

  # 背景が明るく、白い文字では読めないか。WCAG のコントラスト比で白と黒を比べる
  def light_title_color?
    channels = (title_color || DEFAULT_TITLE_COLOR).delete_prefix("#").scan(/../).map do |hex|
      value = hex.to_i(16) / 255.0
      value <= 0.03928 ? value / 12.92 : ((value + 0.055) / 1.055)**2.4
    end
    luminance = 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
    (luminance + 0.05) / 0.05 > 1.05 / (luminance + 0.05)
  end

  private

  def logo_must_be_small_image
    return unless logo.attached?

    errors.add(:logo, :invalid_content_type) unless LOGO_CONTENT_TYPES.include?(logo.blob.content_type)
    errors.add(:logo, :too_large, count: LOGO_MAX_BYTES / 1.megabyte) if logo.blob.byte_size > LOGO_MAX_BYTES
  end
end
