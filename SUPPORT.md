# Support

Support is provided on a best-effort basis; there is no guaranteed response time.

- **Usage and design questions:** [GitHub Discussions](https://github.com/baselabs/agent_blueprint_protocol/discussions).
- **Product or third-party extension namespaces:** configure a host registration and held schema as shown in the [extensions guide](documentation/extensions.md); no upstream package change is required.
- **Protocol-owned registry changes:** use the [registry-request issue template](.github/ISSUE_TEMPLATE/registry_request.yml) and [registry operations process](spec/registry/OPERATIONS.md).
- **Bugs:** use the [bug-report template](.github/ISSUE_TEMPLATE/bug_report.yml).
- **Security:** the repository's Security tab, **Report a vulnerability**;
  see [`SECURITY.md`](SECURITY.md). Do not open a public issue for
  vulnerabilities.

The package is deliberately inert: it grants no authority and starts
nothing. Support questions about authorization, tenancy, or policy belong
to your host runtime, not this protocol. The [host-integration guide](documentation/host-integration.md)
describes that boundary.
