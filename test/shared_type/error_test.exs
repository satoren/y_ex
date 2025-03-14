defmodule Yex.DeletedSharedTypeErrorTest do
  use ExUnit.Case
  alias Yex.DeletedSharedTypeError

  describe "DeletedSharedTypeError" do
    test "raises with default message" do
      assert_raise DeletedSharedTypeError, "Shared type has been deleted", fn ->
        raise DeletedSharedTypeError
      end
    end

    test "raises with custom message" do
      message = "Custom error message"

      assert_raise DeletedSharedTypeError, message, fn ->
        raise DeletedSharedTypeError, message
      end
    end

    test "creates error struct with default message" do
      error = %DeletedSharedTypeError{}
      assert error.message == "Shared type has been deleted"
    end

    test "creates error struct with custom message" do
      message = "Custom error message"
      error = %DeletedSharedTypeError{message: message}
      assert error.message == message
    end
  end
end
