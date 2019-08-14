defmodule PersistentEts.Mixfile do
  use Mix.Project

  @version "0.2.1"

  def project do
    [app: :persistent_ets,
     version: @version,
     elixir: "~> 1.6",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     elixirc_paths: elixirc_paths(Mix.env),
     deps: deps(),
     description: description(),
     package: package(),
     name: "PersistentEts",
     docs: docs()]
  end

  def application do
    [applications: [:logger],
     mod: {PersistentEts.Application, []}]
  end

  defp elixirc_paths(:test), do: ["test/support", "lib"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [{:ex_doc, "~> 0.14", only: :dev}]
  end

  defp description do
    """
    Ets table backed by a persistence file
    """
  end

  defp package do
    [maintainers: ["Michał Muskała"],
     licenses: ["Apache 2.0"],
     links: %{"GitHub" => "https://github.com/michalmuskala/persistent_ets"}]
  end

  defp docs do
    [source_ref: "v#{@version}",
     canonical: "http://hexdocs.pm/persistent_ets",
     source_url: "https://github.com/michalmuskala/persistent_ets",
     main: "PersistentEts"]
  end
end
