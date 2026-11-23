# 0030: Scratch Git maintenance

Status: Accepted

## Context

Git commands can start detached automatic maintenance that continues writing after the command returns. Removing a temporary repository can race those writes.

## Decision

Scratch Git repositories initialize through the shared scratch helper with `maintenance.auto=false` and `gc.auto=0` before commands that can trigger maintenance. Repository replicas and privacy checks use the same initialization. The architecture gate checks initialization ownership and maintenance settings across scripts and tests.

## Consequences

Scratch cleanup owns the complete repository lifetime without a detached maintenance writer. This setting applies to temporary test repositories and does not change contributor repository maintenance.
