defmodule TheoryCraft.UtilsTest do
  use ExUnit.Case, async: true

  alias TheoryCraft.Utils

  ## Tests

  describe "normalize_spec/1" do
    test "normalizes module atom to {module, []}" do
      assert Utils.normalize_spec(String) == {String, []}
    end

    test "preserves {module, opts} tuple" do
      assert Utils.normalize_spec({String, [option: :value]}) == {String, [option: :value]}
    end

    test "handles empty opts list" do
      assert Utils.normalize_spec({String, []}) == {String, []}
    end

    test "handles multiple options" do
      opts = [opt1: 1, opt2: 2, opt3: :three]
      assert Utils.normalize_spec({String, opts}) == {String, opts}
    end

    test "raises on invalid spec (not atom or tuple)" do
      assert_raise ArgumentError, "Invalid spec: \"invalid\"", fn ->
        Utils.normalize_spec("invalid")
      end
    end

    test "raises on tuple with non-atom module" do
      assert_raise ArgumentError, ~r/Invalid spec: \{"not_atom", \[\]\}/, fn ->
        Utils.normalize_spec({"not_atom", []})
      end
    end

    test "raises on tuple with non-list opts" do
      assert_raise ArgumentError, ~r/Invalid spec: \{String, "not_a_list"\}/, fn ->
        Utils.normalize_spec({String, "not_a_list"})
      end
    end
  end
end
