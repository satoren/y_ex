defmodule Yex.MixProject do
  use Mix.Project

  @version "0.6.5"
  @repo "https://github.com/satoren/y_ex"

  @description """
  Elixir wrapper for Yjs
  """

  def project do
    [
      app: :y_ex,
      version: @version,
      elixir: "~> 1.7",
      start_permanent: Mix.env() == :prod,
      package: package(),
      name: "y_ex",
      description: @description,
      deps: deps(),
      source_url: @repo,
      homepage_url: @repo,
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.lcov": :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.cobertura": :test
      ],
      rustler_crates: rustler_crates(),
      elixirc_paths: elixirc_paths(Mix.env())
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp package do
    [
      name: "y_ex",
      maintainers: ["mshiraki"],
      licenses: ["MIT"],
      links: %{"Github" => @repo},
      files: [
        "lib",
        "priv",
        "native",
        "README.md",
        "checksum-*.exs",
        "mix.exs"
      ],
      exclude_files: ["test", "native/target", "native/*.so"]
    ]
  end

  defp deps do
    [
      {:rustler, "~> 0.34.0", runtime: false},
      {:rustler_precompiled, "~> 0.6.0", optional: true},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: :test},
      {:benchee, "~> 1.0", only: :dev},
    ]
  end

  defp rustler_crates do
    [
      yex: [
        path: "native/yex",
        mode: if(Mix.env() == :prod, do: :release, else: :debug)
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]
end
