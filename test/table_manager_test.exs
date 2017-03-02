defmodule PersistentEts.TableManagerTest do
  use ExUnit.Case

  alias PersistentEts.TableManager

  import PersistentEts.FileHelpers

  test "transfers table ownership" do
    in_tmp(fn path ->
      pid = start_manager(path)
      table = TableManager.borrow(pid)
      assert self() == :ets.info(table, :owner)
    end)
  end

  test "stores the file after the borrow" do
    in_tmp(fn path ->
      pid = start_manager(path, persist_opts: [sync: true])
      assert [] == File.ls!(path)
      TableManager.borrow(pid)
      assert_file Path.join(path, "table.tab")
    end)
  end

  test "kills the owner if the manager dies" do
    in_tmp(fn path ->
      Process.flag(:trap_exit, true)
      pid = start_manager(path)
      parent = self()

      owner = spawn_link(fn ->
        TableManager.borrow(pid);
        send(parent, :ready)
        :timer.sleep(:infinity)
      end)

      assert_receive :ready
      Process.exit(pid, :shutdown)
      assert_receive {:EXIT, ^owner, :shutdown}
    end)
  end

  test "kills the manager if the owner dies" do
    in_tmp(fn path ->
      Process.flag(:trap_exit, true)
      pid = start_manager(path)
      parent = self()

      owner = spawn_link(fn ->
        TableManager.borrow(pid);
        send(parent, :ready)
        :timer.sleep(:infinity)
      end)

      assert_receive :ready
      Process.exit(owner, :shutdown)
      assert_receive {:EXIT, ^pid, :shutdown}
    end)
  end

  test "saves the table before dying" do
    in_tmp(fn path ->
      Process.flag(:trap_exit, true)
      pid = start_manager(path, [:named_table])
      parent = self()

      owner = spawn_link(fn ->
        TableManager.borrow(pid);
        :ets.insert(__MODULE__, {:foo})
        send(parent, :ready)
        :timer.sleep(:infinity)
      end)

      assert_receive :ready
      assert [{:foo}] = :ets.tab2list(__MODULE__)
      Process.exit(pid, :shutdown)
      assert_receive {:EXIT, ^owner, :shutdown}
      assert_file Path.join(path, "table.tab")
      start_manager(path, [:named_table])
      assert [{:foo}] = :ets.tab2list(__MODULE__)
    end)
  end

  @tag :capture_log
  test "saves the table periodically" do
    in_tmp(fn path ->
      Process.flag(:trap_exit, true)
      pid = start_manager(path, [:named_table, :public, persist_every: 100])
      parent = self()

      spawn_link(fn ->
        TableManager.borrow(pid);
        :ets.insert(__MODULE__, {:foo})
        send(parent, :ready)
        :timer.sleep(:infinity)
      end)

      assert_receive :ready
      assert [{:foo}] = :ets.tab2list(__MODULE__)
      :timer.sleep(150)
      assert_file Path.join(path, "table.tab")
      :ets.insert(__MODULE__, {:bar})
      Process.exit(pid, :kill)
      start_manager(path, [:named_table, :public, persist_every: 100])
      assert [{:foo}] = :ets.tab2list(__MODULE__)
    end)
  end

  test "does not allow starting private tables" do
    in_tmp(fn path ->
      assert_linked_raise ArgumentError, fn ->
        start_manager(path, [:private])
      end
    end)
  end

  test "does not allow setting the heir option" do
    in_tmp(fn path ->
      assert_linked_raise ArgumentError, fn ->
        start_manager(path, [{:heir, self(), :foo}])
      end
    end)
  end

  test "return persists table & shuts down the manager" do
    in_tmp(fn path ->
      pid = start_manager(path, [:named_table])
      parent = self()

      owner = spawn_link(fn ->
        table = TableManager.borrow(pid)
        :ets.insert(__MODULE__, {:foo})
        send(parent, :ready)
        assert_receive :delete
        TableManager.return(table)
        send(parent, :ready)
        :timer.sleep(:infinity)
      end)

      assert_receive :ready
      assert [{:foo}] = :ets.tab2list(__MODULE__)
      send(owner, :delete)
      assert_receive :ready
      assert Process.alive?(owner)
      assert_file Path.join(path, "table.tab")
      start_manager(path, [:named_table])
      assert [{:foo}] = :ets.tab2list(__MODULE__)
    end)
  end

  test "transfer sends the transfer message" do
    in_tmp(fn path ->
      pid = start_manager(path, [:named_table])
      parent = self()

      spawn_link(fn ->
        table = TableManager.borrow(pid)
        TableManager.transfer(table, parent, :foo)
        :timer.sleep(:infinity)
      end)

      assert_receive {:"ETS-TRANSFER", __MODULE__, _, :foo}
    end)
  end

  test "transfer relinks to the new owner" do
    in_tmp(fn path ->
      Process.flag(:trap_exit, true)
      pid = start_manager(path, [:named_table])
      parent = self()

      another = spawn_link(fn ->
        assert_receive {:"ETS-TRANSFER", _, _, _}
        send(parent, :ready)
        :timer.sleep(:infinity)
      end)

      owner = spawn_link(fn ->
        table = TableManager.borrow(pid)
        TableManager.transfer(table, another, :foo)
        :timer.sleep(:infinity)
      end)

      assert_receive :ready
      Process.exit(pid, :shutdown)
      assert_receive {:EXIT, ^another, :shutdown}
      refute_receive {:EXIT, ^owner, :shutdown}
    end)
  end

  defp start_manager(path, opts \\ []) do
    path = Path.join(path, "table.tab")
    with {:ok, pid} <- TableManager.start_link(__MODULE__, path, opts) do
      pid
    end
  end

  defp assert_linked_raise(error, fun) do
    old = Process.flag(:trap_exit, true)
    try do
      fun.()
      assert_receive {:EXIT, _pid, {reason, stack}}
      reason = Exception.normalize(:error, reason, stack)
      assert error == reason.__struct__
    after
      Process.flag(:trap_exit, old)
    end
  end
end
