# Host integration

This guide is for developers who consume protocol artifacts in an application. You will learn where reconciliation ends and where the host's work begins.

Call `AgentBlueprintProtocol.reconcile/3` with a Blueprint, a Deployment Manifest, and host-supplied inputs. Reconciliation checks the artifacts and returns an Evidence record or a typed error.

The host supplies its supported protocol revisions, bounds, public keys, and any observations used by the checks. A successful result describes protocol checks. It does not make the host's local decisions.

## Set decoder bounds

Decoder bounds limit the size and complexity of JSON input. This example lowers the depth limit. In a Mix project that depends on the package, run:

```elixir
{:ok, profile} = AgentBlueprintProtocol.Bounds.new(%{depth: 32})
profile.depth # => 32
```

## Read the result

Read typed checks and the nonempty `not_verified` list before using a result. The [reading evidence guide](reading-evidence.md) explains the fields and forward-compatible matching pattern.

Handle denials by matching their `code` and `subject`. The [error guide](handling-errors.md) describes the Error record and common responses.

## Next steps

- [Read evidence](reading-evidence.md)
- [Handle errors](handling-errors.md)
- [Verify in CI](verifying-in-ci.md)
