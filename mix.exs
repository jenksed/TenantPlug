defmodule TenantPlug.MixProject do
  use Mix.Project

  def project do
    [
      app: :tenant_plug,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Automatic tenant context management for Phoenix applications",
      package: package(),
      docs: docs()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:plug, "~> 1.14"},
      {:telemetry, "~> 1.0"},
      {:telemetry_test, "~> 0.1.0", only: :test},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      name: "tenant_plug",
      files: ["lib", "mix.exs", "README*", "LICENSE*"],
      maintainers: ["Your Name"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/elixir-multitenant/tenant_plug"}
    ]
  end

  defp docs do
    [
      main: "TenantPlug",
      extras: ["README.md"]
    ]
  end
end
