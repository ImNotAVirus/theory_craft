defmodule TheoryCraft.MixProject do
  use Mix.Project

  def project do
    [
      app: :theory_craft,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {TheoryCraft.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:gen_stage, "~> 1.3"},
      {:nimble_csv, "~> 1.3"},
      {:nimble_parsec, "~> 1.4"}
    ]
  end
end
