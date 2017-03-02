defmodule PersistentEts do
  @moduledoc """
  Ets table backed by a persistence file

  The table is persisted using the `:ets.file2tab/2` and `:ets.tab2file/3`
  functions.

  Table is to be created with `PersistentEts.new/3` in place of `:ets.new/2`.
  After that all functions from `:ets` can be used like with any other table,
  except `:ets.give_away/3` and `:ets.delete/1` - replacement functions are
  provided in this module. The `:ets.setopts/2` function to change the heir
  is not supported - the heir setting is leveraged by the persistence mechanism.

  Like with regular ets table, the table is destroyed once the owning process
  (the one that called `PersistentEts.new/3`) dies, but the table data is persisted
  so it will be re-read when table is opened again.

  ## Example

      pid = spawn(fn ->
        :foo = PersistentEts.new(:foo, "table.tab", [:named_table])
        :ets.insert(:foo, [a: 1])
      end)
      Process.exit(pid, :diediedie)
      PersistentEts.new(:foo, "table.tab", [:named_table])
      [a: 1] = :ets.tab2list(:foo)

  """

  @type tab :: :ets.tab
  @type type :: :ets.type
  @type access :: :public | :protected
  @type tweaks ::
    {:write_concurrency, boolean} |
    {:read_concurrency, boolean} |
    :compressed
  @type persist_opt :: {:extended_info, [:md5sum | :object_count]} | {:sync, boolean}
  @type persistence :: {:persist_every, pos_integer} | {:persist_opts, [persist_opt]}
  @type option :: type | access | :named_table | {:keypos, pos_integer} | tweaks | persistence

  @doc """
  Creates a new table backed by the file `path`.

  Starts a "table manager" process responsible for periodically persisting the
  table to the file `path` and links the caller to the process.

  Tries to re-read the table from the persistence file. If no such file exists,
  a new table is created. Since options a table was created with are persisted
  alongside the table data, if the options the table was created with
  differ from the current options an error occurs. It's advised to manually
  transfer the data to the new table, with new options, if a change if options
  is needed.

  If the table was created with extended info, it will be read using the verify
  option. For information on what this means, refer to `:ets.file2tab/2`.

  Changing the `:heir` option on the returned table is not supported, since it's
  leveraged by the persistence mechanism for correct operation.

  ## Options

    * `:path` (required) - where to store the table file,
    * `:persist_every` - how often to write the table to the file (default: 5_000),
    * `:persist_opts` - options passed to `:ets.tab2file/3` when saving the table

  For other options refer to the `:ets.new/2` documentation.

  The `:heir` option is not supported as it's leveraged by the persistence system
  to guarantee the best possible durability.
  The `:private` option is not supported since the manager process needs access
  to the table in order to save it to the file.
  """
  @spec new(atom, Path.t, [option]) :: tab
  def new(module, path, opts) do
    {:ok, pid} = Supervisor.start_child(PersistentEts.Supervisor, [module, path, opts])
    PersistentEts.TableManager.borrow(pid)
  end

  @doc """
  Make process `pid` the new owner of `table`.

  If successful, message `{:"ETS-TRANSFER", table, manager_pid, data}` is sent
  to the new owner.

  This behaviour differs slightly from the behaviour of `:ets.give_away/3`,
  where the pid in the transfer message is the pid of the process giving the
  table away. This is not maintained, because the table manager process needs
  to keep track of the owner.

  The old owner is unlinked from the manager process and the new onwer is linked.

  See `:ets.give_away/3` for more information.
  """
  @spec give_away(tab, pid, term) :: true
  def give_away(table, pid, data) do
    PersistentEts.TableManager.transfer(table, pid, data)
    true
  end

  @doc """
  Synchronously dumps the table `table` to disk.

  This can be used to make sure all changes have been persisted, before continuing.
  The persistence loop will be restarted.
  """
  @spec flush(tab) :: :ok
  def flush(table) do
    PersistentEts.TableManager.flush(table)
  end

  @doc """
  Deletes the entire table `table`.

  See `:ets.delete/1` for more information.
  """
  @spec delete(tab) :: true
  def delete(table) do
    PersistentEts.TableManager.return(table)
    true
  end
end
