require "test_helper"

class TenantSettingTest < ActiveSupport::TestCase
  setup do
    @tenant = Tenant.setup!(name: "テナントA")
    TenantContext.apply(tenant: @tenant)
    @setting = @tenant.setting
  end

  teardown do
    TenantContext.clear
  end

  describe "タイトルラベル" do
    test "前後の空白を落とし、空なら nil にする" do
      @setting.update!(title_label: "  サンプル株式会社  ")
      assert_equal "サンプル株式会社", @setting.title_label

      @setting.update!(title_label: "   ")
      assert_nil @setting.title_label
    end
  end

  describe "タイトルカラー" do
    test "#rrggbb の形だけ受け付け、小文字にそろえる" do
      @setting.update!(title_color: "#1E40AF")
      assert_equal "#1e40af", @setting.title_color

      @setting.title_color = "blue"
      assert_not @setting.valid?
      assert_predicate @setting.errors[:title_color], :present?
    end

    test "明るい色や未設定（既定の白）なら黒い文字、暗い色なら白い文字にする" do
      @setting.title_color = "#fde047"
      assert_predicate @setting, :light_title_color?

      @setting.title_color = "#1e3a8a"
      assert_not_predicate @setting, :light_title_color?

      @setting.title_color = nil
      assert_predicate @setting, :light_title_color?
    end
  end

  describe "ロゴ画像" do
    test "PNG などの画像は受け付ける" do
      @setting.logo.attach(io: StringIO.new("png"), filename: "logo.png", content_type: "image/png")
      assert_predicate @setting, :valid?
    end

    test "SVG は受け付けない" do
      @setting.logo.attach(io: StringIO.new("<svg/>"), filename: "logo.svg", content_type: "image/svg+xml")
      assert_not @setting.valid?
      assert_includes @setting.errors.full_messages.join, "PNG"
    end

    test "1MB を超えるものは受け付けない" do
      @setting.logo.attach(io: StringIO.new("x" * (1.megabyte + 1)), filename: "logo.png", content_type: "image/png")
      assert_not @setting.valid?
      assert_includes @setting.errors.full_messages.join, "1MB"
    end
  end
end
