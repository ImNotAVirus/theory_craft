defmodule TheoryCraft.MixProject do
  use Mix.Project

  def project() do
    [
      app: :theory_craft,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application() do
    [
      extra_applications: [:logger],
      mod: {TheoryCraft.Application, []}
    ]
  end

  def aliases() do
    [
      tidewave:
        "run --no-halt -e 'Agent.start(fn -> Bandit.start_link(plug: Tidewave, port: 4000) end)'"
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps() do
    [
      {:nimble_csv, "~> 1.3"},
      {:nimble_parsec, "~> 1.4"},

      ## AI agent
      {:tidewave, "~> 0.5", only: :dev},
      {:bandit, "~> 1.0", only: :dev}
    ]
  end
end
