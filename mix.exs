defmodule Yex.MixProject do
  use Mix.Project

  @version "0.13.0"
  @repo "https://github.com/satoren/y_ex"

  @description """
  Elixir wrapper for Yjs
  """

  def project do
    [
      app: :y_ex,
      version: @version,
      elixir: "~> 1.16",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      package: package(),
      name: "y_ex",
      description: @description,
      deps: deps(),
      source_url: @repo,
      homepage_url: @repo,
      docs: docs(),
      test_coverage: [tool: ExCoveralls]
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      extras: ["README.md", "LICENSE"],
      groups_for_modules: [
        Document: [
          Yex,
          Yex.Doc,
          Yex.Doc.Options,
          Yex.Snapshot,
          Yex.StickyIndex,
          Yex.Subscription
        ],
        "Shared types": [
          Yex.SharedType,
          Yex.PrelimType,
          Yex.Output,
          Yex.Text,
          Yex.TextPrelim,
          Yex.Array,
          Yex.ArrayPrelim,
          Yex.Map,
          Yex.MapPrelim,
          Yex.WeakLink,
          Yex.WeakPrelim,
          Yex.Buffer
        ],
        XML: [
          Yex.Xml,
          Yex.XmlFragment,
          Yex.XmlFragmentPrelim,
          Yex.XmlElement,
          Yex.XmlElementPrelim,
          Yex.XmlText,
          Yex.XmlTextPrelim
        ],
        Events: [
          Yex.ArrayEvent,
          Yex.MapEvent,
          Yex.TextEvent,
          Yex.XmlEvent,
          Yex.XmlTextEvent,
          Yex.TransactionCleanupEvent
        ],
        "Undo manager": [
          Yex.UndoManager,
          Yex.UndoManager.Options,
          Yex.UndoManager.StackItemEvent,
          Yex.UndoManager.StackClearedEvent
        ],
        Protocols: [
          Yex.Sync,
          Yex.Sync.SharedDoc,
          Yex.Sync.SharedDoc.PersistenceBehaviour,
          Yex.Awareness
        ],
        Server: [Yex.DocServer, Yex.DocServer.State],
        Errors: [Yex.DeletedSharedTypeError, Yex.TransactionAcqError]
      ]
    ]
  end

  def cli do
    [
      preferred_envs: [
        coveralls: :test,
        "coveralls.lcov": :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.cobertura": :test
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

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
        "README.md",
        "checksum-*.exs",
        "mix.exs"
      ]
    ]
  end

  defp deps do
    [
      {:rustler, "~> 0.38", optional: true},
      {:rustler_precompiled, ">= 0.7.0"},
      {:ex_doc, "~> 0.40", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: :test},
      {:benchee, "~> 1.0", only: :dev}
    ]
  end
end
