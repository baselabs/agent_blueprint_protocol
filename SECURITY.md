# Security policy

## Supported versions

| Version | Supported |
| --- | --- |
| 1.0.0-rc.1 | yes |
| 1.0.x | yes |
| 0.8.x | yes |
| 0.7.x | no — upgrade to the current line |
| 0.6.x | no — upgrade to the current line |
| 0.5.x | no — upgrade to the current line |
| 0.4.x | no — upgrade to the current line |
| 0.3.x | no — upgrade to the current line |
| 0.2.x | no — upgrade to the current line |
| 0.1.x | no — upgrade to the current line |

The release candidate is unreleased. The 1.0 line and the 0.8 transition
line receive security fixes. See the [stability policy](documentation/stability.md).
Reports are acknowledged and handled as promptly as the maintainer can;
there is no guaranteed response time.

## Reporting a vulnerability

Report privately through GitHub: open the repository's
[Security tab](https://github.com/baselabs/agent_blueprint_protocol/security)
and choose **Report a vulnerability**
([direct link](https://github.com/baselabs/agent_blueprint_protocol/security/advisories/new)).
Do not open a public issue containing an exploit, credential, private key,
production data, tenant data, or unreleased vulnerability detail.

A report should identify the affected commit or package version, the violated
protocol property, a minimal value-free reproduction, and the expected
fail-closed result.

## Security boundary

This package validates structural protocol facts. It does not discover trust,
hold keys, issue or revoke grants, evaluate live authorization, reserve replay,
execute tools, own effects, or decide product policy. Consuming hosts
must treat every successful result as non-authorizing evidence.
