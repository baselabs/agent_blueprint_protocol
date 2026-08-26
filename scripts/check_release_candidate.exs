# The release-candidate check: the mechanical backer of docs/design/requirement-map.md.
#
#   mix release.candidate
#
# Asserts, from live project state (never a frozen copy that could drift):
#
# 1. Requirement-map completeness, two directions:
#    - every test-case description under test/architecture/ has a
#      `### case: "<description>"` entry;
#    - every step of the LIVE `quality` alias (read from mix.exs) has an
#      `### alias: <step>` entry;
#    - the named conformance-lane entries exist;
#    - every entry carries a fenced `red` block with a command line and a
#      failure-marker line (a fence of green output reds the check).
# 2. Exactly one normative document: spec/protocol.md exists, is declared
#    in package.files, is in the package-boundary allowlist inside
#    package_boundary_test.exs, and no second copy lives at docs/.
# 3. The specification is coupled to the shipped implementation: every
#    facade function name, every registry namespace, and the corpus digest +
#    case total from priv/conformance/index.json must appear in it, as
#    must the non-authorizing stance.
# 4. The release identity chain (priv/release-metadata.json) matches live
#    state on every field: specification digest over the working-tree
#    spec/ files, package version, corpus and registry digests, corpus
#    index hash, verifier runtime, and the archive-authorization flag.
#    The file is never trusted — every link is re-derived and compared.
#
# A missing or vacuous entry, any specification drift, or a broken
# identity-chain link is a hard failure.

Code.require_file("release_identity.exs", __DIR__)

