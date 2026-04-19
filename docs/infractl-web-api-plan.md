# infractl Web API Plan

## Goal

Expose the deployment-oriented `infractl` subcommands over HTTP so other projects can call the same core logic currently reached through Cobra. The short-term target is an `infractl api serve` command inside `infra-cli`; the longer-term target is a shared API surface that can be used by both `infra-cli` and `go-infra`.

## Design Direction

- Keep Cobra as the CLI adapter, not the core business logic.
- Move shared request and result contracts into `infra-core` when they are stable enough to be consumed by multiple modules.
- Move command execution logic behind callable Go functions that accept request structs and return result structs plus errors.
- Make HTTP handlers non-interactive. Missing required values should return validation errors instead of invoking TUI prompts.
- Prefer asynchronous jobs for long-running deployment operations once the first synchronous endpoints prove the shape.
- Avoid making `go-infra` import `infra-cli`; use `infra-core` for shared contracts or shared implementation to prevent module cycles.

## Module Roles

- `infra-core`: shared deployment/API types and eventually reusable orchestration that has no dependency on either app.
- `infra-cli`: CLI command adapters, local execution agent, and initial HTTP wrapper.
- `go-infra`: central API/service process that can later call `infra-core` directly or delegate execution to an `infractl` API worker.

## First API Milestone

Add:

- Done: `infractl api serve --listen-address :8181`
- Done: `GET /api/v1/health`
- Done: `POST /api/v1/proxy/{name}/install`
- Done: `POST /api/v1/storage/s3/garage/token`

The proxy installer was the first target because the Cobra command already delegates to `deployer.RemoteWebProxyInstaller`, making it a clean path for proving the request/handler/service pattern. Garage S3 token creation followed because it returns useful structured credentials and has a similarly clean deployer-layer entry point.

## Endpoint Roadmap

- `POST /api/v1/deploy/systemd-app`
- Done: `POST /api/v1/proxy/{name}/install`
- `POST /api/v1/database/postgres/app`
- `POST /api/v1/database/mariadb/install`
- `POST /api/v1/database/valkey/install`
- `POST /api/v1/storage/s3/garage/node`
- Done: `POST /api/v1/storage/s3/garage/token`
- `POST /api/v1/proxmox/lxc`
- `POST /api/v1/proxmox/vm`
- `POST /api/v1/proxmox/vm/template`
- `POST /api/v1/proxmox/vm/{vmid}/start`
- `GET /api/v1/proxmox/vm`

## Refactor Order

1. Done: Proxy installers.
2. Done: Garage S3 token creation.
3. Garage node deployment.
4. Valkey and MariaDB remote installers.
5. Remote systemd app deployment.
6. Proxmox VM/LXC operations.
7. PostgreSQL app database setup.

## Job Model

The initial implementation can run synchronously. Before exposing the heavier commands broadly, add an in-memory job runner:

- `POST /api/v1/jobs/...`
- `GET /api/v1/jobs/{id}`
- `GET /api/v1/jobs/{id}/logs`

Later, `go-infra` can persist job state in Postgres and stream logs through the existing web API patterns.

## Security Notes

- Require authentication before exposing the API beyond localhost.
- Treat SSH passphrases, DB passwords, generated S3 secrets, and tokens as sensitive fields.
- Avoid logging secrets in handler request bodies or service results.
- Require explicit confirmation fields for destructive operations such as database drops.
