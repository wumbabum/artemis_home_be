defmodule Core.MixProject do
  use Mix.Project

  def project do
    [
      app: :core,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.19",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      test_coverage: [tool: ExCoveralls, threshold: 0]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Core.Application, []}
    ]
  end

  # Shared test helpers live under test/support.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # Runtime
      {:req, "~> 0.5"},
      {:joken, "~> 2.6"},
      {:jason, "~> 1.4"},
      # Test
      {:mox, "~> 1.1", only: :test},
      {:stream_data, "~> 1.0", only: [:dev, :test]},
      {:assertions, "~> 0.16", only: :test},
      {:excoveralls, "~> 0.18", only: :test}
    ]
  end
end
