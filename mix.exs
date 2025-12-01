defmodule EctoGraph.MixProject do
  use Mix.Project

  @source "https://github.com/Zurga/ecto_graph"
  def project do
    [
      name: "EctoGraph",
      description:
        "Provides an easy interface to get paths between schemas and a way to walk the paths",
      app: :ecto_graph,
      version: "0.2.0",
      elixir: "~> 1.18",
      homepage_url: @source,
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      package: [
        exclude_patterns: ["priv", ".formatter.exs"],
        maintainers: ["Jim Lemmers"],
        licenses: ["MIT"],
        links: %{
          GitHub: @source
        }
      ],
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.github": :test,
        "coveralls.html": :test,
        "coveralls.json": :test
      ],
      # Docs
      name: "EctoGraph",
      source_url: @source,
      home_page: @source,
      docs: [
        main: "readme",
        source_url: @source,
        extras: ["README.md"]
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(env) when env in ~w/test dev/a, do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:libgraph, "~> 0.16.0"},
      {:ecto, "> 1.0.0"},
      {:ex_doc, "~> 0.37.2", only: :dev, runtime: false},
      {:credo, "~> 1.6", runtime: false, only: [:dev, :test]},
      {:dialyxir, "~> 1.2", runtime: false, only: [:dev, :test]},
      {:excoveralls, "~> 0.18.0", runtime: false, only: [:test]}
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
    ]
  end
end
