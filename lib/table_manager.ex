defmodule PersistentEts.TableManager do
  @moduledoc false
  use GenServer, restart: :temporary

  require Logger

  ## Public interface

  def start_link({mod, path, table_opts}) do
    path = String.to_charlist(path)
    GenServer.start_link(__MODULE__, {mod, path, table_opts})
  end

  def borrow(pid, timeout \\ 5_000) do
    ref = Process.monitor(pid)
    GenServer.cast(pid, {:borrow, self(), ref})
    receive do
      {:"ETS-TRANSFER", table, _from, ^ref} ->
        Process.demonitor(ref, [:flush])
        table
      {:DOWN, ^ref, _, _, reason} ->
        exit(reason)
    after
      timeout ->
        Process.demonitor(ref, [:flush])
        exit(:timeout)
    end
  end

  def return(table) do
    give_away_call(table, :return)
  end

  def transfer(table, pid, data) do
    give_away_call(table, {:transfer, pid, data})
  end

  def flush(table) do
    GenServer.call(manager(table), :flush)
  end

  defp give_away_call(table, data, timeout \\ 5_000) do
    pid = manager(table)
    ref = Process.monitor(pid)
    :ets.give_away(table, pid, {ref, data})
    receive do
      ^ref ->
        Process.demonitor(ref, [:flush])
        :ok
      {:DOWN, ^ref, _, _, reason} ->
        exit(reason)
    after
      timeout ->
        Process.demonitor(ref, [:flush])
        exit(:timeout)
    end
  end

  defp manager(table) do
    case :ets.info(table, :heir) do
      pid when is_pid(pid) -> pid
      _ -> raise ArgumentError
    end
  end

  ## Callbacks

  defstruct [:table, :path, :timer, type: :set, protection: :protected,
             keypos: 1,
             table_opts: [], persist_opts: [], persist_every: 60_000]

  @doc false
  def init({mod, path, opts}) do
    Process.flag(:trap_exit, true)
    state = Enum.reduce(opts, %__MODULE__{}, &build_state/2)
    table = open_table(mod, path, table_opts(state))
    state = put_in state.timer, Process.send_after(self(), :not_borrowed, 5_000)
    # We don't start persistence loop yet - only after table is borrowed
    {:ok, %{state | table: table, path: path}}
  end

  # We link to the borrowing process - if we die they should too, table is no
  # longer protected!
  @doc false
  def handle_cast({:borrow, pid, ref}, state) do
    Process.cancel_timer(state.timer)
    Process.link(pid)
    :ets.setopts(state.table, [{:heir, self(), :inherited}])
    state = persist(%{state | timer: nil})
    :ets.give_away(state.table, pid, ref)
    {:noreply, state}
  end

  @doc false
  def handle_call(:flush, _from, state) do
    {:reply, :ok, persist(state, sync: true)}
  end

  @doc false
  def handle_info(:persist, state) do
    {:noreply, persist(state)}
  end

  # Nobody borrowed the table for 5s, something is wrong
  def handle_info(:not_borrowed, state) do
    {:stop, :timeout, state}
  end

  def handle_info({:EXIT, _pid, reason}, state) do
    {:stop, reason, state}
  end

  # We're inheriting the table from the owner - it's dying, we're dying too
  def handle_info({:"ETS-TRANSFER", tab, pid, :inherited}, %{table: tab} = state) do
    receive do
      {:EXIT, ^pid, reason} ->
        {:stop, reason, state}
    after
      0 ->
        {:stop, :table_lost, state}
    end
  end

  def handle_info({:"ETS-TRANSFER", tab, pid, {ref, :return}}, %{table: tab} = state) do
    clean_unlink(pid)
    state = persist(state)
    :ets.delete(tab)
    send(pid, ref)
    {:stop, :normal, %{state | table: nil}}
  end

  def handle_info({:"ETS-TRANSFER", tab, pid, {ref, {:transfer, to, data}}}, %{table: tab} = state) do
    clean_unlink(pid)
    Process.link(to)
    :ets.give_away(tab, to, data)
    send(pid, ref)
    {:noreply, state}
  end

  def handle_info(other, state) do
    Logger.warn "Unknown message received by #{inspect self()}: #{inspect other}"
    {:noreply, state}
  end

  @doc false
  def terminate(_reason, state) do
    persist(state)
  end

  defp build_state({:persist_every, period}, state) when is_integer(period),
    do: %{state | persist_every: period}
  defp build_state({:persist_opts, opts}, state) when is_list(opts),
    do: %{state | persist_opts: opts}
  defp build_state({:heir, _, _}, _state),
    do: raise(ArgumentError, "PeristentEts does not support the :heir ets option")
  defp build_state(:private, _state),
    do: raise(ArgumentError, "PersistentEts does not support private ets tables")
  defp build_state(protection, state) when protection in [:protected, :public],
    do: %{state | protection: protection}
  defp build_state(type, state) when type in [:bag, :duplicate_bag, :set, :ordered_set],
    do: %{state | type: type}
  defp build_state({:keypos, pos}, state),
    do: %{state | keypos: pos}
  defp build_state(opt, state),
    do: update_in(state.table_opts, &[opt | &1])

  defp table_opts(state) do
    [state.type, state.protection, keypos: state.keypos] ++ state.table_opts
  end

  defp persist(state, extra \\ [])

  defp persist(%{table: nil} = state, _extra) do
    state
  end
  defp persist(state, extra) do
    if state.timer, do: Process.cancel_timer(state.timer)
    opts = Keyword.merge(state.persist_opts, extra)
    :ok = :ets.tab2file(state.table, state.path, opts)
    ref = Process.send_after(self(), :persist, state.persist_every)
    %{state | timer: ref}
  end

  defp open_table(mod, path, opts) do
    if File.regular?(path) do
      with {:ok, info} <- :ets.tabfile_info(path),
           Enum.each(info, &check_info(&1, mod, opts)),
           {:ok, table} <- :ets.file2tab(path, verify: verify?(info)) do
        Enum.each(:ets.info(table), &check_info(&1, mod, opts))
        table
      else
        {:error, reason} ->
          raise ArgumentError, "#{path} is not a valid PersistentEts file: #{inspect reason}"
      end
    else
      :ets.new(mod, opts)
    end
  end

  defp verify?(opts), do: Enum.any?(opts, &match?({:extended_info, _}, &1))

  defp check_info({:name, saved_name}, name, _opts) do
    unless saved_name == name do
      raise ArgumentError, "file was created with different table name"
    end
  end
  defp check_info({:type, type}, _name, opts) do
    unless type in opts do
      raise ArgumentError, "file was created with different table type"
    end
  end
  defp check_info({:named_table, bool}, _name, opts) do
    unless (:named_table in opts) == bool do
      raise ArgumentError, "file was created with a different named table setting"
    end
  end
  defp check_info({:protection, protection}, _name, opts) do
    unless protection in opts do
      raise ArgumentError, "file was created with different protection"
    end
  end
  defp check_info({:compressed, bool}, _name, opts) do
    unless (:compressed in opts) == bool do
      raise ArgumentError, "file was created with a different compressed setting"
    end
  end
  defp check_info({:keypos, pos}, _name, opts) do
    unless {:keypos, pos} in opts do
      raise ArgumentError, "file was created with different keypos setting"
    end
  end
  defp check_info({:write_concurrency, bool}, _name, opts) do
    unless !!opts[:write_concurrency] == bool do
      raise ArgumentError, "file was created with different write_concurrency setting"
    end
  end
  defp check_info({:read_concurrency, bool}, _name, opts) do
    unless !!opts[:read_concurrency] == bool do
      raise ArgumentError, "file was created with different read_concurrency setting"
    end
  end
  defp check_info(_info, _name, _opts) do
    :ok
  end

  defp clean_unlink(pid) do
    Process.unlink(pid)
    receive do
      {:EXIT, ^pid, _} ->
        :ok
    after
      0 ->
        :ok
    end
  end
end
