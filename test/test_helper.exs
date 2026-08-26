Code.require_file("support/architecture_scan.exs", __DIR__)
Code.require_file("support/blueprint_fixture.exs", __DIR__)
Code.require_file("support/deployment_fixture.exs", __DIR__)
Code.require_file("support/federation_fixture.exs", __DIR__)

# The actual registered-test count, recorded at every suite end. The
# documentation-currency gate compares README's claim against BOTH the
# source census (macro count) and this number: a generated test block
# (runtime tests from one macro) makes the two disagree LOUDLY. The
# quality battery runs the full suite before any gate reads this file,
# so its value under `mix quality` is always the full-tree count; an
# isolated partial run leaves a partial count that the next full run
# overwrites.
ExUnit.after_suite(fn stats ->
  Path.expand("../.test_census", __DIR__)
  |> File.write!(to_string(stats.total))
end)

ExUnit.start()
