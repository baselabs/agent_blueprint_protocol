defmodule AgentBlueprintProtocol.Architecture.ToolchainLockstepTest do
  @moduledoc """
  Toolchain lockstep gate: the dev pin in `.tool-versions` is the single
  owner of the Elixir, Erlang/OTP, and Node versions every non-matrix
  workflow step builds with. Each literal `elixir-version`,
  `otp-version`, and `node-version` in every workflow under
  `.github/workflows/` (the CI quality and extraction jobs, the doc gates,
  and the publish job) must equal it; `mix.exs`'s Elixir requirement must
  admit it; and its OTP major must be in `config/config.exs`'s supported
  set. Matrix lanes (`${{ matrix.* }}`) are deliberate other toolchains
  and are exempt here.

  Goes RED on: a workflow pinned to a different patch (publish.yml
  carried Elixir 1.20.2 against the 1.20.3 dev pin), a requirement that
  excludes the pin, or a pin outside the supported OTP set.
  """

  use ExUnit.Case, async: true

  test "every literal workflow toolchain pin equals the .tool-versions dev pin" do
    pins = tool_versions()
    elixir = pins["elixir"] |> String.split("-otp-") |> hd()

    expected = %{
      "elixir-version" => elixir,
      "otp-version" => pins["erlang"],
      "node-version" => pins["nodejs"]
    }

    workflows = Path.wildcard(".github/workflows/*.yml")
    assert workflows != []

    found =
      for path <- workflows,
          [_, key, value] <-
            Regex.scan(
              ~r/^\s+(elixir-version|otp-version|node-version):\s*"([^"]+)"/m,
              File.read!(path)
            ),
          do: {path, key, value}

    # Known positives: the quality job and the publish job pin all three.
    assert Enum.any?(found, &match?({".github/workflows/ci.yml", "elixir-version", _}, &1))
    assert Enum.any?(found, &match?({".github/workflows/publish.yml", "elixir-version", _}, &1))

    drift =
      for {path, key, value} <- found,
          value != expected[key],
          do: {path, key, value, expected[key]}

    assert drift == [], "workflow toolchain pins drift from .tool-versions: #{inspect(drift)}"
  end

  test "mix.exs admits the pinned Elixir and config/config.exs supports the pinned OTP major" do
    pins = tool_versions()
    elixir = pins["elixir"] |> String.split("-otp-") |> hd()
    assert Version.match?(elixir, Mix.Project.config()[:elixir])

    otp_major = pins["erlang"] |> String.split(".") |> hd()
    [_, set] = Regex.run(~r/supported_otp = \[([^\]]*)\]/, File.read!("config/config.exs"))
    assert ~s("#{otp_major}") in String.split(set, ~r/,\s*/), "OTP #{otp_major} not in #{set}"

    assert pins["elixir"] |> String.ends_with?("-otp-" <> otp_major),
           "the Elixir build's OTP (#{pins["elixir"]}) differs from erlang #{pins["erlang"]}"
  end

  defp tool_versions do
    for line <- String.split(File.read!(".tool-versions"), "\n", trim: true),
        [name, version] = String.split(line, ~r/\s+/, parts: 2),
        into: %{},
        do: {name, String.trim(version)}
  end
end
