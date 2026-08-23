defmodule AgentBlueprintProtocol.CompatibilityTest do
  @moduledoc """
  The compatibility surface (the compatibility law): identity-exact or
  error — a manifest identity is matched only by an observed identity with
  the exact (kind, name, version, digest) tuple; ranges deny on BOTH
  sides; duplicate candidates (including byte-identical observations) and
  duplicate hand-built manifest entries deny; extra observed identities
  are evidence-neutral.
  """

  use ExUnit.Case, async: true

  alias AgentBlueprintProtocol.{
    Compatibility,
    Deployment,
    DeploymentFixture,
    Digest,
    Error,
    Evidence
  }

  alias Compatibility.Observed

  defp deploy(opts), do: elem(Deployment.from_value(DeploymentFixture.fixture_value(opts)), 1)

  defp default_observed do
    [
      %{
        kind: "package",
        name: "agent_blueprint_protocol",
        version: "0.1.0",
        digest: DeploymentFixture.tagged("identity")
      }
    ]
  end

  test "exact match green: one verified check per manifest identity, detail the matched digest" do
    deployment =
      deploy(
        build_identities: [
          DeploymentFixture.build_identity(),
          DeploymentFixture.build_identity(name: "com.example.adapter", kind: "adapter")
        ]
      )

    observed = %Observed{
      identities:
        default_observed() ++
          [
            %{
              kind: "adapter",
              name: "com.example.adapter",
              version: "0.1.0",
              digest: DeploymentFixture.tagged("identity")
            }
          ]
    }

    assert {:ok, %Evidence{not_verified: not_verified, checks: checks}} =
             Compatibility.verify(deployment, observed)

    assert [%{surface: :compatibility}, %{surface: :compatibility}] = checks
    assert Enum.all?(checks, & &1.verified)
    assert Enum.map(checks, & &1.subject) == [["build_identities", 0], ["build_identities", 1]]
    assert {:ok, digest} = Digest.from_tagged(DeploymentFixture.tagged("identity"))
    assert Enum.map(checks, & &1.detail) == [digest, digest]

    assert Enum.take(not_verified, 7) ==
             ~w(tenancy live_policy authority effect_ownership execution billing evaluation_truth)a
  end

  test "wrong version, digest, kind, or name on the observed side denies entry missing" do
    for forged <- [
          %{version: "0.2.0"},
          %{digest: DeploymentFixture.tagged("other")},
          %{kind: "build"},
          %{name: "other.package"}
        ] do
      observed = %Observed{identities: [Map.merge(hd(default_observed()), forged)]}

      assert {:error,
              %Error{code: :compatibility_entry_missing, subject: ["build_identities", 0]}} =
               Compatibility.verify(deploy([]), observed)
    end
  end

  test "two observed candidates for one manifest identity deny duplicate — including byte-identical" do
    observed = %Observed{identities: default_observed() ++ default_observed()}

    assert {:error,
            %Error{code: :compatibility_duplicate_entry, subject: ["build_identities", 0]}} =
             Compatibility.verify(deploy([]), observed)
  end

  test "two observed same name different version: the matching one wins, the other is neutral" do
    drifted = %{hd(default_observed()) | version: "0.9.0"}
    observed = %Observed{identities: [drifted, hd(default_observed())]}

    assert {:ok, %Evidence{checks: [check]}} = Compatibility.verify(deploy([]), observed)
    assert check.verified
  end

  test "extra observed identities are evidence-neutral: no check, no denial" do
    observed = %Observed{
      identities:
        default_observed() ++
          [
            %{
              kind: "extension",
              name: "com.wider-surface/extension",
              version: "3.2.1",
              digest: DeploymentFixture.tagged("wide")
            }
          ]
    }

    assert {:ok, %Evidence{checks: [check]}} = Compatibility.verify(deploy([]), observed)
    assert check.subject == ["build_identities", 0]
  end

  test "range vocabulary on the observed side denies identity inexact" do
    for range <- ["*", "latest", "1.x", "1.X", ">=2.0.0", "~> 1.0"] do
      observed = %Observed{identities: [%{hd(default_observed()) | version: range}]}

      assert {:error, %Error{code: :compatibility_identity_inexact, subject: ["identities", 0]}} =
               Compatibility.verify(deploy([]), observed)
    end
  end

  test "range vocabulary on a struct-bypassed manifest side denies identity inexact" do
    {:object, ms} = DeploymentFixture.fixture_value([])

    members =
      Enum.map(ms, fn
        {"build_identities", {:array, [entry]}} ->
          forged =
            entry
            |> then(fn {:object, em} ->
              {:object,
               Enum.map(em, fn
                 {"version", _} -> {"version", {:string, "1.x"}}
                 other -> other
               end)}
            end)

          {"build_identities", {:array, [forged]}}

        other ->
          other
      end)

    assert {:error,
            %Error{code: :compatibility_identity_inexact, subject: ["build_identities", 0]}} =
             Compatibility.verify(%Deployment{value: {:object, members}}, %Observed{
               identities: default_observed()
             })
  end

  test "duplicate name in a struct-bypassed manifest denies duplicate entry" do
    {:object, ms} = DeploymentFixture.fixture_value([])

    with_dup =
      Enum.map(ms, fn
        {"build_identities", {:array, entries}} ->
          {"build_identities", {:array, entries ++ entries}}

        other ->
          other
      end)

    assert {:error,
            %Error{code: :compatibility_duplicate_entry, subject: ["build_identities", 1]}} =
             Compatibility.verify(%Deployment{value: {:object, with_dup}}, %Observed{
               identities: default_observed()
             })
  end

  test "exact?/1 is false for range expressions and true for exact spellings" do
    for range <- ["", "*", "latest", "1.x", "1.X", "1.*", ">=1", "~> 2", "1 .0", "1.0 "] do
      refute Compatibility.exact?(%{hd(default_observed()) | version: range}), range
    end

    for exact <- ["0.1.0", "1", "2.0.0-rc.1+build.5", "10.20.30"] do
      assert Compatibility.exact?(%{hd(default_observed()) | version: exact}), exact
    end
  end

  test "exact?/1 agrees with the decode-side version check on the range vocabulary" do
    # Decode denies the same class through the registry table; the public
    # predicate and the table check must not drift.
    assert {:error, reason} =
             Deployment.from_value(
               DeploymentFixture.fixture_value(
                 build_identities: [DeploymentFixture.build_identity(version: "1.x")]
               )
             )

    assert reason == :compatibility_identity_inexact
  end

  # ---- rim probes (typed denials on every malformed shape) --------------------------

  test "rim: a non-struct deployment denies typed" do
    assert {:error, %Error{code: :invalid_type, subject: ["deployment"]}} =
             Compatibility.verify(:junk, %Observed{identities: []})
  end

  test "rim: a non-struct observed denies typed" do
    assert {:error, %Error{code: :invalid_type, subject: ["observed"]}} =
             Compatibility.verify(deploy([]), :junk)
  end

  test "rim: a struct-bypassed deployment without build_identities denies missing member" do
    {:object, ms} = DeploymentFixture.fixture_value([])
    stripped = Enum.reject(ms, fn {name, _} -> name == "build_identities" end)

    assert {:error, %Error{code: :missing_required_field, subject: ["build_identities"]}} =
             Compatibility.verify(%Deployment{value: {:object, stripped}}, %Observed{
               identities: default_observed()
             })
  end

  test "rim: a malformed manifest entry denies typed with its index" do
    {:object, ms} = DeploymentFixture.fixture_value([])

    forged =
      Enum.map(ms, fn
        {"build_identities", {:array, [_]}} ->
          {"build_identities", {:array, [{:object, [{"kind", {:string, "package"}}]}]}}

        other ->
          other
      end)

    assert {:error, %Error{code: :invalid_type, subject: ["build_identities", 0]}} =
             Compatibility.verify(%Deployment{value: {:object, forged}}, %Observed{
               identities: default_observed()
             })
  end

  test "rim: a non-array build_identities member denies typed" do
    {:object, ms} = DeploymentFixture.fixture_value([])

    forged =
      Enum.map(ms, fn
        {"build_identities", _} -> {"build_identities", {:string, "junk"}}
        other -> other
      end)

    assert {:error, %Error{code: :invalid_type, subject: ["build_identities"]}} =
             Compatibility.verify(%Deployment{value: {:object, forged}}, %Observed{identities: []})
  end

  test "rim: observed identities not a list denies typed" do
    assert {:error, %Error{code: :invalid_type, subject: ["identities"]}} =
             Compatibility.verify(deploy([]), %Observed{identities: :junk})
  end

  test "rim: a malformed observed identity denies typed with its index" do
    for junk <- [
          %{kind: "package", name: "x", version: "1.0.0"},
          %{kind: "package", name: "x", version: "1.0.0", digest: "not-tagged", extra: 1},
          %{kind: :package, name: "x", version: "1.0.0", digest: "sha-256:x"},
          "not-a-map"
        ] do
      assert {:error, %Error{code: :invalid_type, subject: ["identities", 0]}} =
               Compatibility.verify(deploy([]), %Observed{identities: [junk]})
    end
  end

  test "rim: exact?/1 is total over junk input (false, never raises)" do
    refute Compatibility.exact?(:junk)
    refute Compatibility.exact?(%{version: 1})
  end

  test "rim: a non-object deployment value denies typed" do
    assert {:error, %Error{code: :invalid_type, subject: ["build_identities"]}} =
             Compatibility.verify(%Deployment{value: {:string, "junk"}}, %Observed{
               identities: []
             })
  end

  test "rim: a manifest entry that is not an object denies typed with its index" do
    {:object, ms} = DeploymentFixture.fixture_value([])

    forged =
      Enum.map(ms, fn
        {"build_identities", {:array, [_]}} -> {"build_identities", {:array, [{:string, "junk"}]}}
        other -> other
      end)

    assert {:error, %Error{code: :invalid_type, subject: ["build_identities", 0]}} =
             Compatibility.verify(%Deployment{value: {:object, forged}}, %Observed{
               identities: []
             })
  end

  test "rim: a matched but unparseable digest denies the digest reason" do
    {:object, ms} = DeploymentFixture.fixture_value([])

    forged =
      Enum.map(ms, fn
        {"build_identities", {:array, [entry]}} ->
          junk =
            entry
            |> then(fn {:object, em} ->
              {:object,
               Enum.map(em, fn
                 {"digest", _} -> {"digest", {:string, "not-tagged"}}
                 other -> other
               end)}
            end)

          {"build_identities", {:array, [junk]}}

        other ->
          other
      end)

    observed = %Observed{identities: [%{hd(default_observed()) | digest: "not-tagged"}]}

    assert {:error, %Error{code: :digest_encoding_invalid, subject: ["build_identities", 0]}} =
             Compatibility.verify(%Deployment{value: {:object, forged}}, observed)
  end

  test "rim: an empty struct-bypassed build_identities denies :invalid_cardinality" do
    {:object, ms} = DeploymentFixture.fixture_value([])

    emptied =
      Enum.map(ms, fn
        {"build_identities", _} -> {"build_identities", {:array, []}}
        other -> other
      end)

    assert {:error, %Error{code: :invalid_cardinality, subject: ["build_identities"]}} =
             Compatibility.verify(%Deployment{value: {:object, emptied}}, %Observed{
               identities: []
             })
  end

  test "rim: a manifest entry with an extra or duplicated member denies typed" do
    {:object, ms} = DeploymentFixture.fixture_value([])
    {"build_identities", {:array, [{:object, em}]}} = List.keyfind(ms, "build_identities", 0)

    with_extra = Enum.sort(em ++ [{"junk", {:string, "x"}}])

    forged =
      Enum.map(ms, fn
        {"build_identities", _} -> {"build_identities", {:array, [{:object, with_extra}]}}
        other -> other
      end)

    assert {:error, %Error{code: :invalid_type, subject: ["build_identities", 0]}} =
             Compatibility.verify(%Deployment{value: {:object, forged}}, %Observed{
               identities: []
             })
  end

  test "case-folded range tags deny on both sides (LATEST, Latest)" do
    for tag <- ["LATEST", "Latest", "*"] do
      observed = %Observed{identities: [%{hd(default_observed()) | version: tag}]}

      assert {:error, %Error{code: :compatibility_identity_inexact, subject: ["identities", 0]}} =
               Compatibility.verify(deploy([]), observed),
             tag
    end

    refute Compatibility.exact?(%{hd(default_observed()) | version: "LATEST"})
  end

  test "rim: a four-member entry missing an identity key denies typed" do
    {:object, ms} = DeploymentFixture.fixture_value([])

    partial =
      Enum.sort([
        {"kind", {:string, "package"}},
        {"name", {:string, "agent_blueprint_protocol"}},
        {"version", {:string, "0.1.0"}},
        {"junk", {:string, "x"}}
      ])

    forged =
      Enum.map(ms, fn
        {"build_identities", _} -> {"build_identities", {:array, [{:object, partial}]}}
        other -> other
      end)

    assert {:error, %Error{code: :invalid_type, subject: ["build_identities", 0]}} =
             Compatibility.verify(%Deployment{value: {:object, forged}}, %Observed{
               identities: []
             })
  end

  test "rim: a non-string member tag in a manifest entry denies typed with its index" do
    {:object, ms} = DeploymentFixture.fixture_value([])

    forged =
      Enum.map(ms, fn
        {"build_identities", {:array, [entry]}} ->
          {:object, em} = entry

          retagged =
            Enum.map(em, fn
              {"version", _} -> {"version", {:integer, 1}}
              other -> other
            end)

          {"build_identities", {:array, [{:object, retagged}]}}

        other ->
          other
      end)

    assert {:error, %Error{code: :invalid_type, subject: ["build_identities", 0]}} =
             Compatibility.verify(%Deployment{value: {:object, forged}}, %Observed{
               identities: []
             })
  end

  test "rim: a struct-bypassed deployment without protocol_revision verifies with a nil revision" do
    {:object, ms} = DeploymentFixture.fixture_value([])
    stripped = Enum.reject(ms, fn {name, _} -> name == "protocol_revision" end)

    assert {:ok, %Evidence{protocol_revision: nil}} =
             Compatibility.verify(%Deployment{value: {:object, stripped}}, %Observed{
               identities: default_observed()
             })
  end
end
