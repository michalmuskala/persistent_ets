defmodule PersistentEts.Mixfile do
  use Mix.Project

  def project do
    [app: :persistent_ets,
     version: "0.1.0",
     elixir: "~> 1.3",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     elixirc_paths: elixirc_paths(Mix.env),
     deps: deps()]
  end

  def application do
    [applications: [:logger],
     mod: {PersistentEts.Application, []}]
  end

  defp elixirc_paths(:test), do: ["test/support", "lib"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    []
  end
end
