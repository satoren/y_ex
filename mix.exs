defmodule Yex.MixProject do
  use Mix.Project

  @version "0.0.1"
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
      deps: deps()
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
        "mix.exs"
      ],
      exclude_files: ["test", "native/target", "native/*.so"]
    ]
  end

  defp deps do
    [
      {:rustler, "~> 0.33.0"},
      {:ex_doc, "~> 0.29", only: :dev, runtime: false}
    ]
  end
end
