defmodule Yex.MixProject do
  use Mix.Project

  @version "0.3.2"
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
      homepage_url: @repo
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
      {:rustler, ">= 0.0.0", optional: true},
      {:rustler_precompiled, "~> 0.7"},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end
end