defmodule AgentBlueprintProtocol.ReleaseCandidateCheck do
  # Citation payloads are runtime-concatenated so this script's own source
  # stays citation-clean (the repo-side citation gate scans scripts/);
  # the planted scratch files still receive the real numerals.
  @citation_probe "0" <> "016"

  @map_path "docs/design/requirement-map.md"
  @protocol_path "spec/protocol.md"

  # A red fence must contain a command line and at least one line that can
  # only come from a failing run. Markers are output-shaped (ExUnit
  # prefixes, gate failure phrases); plain prose words are deliberately
  # absent — the fence must quote failing OUTPUT, not describe the gate.
  # EXIT= must be nonzero (checked by regex) and "Result: n/m passed"
  # counts are compared (n < m) — green output never satisfies a fence.
  @failure_markers [
    "** (Mix)",
    "1) test",
    "code:",
    "violation",
    "Retired",
    "unexpected",
    "drift",
    "survived",
    "did not expect",
    "Compilation failed",
    "Coverage test failed",
    "declared but unemitted",
    "not seen",
    "carve-out is read-only",
    "Break"
  ]

  @reprove_plants [
    %{
      name: "publish-guard-toolpath-plant",
      path: "README.md",
      from: "and [`NOTICE`](NOTICE).\n",
      to:
        "and [`NOTICE`](NOTICE).\n\nSee .kimo" <>
          "sabe/handoffs for design history.\n",
      command: ~w(mix test test/architecture/publish_guard_test.exs)
    },
    %{
      name: "spec-coverage-undocumented-fn",
      path: "lib/agent_blueprint_protocol/base64url.ex",
      from: "defmodule AgentBlueprintProtocol.Base64Url do\n",
      to: "defmodule AgentBlueprintProtocol.Base64Url do\n\n  def undoced_helper(x), do: x\n",
      command: ~w(mix test test/architecture/spec_coverage_test.exs)
    },
    %{
      name: "map-entry-removal",
      path: "docs/design/requirement-map.md",
      from: "### case: \"no shipped module/function/atom carries a version token\"\n",
      to: "### case: \"REMOVED-PROBE\"\n",
      command: ~w(mix release.candidate)
    },
    %{
      name: "protocol-doc-dropped-from-package",
      path: "mix.exs",
      from: "        \"spec/protocol.md\",\n        \"spec/README.md\",\n",
      to: "        \"spec/README.md\",\n",
      command: ~w(mix release.candidate)
    },
    # ---- per-case plants: every architecture case re-proven every run ----
    %{
      name: "cli-main-extra-defp",
      path: "lib/agent_blueprint_protocol/conformance/cli/main.ex",
      from: "  def main(argv), do: System.halt(Cli.run(argv))\nend\n",
      to:
        "  def main(argv), do: System.halt(Cli.run(argv))\n\n  defp planted_extra(x), do: x\nend\n",
      command: ~w(mix test test/architecture/cli_main_shape_test.exs)
    },
    %{
      name: "cli-main-block-body",
      path: "lib/agent_blueprint_protocol/conformance/cli/main.ex",
      from: "  def main(argv), do: System.halt(Cli.run(argv))\nend\n",
      to: "  def main(argv) do\n    code = Cli.run(argv)\n    System.halt(code)\n  end\nend\n",
      command: ~w(mix test test/architecture/cli_main_shape_test.exs)
    },
    %{
      name: "digest-xor-band-swap",
      path: "lib/agent_blueprint_protocol/digest.ex",
      from: "Bitwise.bor(Bitwise.bxor(a, b), acc)",
      to: "Bitwise.bor(Bitwise.band(a, b), acc)",
      command: ~w(mix test test/architecture/constant_time_compare_shape_test.exs)
    },
    %{
      name: "digest-equal-direct-compare",
      path: "lib/agent_blueprint_protocol/digest.ex",
      from: "byte_size(b1) == byte_size(b2) and a1 == a2 and xor_zero?(b1, b2, 0)",
      to: "byte_size(b1) == byte_size(b2) and a1 == a2 and b1 == b2",
      command: ~w(mix test test/architecture/constant_time_compare_shape_test.exs)
    },
    %{
      name: "deployment-validate-skip",
      path: "lib/agent_blueprint_protocol/deployment.ex",
      from:
        "    with {:ok, value} <- Canonicalization.verify(binary, bounds),\n         :ok <- Registry.validate(table(), value),\n         :ok <- scan(value, MapSet.new()),\n         :ok <- verify_content_digest(%__MODULE__{value: value}) do\n      {:ok, %__MODULE__{value: value}}\n    end\n  end\n\n  # The API type boundary \u2014 the never-raising posture at this clause too: a\n  # non-binary input denies :invalid_type instead of raising\n  # FunctionClauseError (the corpus floor's json surface fix, applied\n  # symmetrically to the artifact decoders).\n  def decode(_binary, _bounds), do: {:error, :invalid_type}\n\n  @doc \"\"\"\n  Validate an already-decoded tagged value (stages 2-3; no canonicality \u2014\n  there are no bytes, so the canonicality ordering obligation does not apply here).\n  For values that came from verified bytes, follow with\n  `verify_content_digest/1` \u2014 this function does NOT check the declared\n  digest. `opts` carries `:authored_extensions` \u2014 namespaces\n  whose critical bodies negotiation validated against a digest-pinned host\n  schema (the validated-extension channel). Those bodies skip the portability value-shape\n  heuristics; the channel is tied to THIS artifact's critical region, and\n  the default (`[]`) keeps the strict posture everywhere.\n  \"\"\"\n  @spec from_value(Json.value(), map()) :: {:ok, t()} | {:error, reason()}\n  def from_value(value, opts \\\\ %{}) when is_map(value) or is_tuple(value) do\n    validated = Map.get(opts, :authored_extensions, [])\n\n    with :ok <- authored_tied_to_value(value, validated),\n         :ok <- Registry.validate(table(), value),\n         :ok <- scan(value, MapSet.new(validated)) do\n      {:ok, %__MODULE__{value: value}}\n",
      to:
        "    with {:ok, value} <- Canonicalization.verify(binary, bounds),\n         :ok <- :ok,\n         :ok <- scan(value, MapSet.new()),\n         :ok <- verify_content_digest(%__MODULE__{value: value}) do\n      {:ok, %__MODULE__{value: value}}\n    end\n  end\n\n  # The API type boundary \u2014 the never-raising posture at this clause too: a\n  # non-binary input denies :invalid_type instead of raising\n  # FunctionClauseError (the corpus floor's json surface fix, applied\n  # symmetrically to the artifact decoders).\n  def decode(_binary, _bounds), do: {:error, :invalid_type}\n\n  @doc \"\"\"\n  Validate an already-decoded tagged value (stages 2-3; no canonicality \u2014\n  there are no bytes, so the canonicality ordering obligation does not apply here).\n  For values that came from verified bytes, follow with\n  `verify_content_digest/1` \u2014 this function does NOT check the declared\n  digest. `opts` carries `:authored_extensions` \u2014 namespaces\n  whose critical bodies negotiation validated against a digest-pinned host\n  schema (the validated-extension channel). Those bodies skip the portability value-shape\n  heuristics; the channel is tied to THIS artifact's critical region, and\n  the default (`[]`) keeps the strict posture everywhere.\n  \"\"\"\n  @spec from_value(Json.value(), map()) :: {:ok, t()} | {:error, reason()}\n  def from_value(value, opts \\\\ %{}) when is_map(value) or is_tuple(value) do\n    validated = Map.get(opts, :authored_extensions, [])\n\n    with :ok <- authored_tied_to_value(value, validated),\n         :ok <- :ok,\n         :ok <- scan(value, MapSet.new(validated)) do\n      {:ok, %__MODULE__{value: value}}\n",
      command: ~w(mix test test/architecture/deployment_engine_shape_test.exs)
    },
    %{
      name: "deployment-local-stage",
      path: "lib/agent_blueprint_protocol/deployment.ex",
      from: "defmodule AgentBlueprintProtocol.Deployment do\n",
      to:
        "defmodule AgentBlueprintProtocol.Deployment do\n\n  defp type_check(_value, _spec), do: :ok\n",
      command: ~w(mix test test/architecture/deployment_engine_shape_test.exs)
    },
    %{
      name: "federation-validate-skip",
      path: "lib/agent_blueprint_protocol/federation.ex",
      from:
        "    with {:ok, value} <- Canonicalization.verify(binary, bounds),\n         :ok <- Registry.validate(table(), value),\n         :ok <- scan(value) do\n      {:ok, %__MODULE__{value: value}}\n    else\n      {:error, %Error{} = error} -> {:error, error}\n      {:error, reason} -> {:error, %Error{code: reason, subject: []}}\n    end\n  end\n\n  def decode(_, _), do: {:error, %Error{code: :invalid_type, subject: [\"federation_envelope\"]}}\n\n  @doc \"\"\"\n  Validate an already-decoded tagged value (registry walk + portability\n  pass; no canonicality \u2014 there are no bytes). The codec reconstruction\n  path; values from the wire go through `decode/2`.\n  \"\"\"\n  @spec from_value(Json.value()) :: {:ok, t()} | {:error, Error.t()}\n  def from_value({:object, _} = value) do\n    with :ok <- bounded_shape(value),\n         :ok <- Registry.validate(table(), value),\n         :ok <- scan(value) do\n",
      to:
        "    with {:ok, value} <- Canonicalization.verify(binary, bounds),\n         :ok <- :ok,\n         :ok <- scan(value) do\n      {:ok, %__MODULE__{value: value}}\n    else\n      {:error, %Error{} = error} -> {:error, error}\n      {:error, reason} -> {:error, %Error{code: reason, subject: []}}\n    end\n  end\n\n  def decode(_, _), do: {:error, %Error{code: :invalid_type, subject: [\"federation_envelope\"]}}\n\n  @doc \"\"\"\n  Validate an already-decoded tagged value (registry walk + portability\n  pass; no canonicality \u2014 there are no bytes). The codec reconstruction\n  path; values from the wire go through `decode/2`.\n  \"\"\"\n  @spec from_value(Json.value()) :: {:ok, t()} | {:error, Error.t()}\n  def from_value({:object, _} = value) do\n    with :ok <- bounded_shape(value),\n         :ok <- :ok,\n         :ok <- scan(value) do\n",
      command: ~w(mix test test/architecture/federation_shape_test.exs)
    },
    %{
      name: "federation-local-stage",
      path: "lib/agent_blueprint_protocol/federation.ex",
      from: "defmodule AgentBlueprintProtocol.Federation do\n",
      to:
        "defmodule AgentBlueprintProtocol.Federation do\n\n  defp type_check(_value, _spec), do: :ok\n",
      command: ~w(mix test test/architecture/federation_shape_test.exs)
    },
    %{
      name: "federation-mapping-field-drift",
      path: "lib/agent_blueprint_protocol/federation.ex",
      from:
        "{1, \"task_identity\", \"Task.id (a2a.proto:170)\", \"Task.taskId (mcp-schema.ts:47)\", :native},",
      to:
        "{1, \"task_identity_drift\", \"Task.id (a2a.proto:170)\", \"Task.taskId (mcp-schema.ts:47)\", :native},",
      command: ~w(mix test test/architecture/federation_shape_test.exs)
    },
    %{
      name: "federation-verdict-drift",
      path: "lib/agent_blueprint_protocol/federation.ex",
      from:
        "{1, \"task_identity\", \"Task.id (a2a.proto:170)\", \"Task.taskId (mcp-schema.ts:47)\", :native},",
      to:
        "{1, \"task_identity\", \"Task.id (a2a.proto:170)\", \"Task.taskId (mcp-schema.ts:47)\", :partial},",
      command: ~w(mix test test/architecture/federation_shape_test.exs)
    },
    %{
      name: "federation-blank-transport",
      path: "lib/agent_blueprint_protocol/federation.ex",
      from:
        "{1, \"task_identity\", \"Task.id (a2a.proto:170)\", \"Task.taskId (mcp-schema.ts:47)\", :native},",
      to: "{1, \"task_identity\", \"\", \"Task.taskId (mcp-schema.ts:47)\", :native},",
      command: ~w(mix test test/architecture/federation_shape_test.exs)
    },
    %{
      name: "facade-decode-returns-error",
      path: "lib/agent_blueprint_protocol.ex",
      from:
        "  def decode_federation_envelope(bytes, bounds \\\\ Bounds.maximum()),\n    do: Federation.decode(bytes, bounds)\n",
      to:
        "  def decode_federation_envelope(bytes, bounds \\\\ Bounds.maximum()),\n    do: {:error, %AgentBlueprintProtocol.Error{code: :planted}}\n",
      command: ~w(mix test test/architecture/federation_shape_test.exs)
    },
    %{
      name: "facade-decode-ignores-bounds",
      path: "lib/agent_blueprint_protocol.ex",
      from:
        "  def decode_federation_envelope(bytes, bounds \\\\ Bounds.maximum()),\n    do: Federation.decode(bytes, bounds)\n",
      to:
        "  def decode_federation_envelope(bytes, _bounds \\\\ Bounds.maximum()),\n    do: Federation.decode(bytes, Bounds.maximum())\n",
      command: ~w(mix test test/architecture/federation_shape_test.exs)
    },
    %{
      name: "federation-rim-accepts-nonbinary",
      path: "lib/agent_blueprint_protocol/federation.ex",
      from:
        "  def decode(_, _), do: {:error, %Error{code: :invalid_type, subject: [\"federation_envelope\"]}}\n",
      to: "  def decode(_, _), do: {:ok, %__MODULE__{value: :planted}}\n",
      command: ~w(mix test test/architecture/federation_shape_test.exs)
    },
    %{
      name: "facade-mapping-empty",
      path: "lib/agent_blueprint_protocol.ex",
      from: "  def federation_mapping, do: Federation.mapping()\n",
      to: "  def federation_mapping, do: []\n",
      command: ~w(mix test test/architecture/federation_shape_test.exs)
    },
    %{
      name: "error-vocab-open-set",
      path: "lib/agent_blueprint_protocol/base64url.ex",
      from: "defmodule AgentBlueprintProtocol.Base64Url do\n",
      to:
        "defmodule AgentBlueprintProtocol.Base64Url do\n\n  def planted_vocab_probe, do: {:error, :planted_undeclared}\n",
      command: ~w(mix test test/architecture/error_vocabulary_gate_test.exs)
    },
    %{
      name: "error-vocab-dead-code",
      path: "lib/agent_blueprint_protocol/error.ex",
      from: "    :unknown_member,\n",
      to: "    :unknown_member,\n    :planted_dead_code,\n",
      command: ~w(mix test test/architecture/error_vocabulary_gate_test.exs)
    },
    %{
      name: "error-vocab-ceiling-key",
      path: "lib/agent_blueprint_protocol/error.ex",
      from: "  def ceiling_keys, do: @ceiling_keys\n",
      to: "  def ceiling_keys, do: [:planted_key | @ceiling_keys]\n",
      command: ~w(mix test test/architecture/error_vocabulary_gate_test.exs)
    },
    %{
      name: "identifier-version-fn",
      path: "lib/agent_blueprint_protocol/base64url.ex",
      from: "defmodule AgentBlueprintProtocol.Base64Url do\n",
      to: "defmodule AgentBlueprintProtocol.Base64Url do\n\n  def v2_planted, do: :ok\n",
      command: ~w(mix test test/architecture/identifier_naming_test.exs)
    },
    %{
      name: "identifier-version-path",
      path: "lib/agent_blueprint_protocol/planted_v2.ex",
      create: "defmodule AgentBlueprintProtocol.PlantedV2 do\n  @moduledoc false\nend\n",
      command: ~w(mix test test/architecture/identifier_naming_test.exs)
    },
    %{
      name: "citation-numeral-plant",
      path: "test/property/evidence_property_test.exs",
      from: "  The Evidence record's host-owned non-establishment laws:\n",
      to:
        "  The Evidence record's host-owned non-establishment laws:\n\n# see #{@citation_probe}\n",
      command: ~w(mix test test/architecture/internal_citation_gate_test.exs)
    },
    %{
      name: "file-access-carveout-missing",
      path: "test/architecture/no_file_access_test.exs",
      from: "  @carve_out_beams [\n    \"Elixir.AgentBlueprintProtocol.Conformance.Cli.beam\",",
      to:
        "  @carve_out_beams [\n    \"Elixir.Planted.Missing.beam\",\n    \"Elixir.AgentBlueprintProtocol.Conformance.Cli.beam\",",
      command: ~w(mix test test/architecture/no_file_access_test.exs)
    },
    %{
      name: "file-access-file-call",
      path: "lib/agent_blueprint_protocol/base64url.ex",
      from: "defmodule AgentBlueprintProtocol.Base64Url do\n",
      to:
        "defmodule AgentBlueprintProtocol.Base64Url do\n\n  def planted_file_probe, do: File.exists?(\"x\")\n",
      command: ~w(mix test test/architecture/no_file_access_test.exs)
    },
    %{
      name: "file-access-carveout-write",
      path: "lib/agent_blueprint_protocol/conformance/cli/main.ex",
      from: "  def main(argv), do: System.halt(Cli.run(argv))\nend\n",
      to:
        "  def main(argv), do: System.halt(Cli.run(argv))\n\n  def planted_write_probe, do: File.write!(\"x\", \"y\")\nend\n",
      command: ~w(mix test test/architecture/no_file_access_test.exs)
    },
    %{
      name: "non-authorizing-identifier",
      path: "lib/agent_blueprint_protocol/base64url.ex",
      from: "defmodule AgentBlueprintProtocol.Base64Url do\n",
      to: "defmodule AgentBlueprintProtocol.Base64Url do\n\n  def authorize_planted, do: :ok\n",
      command: ~w(mix test test/architecture/non_authorizing_vocabulary_test.exs)
    },
    %{
      name: "quality-alias-step-drop",
      path: "mix.exs",
      from:
        "        \"hex.audit\",\n        \"deps.unlock --check-unused\",\n        \"deps.audit\",\n",
      to: "        \"hex.audit\",\n        \"deps.audit\",\n",
      command: ~w(mix test test/architecture/package_boundary_test.exs)
    },
    %{
      name: "package-files-entry-drop",
      path: "mix.exs",
      from: "        \"priv/conformance\",\n        \"priv/release-metadata.json\",\n",
      to: "        \"priv/conformance\",\n",
      command: ~w(mix test test/architecture/package_boundary_test.exs)
    },
    %{
      name: "archive-allowlist-drift",
      path: "test/architecture/package_boundary_test.exs",
      from: "    hex_metadata.config\n",
      to: "    hex_metadata.config\n    planted/extra.txt\n",
      command: ~w(mix test test/architecture/package_boundary_test.exs)
    },
    %{
      name: "publish-guard-missing-entry",
      path: "mix.exs",
      from: "        \"lib\",\n        \"priv/conformance\",\n",
      to: "        \"lib\",\n        \"priv/conformance\",\n        \"planted/nowhere\",\n",
      command: ~w(mix test test/architecture/publish_guard_test.exs)
    },
    %{
      name: "publish-guard-symlink-plant",
      path: "priv/conformance/vectors/planted_link.json",
      symlink: "../cases/blueprint-decode.json",
      command: ~w(mix test test/architecture/publish_guard_test.exs)
    },
    %{
      name: "publish-guard-untracked-archive-member",
      path: "lib/archive_tracking_probe.ex",
      create: "defmodule AgentBlueprintProtocol.ArchiveTrackingProbe do\nend\n",
      command: ~w(mix test test/architecture/publish_guard_test.exs)
    },
    %{
      name: "publish-guard-text-reference",
      path: "SECURITY.md",
      from: "reporting for `baselabs/agent_blueprint_protocol`. Do not open a public issue\n",
      to:
        "reporting for `baselabs/agent_blueprint_protocol`. Do not open a public issue\nTracker ticket #{@citation_probe} notes.\n",
      command: ~w(mix test test/architecture/publish_guard_test.exs)
    },
    %{
      name: "publish-guard-exemption-pin-plant",
      path: "test/architecture/publish_guard_test.exs",
      from: "    ~r/\\b(BAP|BARA)\\b/\n  ]\n",
      to: "    ~r/\\b(BAP|BARA)\\b/,\n    ~r/\\bExampleCommerce\\b/\n  ]\n",
      command: ~w(mix test test/architecture/publish_guard_test.exs)
    },
    %{
      name: "publish-guard-calibration-swap",
      path: "test/architecture/publish_guard_test.exs",
      from: "    planted = ~r/\\b(ExampleCommerce|ExamplePlatform)\\b/\n",
      to: "    planted = ~r/Zz9NoFixtureEver/\n",
      command: ~w(mix test test/architecture/publish_guard_test.exs)
    },
    %{
      name: "publish-guard-corpus-filter-swap",
      path: "test/architecture/publish_guard_test.exs",
      from: "Enum.filter(archive_files(), &String.ends_with?(&1, \".json\"))",
      to: "Enum.filter(archive_files(), &String.ends_with?(&1, \".md\"))",
      command: ~w(mix test test/architecture/publish_guard_test.exs)
    },
    %{
      name: "purity-app-mod",
      path: "mix.exs",
      from: "  def application do\n    [extra_applications: [:crypto]]\n",
      to:
        "  def application do\n    [mod: {AgentBlueprintProtocol.Application, []}, extra_applications: [:crypto]]\n",
      command: ~w(mix test --no-start test/architecture/purity_test.exs)
    },
    %{
      name: "purity-extra-app",
      path: "mix.exs",
      from: "    [extra_applications: [:crypto]]\n",
      to: "    [extra_applications: [:crypto, :ssl]]\n",
      command: ~w(mix test test/architecture/purity_test.exs)
    },
    %{
      name: "purity-prod-dep",
      path: "mix.exs",
      from: "      {:credo, \"~> 1.7\", only: [:dev, :test], runtime: false},\n",
      to:
        "      {:jason, \"~> 1.4\"},\n      {:credo, \"~> 1.7\", only: [:dev, :test], runtime: false},\n",
      command: ~w(mix test test/architecture/purity_test.exs)
    },
    %{
      name: "registry-domain-ref",
      path: "lib/agent_blueprint_protocol/registry.ex",
      from: "defmodule AgentBlueprintProtocol.Registry do\n",
      to:
        "defmodule AgentBlueprintProtocol.Registry do\n\n  def planted_domain_ref, do: AgentBlueprintProtocol.Blueprint.module_info()\n",
      command: ~w(mix test test/architecture/registry_engine_shape_test.exs)
    },
    %{
      name: "schema-frozen-set-drift",
      path: "lib/agent_blueprint_protocol/schema.ex",
      from: "defmodule AgentBlueprintProtocol.Schema do\n",
      to:
        "defmodule AgentBlueprintProtocol.Schema do\n\n  def planted_reach, do: AgentBlueprintProtocol.Blueprint.module_info()\n",
      command: ~w(mix test test/architecture/schema_shape_test.exs)
    },
    %{
      name: "schema-apply-reach",
      path: "lib/agent_blueprint_protocol/schema.ex",
      from: "defmodule AgentBlueprintProtocol.Schema do\n",
      to:
        "defmodule AgentBlueprintProtocol.Schema do\n\n  def planted_apply(m), do: apply(m, :module_info, [])\n",
      command: ~w(mix test test/architecture/schema_shape_test.exs)
    },
    %{
      name: "schema-census-selftest",
      path: "test/support/architecture_scan.exs",
      from:
        "  defp collect_remote({:apply, _arity}, _self, acc), do: [{:erlang, :apply} | acc]\n  defp collect_remote({:apply_last, _arity, _dealloc}, _self, acc), do: [{:erlang, :apply} | acc]\n",
      to:
        "  defp collect_remote({:apply, _arity}, _self, acc), do: acc\n  defp collect_remote({:apply_last, _arity, _dealloc}, _self, acc), do: acc\n",
      command: ~w(mix test test/architecture/schema_shape_test.exs)
    },
    %{
      name: "spec-coverage-unquote-fn",
      path: "lib/agent_blueprint_protocol/base64url.ex",
      from: "defmodule AgentBlueprintProtocol.Base64Url do\n",
      to:
        "defmodule AgentBlueprintProtocol.Base64Url do\n\n  for planted <- [:ok] do\n    def unquote(planted)(), do: planted\n  end\n",
      command: ~w(mix test test/architecture/spec_coverage_test.exs)
    },
    %{
      name: "spec-coverage-moduledoc-false",
      path: "lib/agent_blueprint_protocol/base64url.ex",
      from: "defmodule AgentBlueprintProtocol.Base64Url do\n  @moduledoc \"\"\"\n",
      to: "defmodule AgentBlueprintProtocol.Base64Url do\n  @moduledoc false\n",
      command: ~w(mix test test/architecture/spec_coverage_test.exs)
    },
    %{
      name: "verify-only-key-param",
      path: "lib/agent_blueprint_protocol/base64url.ex",
      from: "defmodule AgentBlueprintProtocol.Base64Url do\n",
      to:
        "defmodule AgentBlueprintProtocol.Base64Url do\n\n  def planted_key_probe(private_key), do: private_key\n",
      command: ~w(mix test test/architecture/verify_only_test.exs)
    },
    %{
      name: "verify-only-sign-source",
      path: "lib/agent_blueprint_protocol/base64url.ex",
      from: "defmodule AgentBlueprintProtocol.Base64Url do\n",
      to:
        "defmodule AgentBlueprintProtocol.Base64Url do\n\n  defp planted_sign, do: :crypto.sign(:eddsa, \"m\", \"k\", :sha256)\n",
      command: ~w(mix test test/architecture/verify_only_test.exs)
    },
    %{
      name: "verify-only-key-shape",
      path: "lib/agent_blueprint_protocol/base64url.ex",
      from: "defmodule AgentBlueprintProtocol.Base64Url do\n",
      to: "defmodule AgentBlueprintProtocol.Base64Url do\n\n  @secret :ok\n",
      command: ~w(mix test test/architecture/verify_only_test.exs)
    },
    %{
      name: "verify-only-sign-beam",
      path: "lib/agent_blueprint_protocol/base64url.ex",
      from: "defmodule AgentBlueprintProtocol.Base64Url do\n",
      to:
        "defmodule AgentBlueprintProtocol.Base64Url do\n\n  def planted_sign_public, do: :crypto.sign(:eddsa, \"m\", \"k\", :sha256)\n",
      command: ~w(mix test test/architecture/verify_only_test.exs)
    },
    %{
      name: "version-token-leading-weaken",
      path: "test/support/architecture_scan.exs",
      from: "    Regex.match?(~r/(^|_)v\\d/i, string) or\n",
      to: "    Regex.match?(~r/(^|_)v\\d{2}/i, string) or\n",
      command: ~w(mix test test/architecture/version_token_test.exs)
    },
    %{
      name: "version-token-overmatch",
      path: "test/support/architecture_scan.exs",
      from: "      Regex.match?(~r/[a-z0-9]V\\d/, string) or\n",
      to: "      Regex.match?(~r/[a-z0-9]/, string) or\n",
      command: ~w(mix test test/architecture/version_token_test.exs)
    },
    # Documentation-gate plants: anchors are version-independent (release
    # text mutates; these stable anchors and corruptions red the gates at
    # every future version without rotting the plant table).
    %{
      name: "currency-readme-stale-pin",
      path: "README.md",
      from: "    {:agent_blueprint_protocol,",
      to: "    {:stale_pin, \"~> 0.0.1\"},\n    {:agent_blueprint_protocol,",
      command: ~w(mix test test/architecture/documentation_currency_test.exs)
    },
    %{
      name: "currency-security-stale-row",
      path: "SECURITY.md",
      from: "| Version | Supported |\n| --- | --- |\n",
      to: "| Version | Supported |\n| --- | --- |\n| 0.0.x | no |\n",
      command: ~w(mix test test/architecture/documentation_currency_test.exs)
    },
    %{
      name: "currency-changelog-current-entry",
      path: "CHANGELOG.md",
      from:
        "# Changelog\n\nAll notable public changes to `agent_blueprint_protocol` are documented here.\n",
      to:
        "# Changelog\n\nAll notable public changes to `agent_blueprint_protocol` are documented here.\n\n## [0.0.0] — 1970-01-01\n\nstale placeholder\n",
      command: ~w(mix test test/architecture/documentation_currency_test.exs)
    },
    %{
      name: "currency-readme-stale-count",
      path: "README.md",
      from: "## Intended properties",
      to: "9999999998 tests of filler.\n\n## Intended properties",
      command: ~w(mix test test/architecture/documentation_currency_test.exs)
    },
    %{
      name: "citation-dangling-section",
      path: "README.md",
      from: "## Status\n",
      to: "## Status\n\ninternals §12 has more.\n",
      command: ~w(mix test test/architecture/document_citation_gate_test.exs)
    },
    %{
      name: "citation-dangling-link",
      path: "README.md",
      from: "## Status\n",
      to: "## Status\n\nSee [the note](docs/internals-note.md).\n",
      command: ~w(mix test test/architecture/document_citation_gate_test.exs)
    },
    %{
      name: "identity-chain-format-tamper",
      path: "priv/release-metadata.json",
      from: "\"format\":\"agent-blueprint-protocol-release-metadata\"",
      to: "\"format\":\"tampered-release-metadata\"",
      command: ~w(mix release.candidate)
    },
    %{
      name: "identity-chain-spec-digest-stale",
      path: "spec/README.md",
      from: "## Release identity chain\n",
      to: "## Release identity chain\n\nAn unrecorded post-certification edit.\n",
      command: ~w(mix release.candidate)
    },
    %{
      name: "spec-extraction-dangling-link",
      path: "spec/README.md",
      from: "## Extraction\n",
      to: "## Extraction\n\nSee [the map](../docs/design/requirement-map.md).\n",
      command: ~w(mix spec.extraction)
    },
    %{
      name: "currency-governance-stale-claim",
      path: "CONTRIBUTING.md",
      from: "## The verification battery\n",
      to: "## The verification battery\n\nWorks with agent_blueprint_protocol 0.1.0 and later.\n",
      command: ~w(mix test test/architecture/documentation_currency_test.exs)
    },
    %{
      name: "registry-twin-edit",
      path: "lib/agent_blueprint_protocol/extension_registry.ex",
      from: "owner: \"ExampleCommerce\",\n        criticality: :critical",
      to: "owner: \"ExampleCommerceX\",\n        criticality: :critical",
      command: ~w(mix registry.equality)
    },
    %{
      name: "grammar-cddl-mutation",
      path: "spec/grammar/blueprint.cddl",
      from: "  release_number: positive-integer",
      to: "  release_number: tstr",
      command: ~w(mix grammar.derivation)
    },
    %{
      name: "grammar-derived-hand-edit",
      path: "spec/grammar/derived/blueprint.schema.json",
      from: "\"blueprint_id\",",
      to: "\"blueprint_id_edited\",",
      command: ~w(mix grammar.derivation)
    },
    %{
      name: "spec-threat-untraceable-citation",
      path: "spec/protocol.md",
      from: "`tamper_meaningful_byte` `digest_mismatch`",
      to: "`tamper_meaningful_byte` `made_up_threat_class`",
      command: ~w(mix test test/architecture/spec_threat_traceability_test.exs)
    },
    %{
      name: "spec-grammar-member-rename",
      path: "spec/protocol.md",
      from: "| `blueprint_id` | 1 |",
      to: "| `blueprint_identity` | 1 |",
      command: ~w(mix test test/architecture/spec_member_grammar_test.exs)
    },
    %{
      name: "spec-error-row-drop",
      path: "spec/protocol.md",
      from: "| `unknown_member` | a member is outside the closed world |",
      to: "",
      command: ~w(mix test test/architecture/spec_member_grammar_test.exs)
    },
    %{
      name: "spec-language-keyword-strip",
      path: "spec/protocol.md",
      from: "caller SHOULD NOT read an Evidence record",
      to: "caller should not read an Evidence record",
      command: ~w(mix test test/architecture/spec_conformance_language_test.exs)
    },
    %{
      name: "spec-language-boilerplate-strip",
      path: "spec/protocol.md",
      from: "capitals, as shown here.",
      to: "capitals, as implied.",
      command: ~w(mix test test/architecture/spec_conformance_language_test.exs)
    },
    %{
      name: "spec-example-untagged-fence",
      path: "spec/protocol.md",
      from: "## 3. Bytes\n",
      to: "## 3. Bytes\n\n```json\n{\"unbound\": true}\n```\n",
      command: ~w(mix test test/architecture/spec_conformance_language_test.exs)
    },
    %{
      name: "spec-example-tampered-bytes",
      path: "spec/protocol.md",
      from: "## 3. Bytes\n",
      to: "## 3. Bytes\n\n```json corpus:blueprint-decode-valid\n{\"drifted\": true}\n```\n",
      command: ~w(mix test test/architecture/spec_conformance_language_test.exs)
    },
    %{
      name: "second-normative-document",
      path: "docs/protocol.md",
      create: "A stale second copy of the normative document.\n",
      command: ~w(mix release.candidate)
    }
  ]

  @reprove_copy_paths [
    ".formatter.exs",
    "README.md",
    "CHANGELOG.md",
    "CODE_OF_CONDUCT.md",
    "CONTRIBUTING.md",
    "LICENSE",
    "NOTICE",
    "SECURITY.md",
    "usage-rules.md",
    "conformance",
    "docs",
    "lib",
    "mix.exs",
    "mix.lock",
    "priv",
    "scripts",
    "spec",
    "test"
  ]

  @doc "The reprove plant table (list mode for batch tooling)."
  @spec plants() :: [map()]
  def plants, do: @reprove_plants

  def run do
    map_text = read!(@map_path)

    findings =
      map_completeness_findings(map_text) ++
        protocol_presence_findings() ++
        protocol_coupling_findings() ++
        identity_chain_findings()

    if findings != [] do
      raise """
      release candidate: FAILED

      #{Enum.join(findings, "\n")}
      """
    end

    # Recursion guard: the reprove baselines and plants run this same
    # command inside their scratches; the inner runs are static-only.
    if System.get_env("ABP_RC_REPROVE") == "off" do
      IO.puts(
        "release candidate: ok (requirement-map complete, protocol.md coupled, " <>
          "reprove SKIPPED — ABP_RC_REPROVE=off names an operator override, never a green claim)"
      )
    else
      reprove()

      count = length(@reprove_plants)

      IO.puts(
        "release candidate: ok (requirement-map complete, protocol.md coupled, reprove #{count}/#{count})"
      )
    end
  end

  # ---- 4. reprove: replant the decided-red acceptance mutations ----------
  #
  # The map's fences are verbatim historical evidence; this replants the
  # acceptance spine (the recorded decided-red plants) in scratch copies and
  # requires each to redden NOW — the evidence half of the map is therefore
  # not self-asserted for the core set. A plant whose command stays green
  # raises (the vacuous guard); the UNMUTATED command must first run green
  # in a clean scratch (baseline non-vacuity, cached per command).

  defp reprove do
    Enum.each(@reprove_plants, &reprove_plant/1)
    Enum.each(@reprove_plants, &IO.puts("reprove caught: #{&1.name}"))
  end

  defp reprove_plant(plant) do
    baseline_green!(plant.command)

    scratch = scratch_dir("reprove-#{plant.name}")

    File.mkdir_p!(scratch)

    try do
      Enum.each(@reprove_copy_paths, &copy_path(&1, scratch))
      File.ln_s!(Path.expand("../deps", __DIR__), Path.join(scratch, "deps"))
      copy_build(scratch)
      initialize_git_repo!(scratch)
      apply_plant!(Path.join(scratch, plant.path), plant)

      {output, status} =
        System.cmd(hd(plant.command), tl(plant.command),
          cd: scratch,
          stderr_to_stdout: true,
          env: [{"MIX_ENV", "test"}, {"ABP_RC_REPROVE", "off"}]
        )

      if status == 0 do
        raise "reprove survived: #{plant.name}\n#{output}"
      end
    after
      File.rm_rf!(scratch)
    end
  end

  defp baseline_green!(command) do
    key = {:rc_baseline_green, command}

    if Process.get(key) != :ok do
      scratch = scratch_dir("baseline")

      File.mkdir_p!(scratch)

      try do
        Enum.each(@reprove_copy_paths, &copy_path(&1, scratch))
        File.ln_s!(Path.expand("../deps", __DIR__), Path.join(scratch, "deps"))
        copy_build(scratch)
        initialize_git_repo!(scratch)

        {output, status} =
          System.cmd(hd(command), tl(command),
            cd: scratch,
            stderr_to_stdout: true,
            env: [{"MIX_ENV", "test"}, {"ABP_RC_REPROVE", "off"}]
          )

        if status != 0 do
          raise "reprove baseline not green: #{inspect(command)} exited #{status}\n#{output}"
        end

        Process.put(key, :ok)
      after
        File.rm_rf!(scratch)
      end
    end

    :ok
  end

  # Unpredictable scratch names: a predictable path in the world-writable
  # temp dir is a pre-planted-symlink hazard (mkdir_p succeeds through it).
  defp scratch_dir(label) do
    rand = Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
    Path.join(System.tmp_dir!(), "abp-rc-#{label}-#{rand}")
  end

  defp copy_path(relative, scratch) do
    source = Path.expand(Path.join("..", relative), __DIR__)
    target = Path.join(scratch, relative)
    File.mkdir_p!(Path.dirname(target))
    {:ok, _copied} = File.cp_r(source, target)
  end

  defp copy_build(scratch) do
    for env <- ~w(dev test) do
      source = Path.expand(Path.join(["..", "_build", env]), __DIR__)

      if File.dir?(source) do
        target = Path.join(scratch, "_build/#{env}")
        File.mkdir_p!(Path.dirname(target))
        {:ok, _} = File.cp_r(source, target)
      end
    end
  end

  defp initialize_git_repo!(scratch) do
    commands = [
      ["init", "--initial-branch=main"],
      ["config", "user.email", "release-candidate@example.invalid"],
      ["config", "user.name", "Release Candidate"],
      ["add", "--all"],
      ["commit", "-m", "baseline"]
    ]

    Enum.each(commands, fn args ->
      {_output, 0} = System.cmd("git", args, cd: scratch, stderr_to_stdout: true)
    end)
  end

  # A plant is one of three ops: an exact-anchor text replacement (from/to),
  # the creation of a new file (create), or planting a symlink (symlink) —
  # the archive-symlink case needs a symlinked path, not content.
  defp apply_plant!(path, %{from: from, to: to}), do: mutate_once!(path, from, to)

  defp apply_plant!(path, %{create: contents}) do
    if File.exists?(path) do
      raise "reprove anchor is not exact: #{path} (create target already exists)"
    end

    File.mkdir_p!(Path.dirname(path))
    File.write!(path, contents)
  end

  defp apply_plant!(path, %{symlink: target}) do
    if File.exists?(path) do
      raise "reprove anchor is not exact: #{path} (symlink target already exists)"
    end

    File.mkdir_p!(Path.dirname(path))
    File.ln_s!(target, path)
  end

  defp mutate_once!(path, source, replacement) do
    contents = File.read!(path)

    if count(contents, source) != 1 do
      raise "reprove anchor is not exact: #{path}"
    end

    File.write!(path, String.replace(contents, source, replacement))
  end

  defp count(contents, source) do
    length(:binary.matches(contents, source))
  end

  # ---- 1. map completeness -------------------------------------------------------

  defp map_completeness_findings(map_text) do
    architecture_cases =
      for file <- Path.wildcard("test/architecture/*_test.exs"),
          desc <- test_descriptions(file) do
        {file, desc}
      end

    alias_steps =
      Mix.Project.config()[:aliases][:quality]
      |> Enum.map(&to_string/1)

    expected =
      Enum.map(architecture_cases, fn {file, desc} -> {:case, desc, Path.basename(file)} end) ++
        Enum.map(alias_steps, fn step -> {:alias, step, step} end) ++
        [
          {:conformance, "conformance: corpus loader integrity", "conformance.verify"},
          {:conformance, "conformance: runner agreement + report determinism",
           "verifier.agreement"}
        ]

    missing =
      for {kind, name, _binding} <- expected,
          not map_has_entry?(map_text, kind, name) do
        "requirement-map: missing entry for #{kind}: #{inspect(name)}"
      end

    vacuous =
      for {kind, name, _binding} <- expected,
          map_has_entry?(map_text, kind, name),
          not entry_has_red_fence?(map_text, kind, name) do
        "requirement-map: entry #{kind}: #{inspect(name)} has no valid red fence " <>
          "(a fenced ```red block with a command line and a failure line)"
      end

    unbound =
      for {kind, name, binding} <- expected,
          map_has_entry?(map_text, kind, name),
          not entry_fence_bound?(map_text, kind, name, binding) do
        "requirement-map: entry #{kind}: #{inspect(name)} red fence does not run " <>
          "its own gate (expected #{inspect(binding)} in the command)"
      end

    missing ++ vacuous ++ unbound
  end

  defp map_has_entry?(map_text, kind, name) do
    Regex.match?(anchored_header_regex(kind, name), map_text)
  end

  # Headers match as whole lines (multiline-anchored): an entry header
  # embedded inside another entry's body cannot piggyback that entry's
  # existence or fence.
  defp anchored_header_regex(kind, name) do
    body =
      case kind do
        :case -> "### case: \"#{name}\""
        :alias -> "### alias: #{name}"
        :conformance -> "### #{name}"
      end

    ~r/^#{Regex.escape(body)}$/m
  end

  defp entry_has_red_fence?(map_text, kind, name) do
    body = entry_body(map_text, kind, name)
    fences = red_fences(body)

    Enum.any?(fences, fn fence ->
      lines = String.split(fence, "\n")
      has_command = Enum.any?(lines, &command_line?/1)
      has_failure = Enum.any?(lines, &failure_line?/1)
      has_command and has_failure
    end)
  end

  # Every fence in the entry must be command-bound: its command line names
  # the entry's own gate (the test file for cases, the task for aliases) —
  # a fence copy-pasted from another gate reds.
  defp entry_fence_bound?(map_text, kind, name, binding) do
    body = entry_body(map_text, kind, name)

    Enum.any?(red_fences(body), fn fence ->
      fence
      |> String.split("\n")
      |> Enum.any?(&(command_line?(&1) and String.contains?(&1, binding)))
    end)
  end

  # The entry's section runs from its header line to the next header line.
  defp entry_body(map_text, kind, name) do
    case Regex.split(anchored_header_regex(kind, name), map_text, parts: 2) do
      [_before, rest] ->
        rest
        |> String.split(~r/^### /m, parts: 2)
        |> hd()

      [_] ->
        ""
    end
  end

  defp red_fences(body) do
    ~r/```red\n(.*?)```/s
    |> Regex.scan(body)
    |> Enum.map(fn [_, fence] -> fence end)
  end

  defp command_line?(line) do
    stripped = String.trim_trailing(line)
    String.starts_with?(stripped, "$ ") or String.starts_with?(stripped, "mix ")
  end

  defp failure_line?(line) do
    Enum.any?(@failure_markers, &String.contains?(line, &1)) or
      Regex.match?(~r/EXIT=[1-9]/, line) or
      partial_result?(line)
  end

  # "Result: 1/2 passed" is failing output; "Result: 2/2 passed" is green
  # and must NOT satisfy the vacuity guard — the counts are compared.
  defp partial_result?(line) do
    case Regex.run(~r/Result: (\d+)\/(\d+) passed/, line) do
      [_, failed, total] -> String.to_integer(failed) < String.to_integer(total)
      nil -> false
    end
  end

  defp test_descriptions(path) do
    source = read!(path)

    ~r/\btest\s+"((?:[^"\\]|\\.)*)"/s
    |> Regex.scan(source)
    |> Enum.map(fn [_, desc] -> desc end)
  end

  # ---- 2. exactly one normative document -------------------------------------------

  defp protocol_presence_findings do
    findings = []

    findings =
      if File.exists?(@protocol_path) do
        findings
      else
        ["release candidate: #{@protocol_path} does not exist" | findings]
      end

    findings =
      if File.exists?("docs/protocol.md") do
        [
          "release candidate: docs/protocol.md exists — the normative " <>
            "document is #{@protocol_path}; a second copy reds"
          | findings
        ]
      else
        findings
      end

    files = Mix.Project.config()[:package][:files] || []

    findings =
      if @protocol_path in files do
        findings
      else
        ["release candidate: #{@protocol_path} missing from package.files" | findings]
      end

    boundary_test = read!("test/architecture/package_boundary_test.exs")

    if String.contains?(boundary_test, @protocol_path) do
      findings
    else
      [
        "release candidate: #{@protocol_path} missing from the package-boundary allowlists"
        | findings
      ]
    end
  end

  # ---- 3. protocol.md coupling ---------------------------------------------------

  defp protocol_coupling_findings do
    # A missing protocol.md raises in read! below — fail-closed; the
    # presence finding names it cleanly for the message.
    protocol = read!(@protocol_path)

    facade_functions =
      AgentBlueprintProtocol.__info__(:functions)
      |> Enum.map(fn {name, _arity} -> Atom.to_string(name) end)
      |> Enum.uniq()

    namespaces =
      AgentBlueprintProtocol.ExtensionRegistry.registered_extensions()
      |> Enum.map(& &1.namespace)

    index = read!("priv/conformance/index.json")
    digest = extract_json_string(index, "corpus_digest")
    total = extract_json_number(index, "total_cases")

    # A missing or unparseable corpus-identity field is a finding, not a
    # silent skip — the coupling check must not degrade quietly.
    corpus_field_findings =
      for {field, value} <- [corpus_digest: digest, total_cases: total], value == "" do
        "protocol.md coupling: corpus index field #{inspect(field)} missing or unparseable"
      end

    empty_registry =
      if namespaces == [] do
        ["protocol.md coupling: registered_extensions() is empty — namespace coupling is vacuous"]
      else
        []
      end

    drift =
      [
        {:facade_function, facade_functions},
        {:registry_namespace, namespaces},
        {:corpus_identity, [digest]}
      ]
      |> Enum.flat_map(fn {label, required} ->
        for item <- required,
            is_binary(item),
            item != "",
            not documented?(protocol, label, item) do
          "protocol.md drift: #{label} #{inspect(item)} not documented in #{@protocol_path}"
        end
      end)

    # The case total couples as a word-bounded "N cases" phrase, not a
    # bare number that any substring satisfies.
    total_finding =
      if total != "" and not Regex.match?(~r/\b#{total} cases\b/, protocol) do
        ["protocol.md drift: corpus total #{total} not stated as \"#{total} cases\""]
      else
        []
      end

    empty_registry ++ corpus_field_findings ++ drift ++ total_finding ++ stance_finding(protocol)
  end

  defp stance_finding(protocol) do
    if String.contains?(String.downcase(protocol), "non-authorizing") do
      []
    else
      ["protocol.md drift: the non-authorizing stance is not stated"]
    end
  end

  # Minimal JSON field extraction over the flat index header (the corpus
  # loader itself remains the integrity authority; this is doc coupling).
  defp extract_json_string(json, key) do
    case Regex.run(~r/"#{key}"\s*:\s*"([^"]+)"/, json) do
      [_, value] -> value
      _ -> ""
    end
  end

  defp extract_json_number(json, key) do
    case Regex.run(~r/"#{key}"\s*:\s*(\d+)/, json) do
      [_, value] -> value
      _ -> ""
    end
  end

  # Facade functions must appear as name/arity tokens ("negotiate/2");
  # namespaces and digests as exact substrings.
  defp documented?(protocol, :facade_function, name), do: String.contains?(protocol, "#{name}/")
  defp documented?(protocol, _label, item), do: String.contains?(protocol, item)

  # ---- 4. release identity chain ------------------------------------------
  #
  # priv/release-metadata.json pins the release identity: the
  # specification digest, package version, corpus/registry digests, the
  # corpus index hash, the verifier runtime floor, and the
  # archive-authorization stance. Every field is re-derived from live
  # state by the shared ReleaseIdentity derivations and compared — the
  # file is never trusted (a tampered, stale, or unexpected field reds).
  # This chain is what certifies that the specification and its evidence
  # co-version.

  defp identity_chain_findings do
    expected = AgentBlueprintProtocol.ReleaseIdentity.expected_metadata()
    metadata_path = AgentBlueprintProtocol.ReleaseIdentity.metadata_path()

    if File.exists?(metadata_path) do
      actual = Jason.decode!(read!(metadata_path))

      mismatched =
        for field <- Enum.sort(Map.keys(expected)),
            Map.get(actual, field) != expected[field] do
          "identity chain: #{field} is #{inspect(Map.get(actual, field))} — " <>
            "the live value is #{inspect(expected[field])}"
        end

      unexpected =
        for field <- Enum.sort(Map.keys(actual) -- Map.keys(expected)) do
          "identity chain: unexpected field #{inspect(field)} in #{metadata_path}"
        end

      mismatched ++ unexpected
    else
      ["identity chain: #{metadata_path} is missing"]
    end
  end

  defp read!(path) do
    if File.exists?(path) do
      File.read!(path)
    else
      raise "release candidate: required file missing: #{path}"
    end
  end
end

# Operator list mode: print the plant table (one JSON object per line)
# and exit WITHOUT running any check — used by batch verification tooling
# and for eyeballing the reprove inventory. NEVER a green claim: the exit
# code is a distinct 3, so a wrapping gate cannot mistake a listing for a
# passed check (fail-closed, matching ABP_RC_REPROVE=off's named-skip rule).
# There is deliberately NO load-without-running mode: the shared
# derivations live in release_identity.exs, so every other entry into
# this file runs the check.
if System.get_env("ABP_RC_LIST_PLANTS") == "1" do
  Enum.each(AgentBlueprintProtocol.ReleaseCandidateCheck.plants(), fn plant ->
    IO.puts(Jason.encode!(plant))
  end)

  System.halt(3)
else
  AgentBlueprintProtocol.ReleaseCandidateCheck.run()
end
