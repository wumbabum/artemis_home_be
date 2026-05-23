defmodule ArtemisHomeBe.MixProject do
  use Mix.Project

  def project do
    [
      apps_path: "apps",
      version: "0.1.0",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      # threshold: 0 silences Mix's built-in 90% cover check; ExCoveralls is the
      # authority on coverage via coveralls.json (minimum_coverage: 100).
      test_coverage: [tool: ExCoveralls, threshold: 0],
      dialyzer: [
        plt_add_apps: [:ex_unit, :mix],
        ignore_warnings: ".dialyzer_ignore.exs"
      ]
    ]
  end

  def cli do
    [
      preferred_envs: [
        all_tests: :test,
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.html": :test,
        dialyzer: :test,
        credo: :test
      ]
    ]
  end

  # Dependencies listed here are available only for this
  # project and cannot be accessed from applications inside
  # the apps folder.
  #
  # Run "mix help deps" for examples and options.
  defp deps do
    [
      {:excoveralls, "~> 0.18", only: :test},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      all_tests: [
        "compile --force --warnings-as-errors",
        "credo --strict",
        "format --check-formatted",
        # --raise fails the suite when coverage drops below the threshold set
        # in coveralls.json (minimum_coverage: 100 with skip_files for generated code).
        "coveralls --umbrella --raise",
        "dialyzer --list-unused-filters"
      ],
      precommit: [
        "compile --warnings-as-errors",
        "format --check-formatted",
        "test"
      ],
      # Convenience alias so the task can be invoked with the dotted name
      # `mix seed.homes` in addition to the underscored `mix seed_homes`.
      "seed.homes": "seed_homes"
    ]
  end
end
