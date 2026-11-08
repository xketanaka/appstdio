require "vips"

# 利用者が送った画像から、アバターの画像（正方形の WebP）を作る。元の画像は残さない
module AvatarImage
  SIZE = 256
  MAX_BYTES = 10.megabytes
  # 小さなファイルでも、展開すると巨大になる画像がある。メモリを使い切らないよう画素数でも抑える
  MAX_PIXELS = 50_000_000
  CONTENT_TYPES = ["image/png", "image/jpeg", "image/gif", "image/webp"].freeze
  # 形式は送られた Content-Type でなく中身で判定する。libvips は SVG・PDF なども読めるので、CONTENT_TYPES の形式に絞る
  LOADERS = ["VipsForeignLoadPngFile", "VipsForeignLoadJpegFile", "VipsForeignLoadNsgifFile",
             "VipsForeignLoadWebpFile"].freeze

  # 作れないわけを、モデルの誤りのキー（:too_large など）として持つ
  class Invalid < StandardError
    def key = message.to_sym
  end

  # path の画像を crop（{ x:, y:, size: }。向きを直した後の画素）の正方形で切り抜き、SIZE 四方に縮めた
  # WebP のバイト列を返す。crop が無ければ中央を切り抜く。範囲が画像からはみ出していたら、内側に寄せる
  def self.process(path, crop: nil)
    raise Invalid, "too_large" if File.size(path) > MAX_BYTES
    raise Invalid, "invalid_format" unless LOADERS.include?(Vips.vips_foreign_find_load(path))

    image = Vips::Image.new_from_file(path)
    raise Invalid, "too_many_pixels" if image.width * image.height > MAX_PIXELS

    # 画面で調整した範囲は、ブラウザが EXIF の向きを直して表示した画像の上の座標
    image = image.autorot
    side = [image.width, image.height].min
    size = crop ? crop[:size].clamp(1, side) : side
    x = crop ? crop[:x].clamp(0, image.width - size) : (image.width - size) / 2
    y = crop ? crop[:y].clamp(0, image.height - size) : (image.height - size) / 2

    image.crop(x, y, size, size).colourspace(:srgb).thumbnail_image(SIZE, height: SIZE, size: :force)
      .write_to_buffer(".webp", Q: 85, keep: :none)
  rescue Vips::Error
    raise Invalid, "invalid_format"
  end
end
