# The grammar-derivation gate: the CDDL grammars under spec/grammar/
# are the normative machine-readable grammar; the JSON Schema files
# under spec/grammar/derived/ are DERIVED from them (never hand-edited)
# and the corpus golden artifacts must validate against the derived
# schemas.
#
#   mix grammar.derivation            # verify: re-derive + compare + corpus goldens
#   mix grammar.derivation --write    # regenerate the derived files (then commit)
#
# Three findings red the gate:
#   1. a derived file that does not byte-match a fresh derivation
#      (hand-edit, or the CDDL mutated);
#   2. a corpus golden (valid case or golden vector) that fails
#      validation under a derived schema — the grammars are pinned to
#      the corpus;
#   3. an unparseable or dangling CDDL construct (unknown rule name,
#      unsupported syntax) — the parser is total and fail-closed.
#
# The CDDL subset is deliberately disciplined (RFC 8610 §3): rules,
# group maps, `?` member occurrence, `[n*m item]` arrays, string
# enums and literal members, choices between map arms (oneOf),
# `integer .gt 0`, and the primitive names tstr/integer/bool/null/any.
# Anything outside the subset denies, so the grammar files cannot grow
# constructs the derivation silently mishandles.

Code.require_file("grammar_derivation.exs", __DIR__)

write? = System.argv() == ["--write"] or System.get_env("ABP_GRAMMAR_WRITE") == "1"
AgentBlueprintProtocol.GrammarDerivation.run(write?)
