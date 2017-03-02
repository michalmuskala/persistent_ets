defmodule PersistentEts do
  def new(module, opts) do
    {:ok, pid} = Supervisor.start_child(PersistentEts.Supervisor, [module, opts])
    PersistentEts.TableManager.borrow(pid)
  end

  def give_away(table, pid, data) do
    PersistentEts.TableManager.transfer(table, pid, data)
    true
  end

  def delete(table) do
    PersistentEts.TableManager.return(table)
    true
  end
end
