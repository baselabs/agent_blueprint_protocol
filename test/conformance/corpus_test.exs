defmodule AgentBlueprintProtocol.Conformance.CorpusTest do
  @moduledoc """
  The conformance corpus loader: every integrity check, each proven able to
  RED on its own tampered map (the corpus acceptance line + its design note).
  Fixtures come from `ConformanceTest.Builder`, which authors floor-valid
  corpora exactly as the shipped corpus is authored.
  """

  use ExUnit.Case, async: true

  alias AgentBlueprintProtocol.Conformance.Corpus
  alias AgentBlueprintProtocol.ConformanceTest.Builder
  alias AgentBlueprintProtocol.{Error, Json}

  defp minimal, do: Builder.build(Builder.minimal_cases())

  defp deny(map, code, subject) do
    assert {:error, %Error{code: ^code, subject: ^subject}} = Corpus.load(map)
  end

  defp replace_required(cases, surface, class, replacement) do
    idx =
      Enum.find_index(cases, &(&1["surface"] == surface and &1["class"] == class))

    List.replace_at(cases, idx, replacement)
  end

  describe "a floor-valid corpus loads" do
    test "the minimal 90-cell corpus returns the loaded struct" do
      assert length(Builder.minimal_cases()) == 90
      assert {:ok, %Corpus{}} = Corpus.load(minimal())
    end

    test "the loaded corpus carries its recomputed identity" do
      assert {:ok, %Corpus{identity: identity}} = Corpus.load(minimal())
      assert is_binary(identity) and String.starts_with?(identity, "sha-256:")
    end
  end

  describe "index integrity" do
    test "a non-map input denies :corpus_index_invalid" do
      deny(:not_a_map, :corpus_index_invalid, ["index"])
    end

    test "a missing index.json denies :corpus_index_invalid" do
      deny(Map.delete(minimal(), "index.json"), :corpus_index_invalid, ["index"])
    end

    test "a stale corpus_digest member denies :corpus_index_invalid" do
      tampered =
        Builder.update_index(
          minimal(),
          fn index ->
            Map.put(index, "corpus_digest", "sha-256:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA")
          end,
          redigest: false
        )

      deny(tampered, :corpus_index_invalid, ["index", "corpus_digest"])
    end

    test "a stale registry_digest denies :corpus_index_invalid" do
      tampered =
        Builder.update_index(minimal(), fn index ->
          Map.put(index, "registry_digest", "sha-256:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA")
        end)

      deny(tampered, :corpus_index_invalid, ["index", "registry_digest"])
    end

    test "non-canonical index bytes deny :corpus_index_invalid" do
      # Trailing whitespace is valid JSON but not the canonical bytes the
      # digest is taken over — the file and the digest must not be able to
      # drift apart.
      padded = Map.fetch!(minimal(), "index.json") <> " "
      assert {:ok, _} = Json.decode(padded)
      deny(Map.put(minimal(), "index.json", padded), :corpus_index_invalid, ["index"])
    end
  end

  describe "file-set integrity (both directions)" do
    test "a removed declared file denies :corpus_file_set_mismatch" do
      map = minimal()
      path = map |> Map.keys() |> Enum.reject(&(&1 == "index.json")) |> hd()
      deny(Map.delete(map, path), :corpus_file_set_mismatch, ["index", "files"])
    end

    test "an unlisted extra file denies :corpus_file_set_mismatch" do
      deny(Map.put(minimal(), "cases/rogue.json", "{}"), :corpus_file_set_mismatch, [
        "index",
        "files"
      ])
    end
  end

  describe "per-file hash integrity" do
    test "a flipped case-file hash denies :corpus_hash_mismatch" do
      tampered =
        Builder.update_index(minimal(), fn index ->
          files =
            Enum.map(index["files"], fn
              %{"path" => "cases/json-decode.json"} = entry ->
                Map.put(entry, "sha256_base64url", "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA")

              entry ->
                entry
            end)

          Map.put(index, "files", files)
        end)

      deny(tampered, :corpus_hash_mismatch, ["index", "files"])
    end
  end

  describe "count integrity" do
    test "a wrong total_cases denies :corpus_count_mismatch" do
      tampered = Builder.update_index(minimal(), &Map.put(&1, "total_cases", 999))
      deny(tampered, :corpus_count_mismatch, ["index", "total_cases"])
    end

    test "a wrong per-file count denies :corpus_count_mismatch" do
      tampered =
        Builder.update_index(minimal(), fn index ->
          files =
            Enum.map(index["files"], fn
              %{"path" => "cases/json-decode.json"} = entry ->
                Map.put(entry, "cases", 999)

              entry ->
                entry
            end)

          Map.put(index, "files", files)
        end)

      deny(tampered, :corpus_count_mismatch, ["index", "total_cases"])
    end
  end

  describe "case-id uniqueness" do
    test "a duplicated case id denies :corpus_case_id_duplicate" do
      dupe = Enum.find(Builder.minimal_cases(), &(&1["surface"] == "json.decode"))
      deny(Builder.build(Builder.minimal_cases() ++ [dupe]), :corpus_case_id_duplicate, ["cases"])
    end
  end

  describe "case validity" do
    test "an undecodable-but-hash-matching case file denies :corpus_case_invalid" do
      tampered = Builder.resync_file(minimal(), "cases/json-decode.json", "not json at all")
      deny(tampered, :corpus_case_invalid, ["cases"])
    end

    test "a tamper whose verbatim bytes disagree with the derivation denies" do
      # canonicalization.encode is the surface whose floor REQUIRES
      # tamper_meaningful_byte; the base occupies its required valid cell.
      base = %{
        "id" => "canonicalization-encode-tamper-base",
        "surface" => "canonicalization.encode",
        "class" => "valid",
        "input" => %{"text" => "{\"a\":1}"},
        "expected" => %{"verdict" => "valid", "encoded" => "{\"a\":1}"}
      }

      lying = %{
        "id" => "canonicalization-encode-tamper-byte",
        "surface" => "canonicalization.encode",
        "class" => "tamper_meaningful_byte",
        # The verbatim artifact is NOT the base with byte 5 flipped by 9.
        "input" => %{"text" => "{\"b\":8}"},
        "expected" => %{"verdict" => "invalid", "code" => "non_canonical_bytes"},
        "tamper" => %{
          "base_case" => "canonicalization-encode-tamper-base",
          "byte_index" => 5,
          "xor" => 9
        }
      }

      cases =
        Builder.minimal_cases()
        |> replace_required("canonicalization.encode", "valid", base)
        |> replace_required("canonicalization.encode", "tamper_meaningful_byte", lying)

      deny(Builder.build(cases), :corpus_case_invalid, ["cases", "tamper"])
    end

    test "a well-formed tamper loads (the derivation agrees with the verbatim bytes)" do
      base = %{
        "id" => "canonicalization-encode-tamper-base",
        "surface" => "canonicalization.encode",
        "class" => "valid",
        "input" => %{"text" => "{\"a\":1}"},
        "expected" => %{"verdict" => "valid", "encoded" => "{\"a\":1}"}
      }

      # `{"a":1}` byte 5 is the '1'; xor 9 flips 0x31 -> 0x38 ('8').
      honest = %{
        "id" => "canonicalization-encode-tamper-byte",
        "surface" => "canonicalization.encode",
        "class" => "tamper_meaningful_byte",
        "input" => %{"text" => "{\"a\":8}"},
        "expected" => %{"verdict" => "valid", "encoded" => "{\"a\":8}"},
        "tamper" => %{
          "base_case" => "canonicalization-encode-tamper-base",
          "byte_index" => 5,
          "xor" => 9
        }
      }

      cases =
        Builder.minimal_cases()
        |> replace_required("canonicalization.encode", "valid", base)
        |> replace_required("canonicalization.encode", "tamper_meaningful_byte", honest)

      assert {:ok, _} = Corpus.load(Builder.build(cases))
    end
  end

  describe "applicability totality (the compiled-in floor)" do
    test "a required cell declared n_a denies :corpus_applicability_incomplete" do
      tampered =
        Builder.update_index(minimal(), fn index ->
          put_in(index, ["applicability", "json.decode", "valid"], %{"n_a" => "because"})
        end)

      deny(tampered, :corpus_applicability_incomplete, ["index", "applicability"])
    end

    test "a missing leaf denies :corpus_applicability_incomplete" do
      tampered =
        Builder.update_index(minimal(), fn index ->
          leaves = Map.delete(index["applicability"]["json.decode"], "valid")
          put_in(index, ["applicability", "json.decode"], leaves)
        end)

      deny(tampered, :corpus_applicability_incomplete, ["index", "applicability"])
    end

    test "a declared count disagreeing with the executed count denies" do
      tampered =
        Builder.update_index(minimal(), fn index ->
          put_in(index, ["applicability", "json.decode", "valid"], 99)
        end)

      deny(tampered, :corpus_applicability_incomplete, ["index", "applicability"])
    end

    test "an n_a cell with an executed case denies" do
      stray = %{
        "id" => "stray-n-a-case",
        "surface" => "json.decode",
        "class" => "signature_invalid",
        "input" => %{},
        "expected" => %{"verdict" => "invalid", "code" => "invalid_type"}
      }

      deny(Builder.build(Builder.minimal_cases() ++ [stray]), :corpus_applicability_incomplete, [
        "index",
        "applicability"
      ])
    end

    test "a surface keyset drift denies" do
      tampered =
        Builder.update_index(minimal(), fn index ->
          app =
            index["applicability"] |> Map.delete("bounds.new") |> Map.put("rogue.surface", %{})

          Map.put(index, "applicability", app)
        end)

      deny(tampered, :corpus_applicability_incomplete, ["index", "applicability"])
    end

    test "an n_a cell without a reason denies" do
      tampered =
        Builder.update_index(minimal(), fn index ->
          put_in(index, ["applicability", "json.decode", "signature_invalid"], "n_a")
        end)

      deny(tampered, :corpus_applicability_incomplete, ["index", "applicability"])
    end
  end

  describe "vacuous green" do
    test "a zero-case corpus denies :corpus_empty" do
      deny(Builder.build([]), :corpus_empty, ["index", "total_cases"])
    end
  end

  describe "raw sidecars" do
    test "a lying case reference to a sidecar denies :corpus_case_invalid" do
      good = %{
        "id" => "signature-verify-valid",
        "surface" => "signature.verify",
        "class" => "valid",
        "input" => %{"raw_file" => "raw/key.raw", "sha256_base64url" => "definitely-not-it"},
        "expected" => %{"verdict" => "valid", "encoded" => "{\"a\":1}"}
      }

      cases =
        Builder.minimal_cases()
        |> replace_required("signature.verify", "valid", good)

      deny(Builder.build(cases, %{"raw/key.raw" => <<1, 2, 3>>}), :corpus_case_invalid, ["cases"])
    end
  end

  describe "structure, files, and data arms (the remaining integrity branches)" do
    test "a scalar index denies :corpus_index_invalid" do
      deny(Map.put(minimal(), "index.json", "123"), :corpus_index_invalid, ["index"])
    end

    test "each malformed structure member denies with its subject" do
      for {fun, subject} <- [
            {fn i -> Map.put(i, "format", "wrong") end, ["index"]},
            {fn i -> Map.put(i, "protocol_revision", 0) end, ["index"]},
            {fn i -> Map.put(i, "total_cases", "x") end, ["index", "total_cases"]},
            {fn i -> Map.put(i, "public_key_fingerprints", 5) end, ["index"]},
            {fn i -> Map.put(i, "registry_digest", 7) end, ["index", "registry_digest"]},
            {fn i -> Map.put(i, "applicability", []) end, ["index", "applicability"]}
          ] do
        tampered = Builder.update_index(minimal(), fun)
        deny(tampered, :corpus_index_invalid, subject)
      end

      # A non-binary corpus_digest member (redigest off so it survives).
      tampered =
        Builder.update_index(
          minimal(),
          &Map.put(&1, "corpus_digest", 8),
          redigest: false
        )

      deny(tampered, :corpus_index_invalid, ["index", "corpus_digest"])
    end

    test "a malformed file entry and a disallowed path deny" do
      for fun <- [
            fn i -> update_file(i, "cases/json-decode.json", &Map.delete(&1, "cases")) end,
            fn i ->
              update_file(i, "cases/json-decode.json", &Map.put(&1, "path", "evil.json"))
            end
          ] do
        deny(Builder.update_index(minimal(), fun), :corpus_index_invalid, ["index", "files"])
      end
    end

    test "schemas/ and vectors/ data files load as hash-bound non-case data" do
      data = %{
        "schemas/simple.schema.json" => %{
          "type" => "object",
          "float_tail" => 1.5,
          "bool_tail" => true,
          "null_tail" => nil
        },
        "vectors/manifest.json" => %{"rows" => [1, "two", 3.5, false, nil]}
      }

      map = Builder.build(Builder.minimal_cases(), %{}, data: data)
      assert {:ok, %Corpus{data: loaded}} = Corpus.load(map)
      assert Map.get(loaded, "schemas/simple.schema.json")["float_tail"] == 1.5
    end

    test "an undecodable data file denies :corpus_case_invalid" do
      map = Builder.build(Builder.minimal_cases(), %{}, data: %{"schemas/x.json" => %{}})

      deny(Builder.resync_file(map, "schemas/x.json", "not json"), :corpus_case_invalid, ["cases"])
    end

    test "a case file with no format member denies :corpus_case_invalid" do
      tampered = Builder.resync_file(minimal(), "cases/json-decode.json", "{}")
      deny(tampered, :corpus_case_invalid, ["cases"])
    end

    test "an index carrying extra scalar-typed members loads (canonical round-trip)" do
      tampered =
        Builder.update_index(minimal(), fn index ->
          index
          |> Map.put("float_extra", 1.5)
          |> Map.put("bool_extra", true)
          |> Map.put("null_extra", nil)
        end)

      assert {:ok, _} = Corpus.load(tampered)
    end

    defp update_file(index, path, fun) do
      files =
        Enum.map(index["files"], fn
          %{"path" => ^path} = entry -> fun.(entry)
          entry -> entry
        end)

      Map.put(index, "files", files)
    end
  end

  describe "tamper target resolution (the addressed artifact)" do
    defp with_tamper(base_id, base_input, id, input, tamper, expected_ok?) do
      cases =
        Builder.minimal_cases()
        |> replace_required("canonicalization.encode", "valid", %{
          "id" => base_id,
          "surface" => "canonicalization.encode",
          "class" => "valid",
          "input" => base_input,
          "expected" => %{"verdict" => "valid", "encoded" => "{\"a\":1}"}
        })
        |> replace_required("canonicalization.encode", "tamper_meaningful_byte", %{
          "id" => id,
          "surface" => "canonicalization.encode",
          "class" => "tamper_meaningful_byte",
          "input" => input,
          "expected" => %{"verdict" => "valid", "encoded" => "{\"a\":1}"},
          "tamper" => tamper
        })

      result = Corpus.load(Builder.build(cases))
      if expected_ok?, do: match?({:ok, _}, result), else: match?({:error, _}, result)
    end

    test "explicit targets resolve input.text and input.base64url" do
      assert with_tamper(
               "t-base",
               %{"text" => "{\"a\":1}"},
               "t-text",
               %{"text" => "{\"a\":9}"},
               %{
                 "base_case" => "t-base",
                 "byte_index" => 5,
                 "xor" => 8,
                 "target" => "input.text"
               },
               true
             )

      assert with_tamper(
               "t-base2",
               %{"base64url" => Base.url_encode64("{\"a\":1}", padding: false)},
               "t-b64",
               %{"base64url" => Base.url_encode64("{\"a\":9}", padding: false)},
               %{
                 "base_case" => "t-base2",
                 "byte_index" => 5,
                 "xor" => 8,
                 "target" => "input.base64url"
               },
               true
             )
    end

    test "an unknown target, a missing member, and bad base64 deny" do
      refute with_tamper(
               "u-base",
               %{"text" => "{\"a\":1}"},
               "u-target",
               %{"text" => "zzz"},
               %{"base_case" => "u-base", "byte_index" => 5, "xor" => 8, "target" => "input.zzz"},
               true
             )

      refute with_tamper(
               "u-base2",
               %{"text" => "{\"a\":1}"},
               "u-missing",
               %{"text" => "zzz"},
               %{
                 "base_case" => "u-base2",
                 "byte_index" => 5,
                 "xor" => 8,
                 "target" => "input.text"
               },
               true
             )

      refute with_tamper(
               "u-base3",
               %{"base64url" => "QQ"},
               "u-default",
               %{"text" => "zzz"},
               %{"base_case" => "u-base3", "byte_index" => 0, "xor" => 1},
               true
             )
    end

    test "the input.entry target resolves signature entries (and misses absent keys)" do
      base_entry = %{
        "id" => "sig-base",
        "surface" => "signature.verify",
        "class" => "valid",
        "input" => %{"entry" => "ABC"},
        "expected" => %{"verdict" => "valid", "encoded" => "{\"a\":1}"}
      }

      good =
        Builder.minimal_cases()
        |> replace_required("signature.verify", "valid", base_entry)
        |> replace_required("signature.verify", "tamper_meaningful_byte", %{
          "id" => "sig-t-target",
          "surface" => "signature.verify",
          "class" => "tamper_meaningful_byte",
          "input" => %{"entry" => "ABD"},
          "expected" => %{"verdict" => "valid", "encoded" => "{\"a\":1}"},
          "tamper" => %{
            "base_case" => "sig-base",
            "byte_index" => 2,
            "xor" => 7,
            "target" => "input.entry"
          }
        })

      assert {:ok, _} = Corpus.load(Builder.build(good))

      bad =
        Builder.minimal_cases()
        |> replace_required("signature.verify", "valid", base_entry)
        |> replace_required("signature.verify", "tamper_meaningful_byte", %{
          "id" => "sig-t-miss",
          "surface" => "signature.verify",
          "class" => "tamper_meaningful_byte",
          "input" => %{"entry" => "ABD"},
          "expected" => %{"verdict" => "valid", "encoded" => "{\"a\":1}"},
          "tamper" => %{
            "base_case" => "sig-base",
            "byte_index" => 2,
            "xor" => 7,
            "target" => "input.absent"
          }
        })

      deny(Builder.build(bad), :corpus_case_invalid, ["cases", "tamper"])
    end

    test "a base carrying no bytes denies the default resolution" do
      refute with_tamper(
               "n-base",
               %{},
               "n-tamper",
               %{"text" => "zzz"},
               %{"base_case" => "n-base", "byte_index" => 0, "xor" => 1},
               true
             )
    end
  end

  test "a tamper base whose base64url member is not decodable denies" do
    cases =
      Builder.minimal_cases()
      |> replace_required("canonicalization.encode", "valid", %{
        "id" => "b-base",
        "surface" => "canonicalization.encode",
        "class" => "valid",
        "input" => %{"base64url" => "!!"},
        "expected" => %{"verdict" => "valid", "encoded" => "{\"a\":1}"}
      })
      |> replace_required("canonicalization.encode", "tamper_meaningful_byte", %{
        "id" => "b-tamper",
        "surface" => "canonicalization.encode",
        "class" => "tamper_meaningful_byte",
        "input" => %{"base64url" => Base.url_encode64("zz", padding: false)},
        "expected" => %{"verdict" => "valid", "encoded" => "{\"a\":1}"},
        "tamper" => %{
          "base_case" => "b-base",
          "byte_index" => 0,
          "xor" => 1,
          "target" => "input.base64url"
        }
      })

    deny(Builder.build(cases), :corpus_case_invalid, ["cases", "tamper"])
  end

  test "a case referencing an absent sidecar denies :corpus_case_invalid" do
    cases =
      Builder.minimal_cases()
      |> replace_required("signature.verify", "valid", %{
        "id" => "sig-valid",
        "surface" => "signature.verify",
        "class" => "valid",
        "input" => %{"raw_file" => "raw/absent.raw", "sha256_base64url" => "zz"},
        "expected" => %{"verdict" => "valid", "encoded" => "{\"a\":1}"}
      })

    deny(Builder.build(cases), :corpus_case_invalid, ["cases"])
  end

  describe "the floor itself" do
    test "is the pinned design commitment: 16 surfaces x 31 classes, 90 required cells" do
      floor = Corpus.floor()
      assert map_size(floor) == 16
      assert length(Corpus.surfaces()) == 16
      assert length(Corpus.classes()) == 31
      assert MapSet.new(Corpus.surfaces()) == MapSet.new(Map.keys(floor))

      required = floor |> Enum.map(fn {_s, %{required: r}} -> length(r) end) |> Enum.sum()
      assert required == 90
    end

    test "every surface carries its falsifiable n_a reason" do
      for {_surface, %{n_a: reason}} <- Corpus.floor() do
        assert is_binary(reason) and reason != ""
      end
    end
  end
end
