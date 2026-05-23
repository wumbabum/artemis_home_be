defmodule DispatchTest do
  use ExUnit.Case
  doctest Dispatch

  test "greets the world" do
    assert Dispatch.hello() == :world
  end
end
