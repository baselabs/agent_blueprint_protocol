# Security policy

## Supported versions

| Version | Supported |
| --- | --- |
| 0.2.x | yes |
| 0.1.x | no — upgrade to the current line |

## Reporting a vulnerability

Use GitHub private vulnerability
reporting for `baselabs/agent_blueprint_protocol`. Do not open a public issue
containing an exploit, credential, private key, production data, tenant data, or
unreleased vulnerability detail.

A report should identify the affected commit or package version, the violated
protocol property, a minimal value-free reproduction, and the expected
fail-closed result.

## Security boundary

This package will validate structural protocol facts. It will not discover
trust, hold keys, issue or revoke grants, evaluate live authorization, reserve
replay, execute tools, own effects, or decide product policy. Consuming hosts
must treat every successful result as non-authorizing evidence.
