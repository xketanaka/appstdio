require "test_helper"

class Files::EffectivePermissionTest < ActiveSupport::TestCase
  describe "#readable? / #editable? / #manageable?" do
    test "上位の権限は下位を含む" do
      manager = Files::EffectivePermission.new("manager")
      editor = Files::EffectivePermission.new("editor")
      viewer = Files::EffectivePermission.new("viewer")

      assert [manager.readable?, manager.editable?, manager.manageable?].all?
      assert [editor.readable?, editor.editable?].all?
      assert_not editor.manageable?
      assert viewer.readable?
      assert_not viewer.editable?
    end

    test "権限なしはどれも満たさない" do
      none = Files::EffectivePermission.new(nil)

      assert_not none.readable?
      assert_not none.editable?
      assert_not none.manageable?
    end

    test "打ち消しの値を渡されても満たさない" do
      assert_not Files::EffectivePermission.new("none").readable?
    end
  end
end
