defmodule Ragistry.MixProject do
  use Mix.Project

  def project do
    [
      app: :ragistry,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      test_coverage: [local_only: false],
      description: "A distributed process registry based on Ra",
      package: package()
    ]
  end

  defp elixirc_paths(:test), do: [~c"lib", ~c"test/support"]
  defp elixirc_paths(_), do: [~c"lib"]

  def application do
    [
      mod: {Ragistry.Application, []},
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:ra, "~> 2.16"},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:ex_unit_cluster, "~> 0.7.0", only: :test}
    ]
  end

  defp package do
    [
      name: "ragistry",
      files: ~w(lib mix.exs README.md),
      licenses: ["MPL-2.0"],
      links: %{
        "GitHub" => "https://github.com/hkrutzer/ragistry"
      }
    ]
  end
end
