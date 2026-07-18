# Endevir Cloud public integration contract

This document defines the public boundary between the Apache-2.0 Endevir OSS
tooling and the separately operated Endevir Cloud service. Cloud implementation,
infrastructure, pricing, and operations are outside this repository.

## Principles

- Local test execution, trace generation, and HTML reports remain usable without a Cloud account.
- Cloud integration is opt-in and must not change local execution semantics.
- The CLI uploads only artifacts explicitly selected by the user.
- Authentication credentials and Cloud endpoints are configuration, not source-controlled defaults.
- Protocol and trace changes are versioned and remain backward compatible within a documented support window.

## Public responsibilities

### Endevir OSS

- Produce versioned trace and evidence artifacts.
- Validate artifacts before upload.
- Provide explicit Cloud authentication and submission commands.
- Display remote run identifiers, status, and actionable failures.
- Keep the transport boundary replaceable and testable without the hosted service.

### Endevir Cloud

- Accept supported artifact and protocol versions.
- Return stable run identifiers and machine-readable status.
- Preserve tenant isolation and protect uploaded evidence.
- Expose retention and deletion behavior to users.
- Report unsupported client versions without silently dropping tests.

## Planned command boundary

`endevir cloud run` is reserved for the opt-in upload, execution, and result
retrieval flow. Its request/response schema will be added to `schema/` before the
command is considered stable.

## Source of truth

- Public CLI and protocol behavior: this repository
- Trace schema: [`schema/`](../../schema/)
- Cloud product and infrastructure requirements: private `HyuCode/endevir-cloud`
