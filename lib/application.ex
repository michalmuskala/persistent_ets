defmodule PersistentEts.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    children = [
      worker(PersistentEts.TableManager, [], restart: :temporary),
    ]

    opts = [strategy: :simple_one_for_one, name: PersistentEts.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
