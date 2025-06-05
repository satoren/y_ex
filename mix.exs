defmodule Yex.MixProject do
  use Mix.Project

  @version "0.8.0"
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
      ]
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
        "native/yex/src",
        "native/yex/Cargo.*",
        "native/yex/Cross.*",
        "native/yex/README.md",
        "native/yex/README.md",
        "README.md",
        "checksum-*.exs",
        "mix.exs"
      ]
    ]
  end

  defp deps do
    [
      {:rustler, ">= 0.0.0", optional: true},
      {:rustler_precompiled, ">= 0.6.0"},
      {:ex_doc, "~> 0.38", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: :test},
      {:benchee, "~> 1.0", only: :dev},
      {:mock, "~> 0.3.0", only: :test}
    ]
  end
end
