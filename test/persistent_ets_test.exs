defmodule PersistentEtsTest do
  use ExUnit.Case, async: true

  import PersistentEts.FileHelpers

  doctest PersistentEts

  test "new" do
    in_tmp(fn path ->
      parent = self()
      file = Path.join(path, "table.tab")

      pid =
        spawn(fn ->
          PersistentEts.new(:foo, file, [:public, :named_table])
          send(parent, :continue)

          receive do
            :continue -> :ok
          end
        end)

      assert_receive :continue

      :ets.insert(:foo, {:hello, :world})
      assert [{:hello, :world}] = :ets.lookup(:foo, :hello)

      table_manager = :ets.info(:foo, :heir)
      monitor = Process.monitor(table_manager)
      send(pid, :continue)

      assert_receive {:DOWN, ^monitor, _, _, _}
      assert :undefined == :ets.info(:foo)
    end)
  end
end
