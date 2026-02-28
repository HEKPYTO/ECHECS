defmodule Echecs.MixProject do
  use Mix.Project

  def project do
    [
      app: :echecs,
      version: "0.1.3",
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      description:
        "A high-performance chess library in pure Elixir with bitboard move generation.",
      package: package(),
      deps: deps(),
      docs: docs(),
      name: "Echecs",
      source_url: "https://github.com/HEKPYTO/ECHECS"
    ]
  end

  defp package do
    [
      licenses: ["GPL-3.0-or-later"],
      links: %{"GitHub" => "https://github.com/HEKPYTO/ECHECS"},
      files: ~w(lib mix.exs README.md LICENSE)
    ]
  end

  defp docs do
    [
      main: "Echecs",
      extras: ["README.md"]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Echecs.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:git_hooks, "~> 0.7.3", only: [:dev], runtime: false},
      {:exprof, "~> 0.2.0", only: :dev},
      {:nimble_parsec, "~> 1.4"}
    ]
  end
end
