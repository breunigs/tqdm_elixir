defmodule Tqdm.Mixfile do
  use Mix.Project

  @version "0.0.3"

  def project do
    [
      app: :tqdm,
      version: @version,
      elixir: "~> 1.4",
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      source_url: "https://github.com/antipax/tqdm_elixir",
      docs: [
        main: "Tqdm",
        extras: ["README.md"],
        source_ref: "v#{@version}"
      ],
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ]
    ]
  end

  defp deps do
    [
      {:credo, "~> 1.7.5", only: [:dev, :test]},
      {:dialyxir, "~> 1.0", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.32", only: :dev},
      {:excoveralls, "~> 0.18", only: :test}
    ]
  end

  defp description do
    "Add a progress bar to your enumerables (Lists, Maps, Streams, Ranges, etc.) in a second."
  end

  defp package do
    [
      files: ["lib", "mix.exs", "README.md", "LICENSE"],
      maintainers: ["Eric Entin"],
      licenses: ["Apache 2.0"],
      links: %{
        "GitHub" => "https://github.com/antipax/tqdm_elixir"
      }
    ]
  end
end
