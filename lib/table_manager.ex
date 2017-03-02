defmodule PersistentEts.TableManager do
  @moduledoc false
  use GenServer

  require Logger

  ## Public interface

  def start_link(mod, path, table_opts, opts \\ []) do
    GenServer.start_link(__MODULE__, {mod, path, table_opts}, opts)
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

  defstruct [:table, :path, :timer,
             table_opts: [], persist_opts: [], persist_every: 60_000]

  @doc false
  def init({mod, path, opts}) do
    Process.flag(:trap_exit, true)
    state = Enum.reduce(opts, %__MODULE__{}, &build_state/2)
    table = :ets.new(mod, state.table_opts)
    state = put_in state.timer, Process.send_after(self(), :not_borrowed, 5_000)
    # We don't start persistence loop yet - only after table is borrowed
    {:ok, %{state | table: table, path: String.to_charlist(path)}}
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
  defp build_state(opt, state),
    do: update_in(state.table_opts, &[opt | &1])

  defp persist(%{table: nil} = state) do
    state
  end
  defp persist(state) do
    :ets.tab2file(state.table, state.path, state.persist_opts)
    Process.send_after(self(), :persist, state.persist_every)
    state
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
