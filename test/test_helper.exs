Code.require_file("support/scratch.exs", __DIR__)
Code.require_file("support/architecture_scan.exs", __DIR__)
Code.require_file("support/blueprint_fixture.exs", __DIR__)
Code.require_file("support/deployment_fixture.exs", __DIR__)
Code.require_file("support/ed25519_strict_fixture.exs", __DIR__)
Code.require_file("support/federation_fixture.exs", __DIR__)

Code.require_file("support/census_formatter.exs", __DIR__)

# The registered-test count, recorded at every suite end by the census
# formatter (doctests excluded, because the source macro census cannot
# count them). The release-candidate gate compares it with the source
# macro census: any other generated test block makes the two disagree
# loudly. The quality battery runs the full suite before any gate reads
# the file; an isolated partial run leaves a partial count that the next
# full run overwrites.
ExUnit.start(formatters: [ExUnit.CLIFormatter, AgentBlueprintProtocol.Test.CensusFormatter])
