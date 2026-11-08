require "test_helper"

class AvatarImageTest < ActiveSupport::TestCase
  setup do
    @dir = Dir.mktmpdir
  end

  teardown do
    FileUtils.remove_entry(@dir)
  end

  # 左半分が黒、右半分が白の画像
  def write_image(name, width: 400, height: 200, orientation: nil)
    image = Vips::Image.black(width / 2, height).join(Vips::Image.black(width / 2, height) + 255, :horizontal)
    image = image.copy.tap { it.set_type(GObject::GINT_TYPE, "orientation", orientation) } if orientation
    File.join(@dir, name).tap { image.write_to_file(it) }
  end

  def result(data)
    Vips::Image.new_from_buffer(data, "")
  end

  test "中央を正方形に切り抜き、決まった大きさの WebP にする" do
    data = AvatarImage.process(write_image("a.png"))
    image = result(data)

    assert_equal "WEBP", data.byteslice(8, 4)
    assert_equal [AvatarImage::SIZE, AvatarImage::SIZE], [image.width, image.height]
    # 中央の 200 四方は、左半分が黒・右半分が白
    assert_operator image.crop(0, 0, 10, 10).avg, :<, 10
    assert_operator image.crop(AvatarImage::SIZE - 10, 0, 10, 10).avg, :>, 245
  end

  test "指定した範囲で切り抜く" do
    image = result(AvatarImage.process(write_image("a.jpg"), crop: { x: 0, y: 0, size: 100 }))

    assert_operator image.avg, :<, 10
  end

  test "はみ出した範囲は、画像の内側に寄せる" do
    image = result(AvatarImage.process(write_image("a.png"), crop: { x: 350, y: -20, size: 150 }))

    assert_operator image.avg, :>, 245
  end

  test "大きさが0以下・画像より大きい範囲でも、画像の中に収まる正方形で切り抜く" do
    path = write_image("a.png")

    [{ x: 0, y: 0, size: 0 }, { x: -10, y: -10, size: -5 }, { x: 10**30, y: 10**30, size: 10**30 }].each do |crop|
      image = result(AvatarImage.process(path, crop:))
      assert_equal [AvatarImage::SIZE, AvatarImage::SIZE], [image.width, image.height]
    end
  end

  test "EXIF の向きを直してから切り抜く（画面で調整した範囲は、向きを直した画像の上の座標）" do
    # 右に90度回して表示する画像。表示では縦長で、上半分が黒、下半分が白になる
    path = write_image("a.jpg", orientation: 6)

    image = result(AvatarImage.process(path, crop: { x: 0, y: 300, size: 100 }))

    assert_operator image.avg, :>, 245
  end

  test "写真の形式でないものは受け付けない" do
    path = File.join(@dir, "a.svg")
    File.write(path, %(<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"/>))
    tiff = File.join(@dir, "a.tif").tap { Vips::Image.black(10, 10).write_to_file(it) }
    text = File.join(@dir, "a.png").tap { File.write(it, "not an image") }

    [path, tiff, text].each do |file|
      error = assert_raises(AvatarImage::Invalid) { AvatarImage.process(file) }
      assert_equal :invalid_format, error.key
    end
  end

  test "大きすぎるファイル・画素数の多すぎる画像は受け付けない" do
    path = write_image("a.png", width: 10_000, height: 6_000)

    error = assert_raises(AvatarImage::Invalid) { AvatarImage.process(path) }
    assert_equal :too_many_pixels, error.key

    File.truncate(path, AvatarImage::MAX_BYTES + 1)
    error = assert_raises(AvatarImage::Invalid) { AvatarImage.process(path) }
    assert_equal :too_large, error.key
  end
end
