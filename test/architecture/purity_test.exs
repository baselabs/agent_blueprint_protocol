defmodule AgentBlueprintProtocol.Architecture.PurityTest do
  @moduledoc """
  Purity gate: the package is an inert library. It registers no OTP application
  callback and no supervision tree, adds only vetted OTP applications
  (`:crypto`), and pulls zero third-party/Hex production dependencies — every
  declared dependency is dev/test-only and non-runtime.
  """
  use ExUnit.Case, async: true

  defp application do
    mod = Mix.Project.get()
    if function_exported?(mod, :application, 0), do: mod.application(), else: []
  end

  test "no OTP application callback / supervision tree is registered" do
    refute Keyword.has_key?(application(), :mod),
           "application/0 must not register a :mod callback — the package has no supervision tree"
  end

  test "extra_applications lists only the vetted OTP applications" do
    extra = application() |> Keyword.get(:extra_applications, []) |> Enum.sort()
    assert extra == [:crypto]
  end

  test "every dependency is dev/test-only and non-runtime (zero third-party prod deps)" do
    offenders =
      for dep <- Mix.Project.config()[:deps],
          {name, opts} = normalize_dep(dep),
          not (Keyword.get(opts, :runtime) == false and
                 Enum.sort(List.wrap(Keyword.get(opts, :only))) == [:dev, :test]),
          do: name

    assert offenders == [],
           "dependencies that are not strictly dev/test-only + runtime: false " <>
             "(a production runtime dependency breaks the zero-dep contract): #{inspect(offenders)}"
  end

  defp normalize_dep({name, req, opts}) when is_binary(req), do: {name, opts}
  defp normalize_dep({name, opts}) when is_list(opts), do: {name, opts}
  defp normalize_dep({name, req}) when is_binary(req), do: {name, []}
end
