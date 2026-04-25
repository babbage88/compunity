# infractl Web API Plan

## Goal

Expose the deployment-oriented `infractl` workflows over HTTP so other projects can call the same core logic currently reached through Cobra. The target architecture is the same pattern used by the certificate service: shared request/result contracts and execution live in `infra-core`, while `go-infra` owns the HTTP routes and swagger-facing wrappers. `infra-cli` remains a CLI adapter and should not own the web API surface for these deployment endpoints.

## Design Direction

- Keep Cobra as the CLI adapter, not the core business logic.
- Move shared request and result contracts into `infra-core` when they are stable enough to be consumed by multiple modules.
- Move command execution logic behind callable Go functions that accept request structs and return result structs plus errors.
- Make HTTP handlers non-interactive. Missing required values should return validation errors instead of invoking TUI prompts.
- Prefer asynchronous jobs for long-running deployment operations once the first synchronous endpoints prove the shape.
- Avoid making `go-infra` import `infra-cli`; use `infra-core` for shared contracts and shared implementation to prevent module cycles.

## Module Roles

- `infra-core`: shared deployment/API types plus reusable orchestration callable from either app.
- `infra-cli`: CLI command adapters that call `infra-core`.
- `go-infra`: central API/service process that owns the HTTP routes, auth, and swagger surface while calling `infra-core`.

## First API Milestone

Add:

- Done: `GET /api/v1/health`
- Done in `go-infra`: `POST /api/v1/database/mariadb/install`
- Done in `go-infra`: `POST /api/v1/database/valkey/install`
- Done in `go-infra`: `POST /api/v1/proxy/{name}/install`
- Done in `go-infra`: `POST /api/v1/storage/s3/garage/node`
- Done in `go-infra`: `POST /api/v1/storage/s3/garage/token`
- Done in `go-infra`: `POST /api/v1/proxmox/vm/{vmid}/start`
- Done in `go-infra`: `GET /api/v1/proxmox/vm`

The proxy installer was the first target because the Cobra command already delegates to `deployer.RemoteWebProxyInstaller`, making it a clean path for proving the request/handler/service pattern. Garage S3 token creation followed because it returns useful structured credentials and has a similarly clean deployer-layer entry point.

## Endpoint Roadmap

- Done in `go-infra`: `POST /api/v1/deploy/systemd-app`
- Done in `go-infra`: `POST /api/v1/proxy/{name}/install`
- Done in `go-infra`: `POST /api/v1/database/postgres/app`
- Done in `go-infra`: `POST /api/v1/database/mariadb/install`
- Done in `go-infra`: `POST /api/v1/database/valkey/install`
- Done in `go-infra`: `POST /api/v1/storage/s3/garage/node`
- Done in `go-infra`: `POST /api/v1/storage/s3/garage/token`
- Done in `go-infra`: `POST /api/v1/proxmox/lxc`
- Done in `go-infra`: `POST /api/v1/proxmox/vm`
- Done in `go-infra`: `POST /api/v1/proxmox/vm/template`
- Done in `go-infra`: `POST /api/v1/proxmox/pve-user`
- Done in `go-infra`: `POST /api/v1/proxmox/api-token`
- Done in `go-infra`: `POST /api/v1/proxmox/vm/{vmid}/start`
- Done in `go-infra`: `GET /api/v1/proxmox/vm`

## Refactor Order

1. Done: Move proxy installers into `infra-core` and expose them from `go-infra`.
2. Done: Move Garage S3 token creation into `infra-core` and expose it from `go-infra`.
3. Done: Move Garage node deployment into `infra-core` and expose it from `go-infra`.
4. Done: Move Valkey and MariaDB remote installers into `infra-core` and expose them from `go-infra`.
   - Done: Valkey remote installer.
   - Done: MariaDB remote installer.
5. Done: Remote systemd app deployment.
6. Done: Proxmox VM/LXC operations.
   - Done: Proxmox user creation over SSH.
   - Done: Proxmox API token creation over SSH.
7. Done: PostgreSQL app database setup.

## Current State

- `infra-cli` no longer owns the deployment HTTP routes for proxy, MariaDB, Valkey, or Garage.
- `infra-cli` commands now call `infra-core/deployment` directly.
- `go-infra` owns these HTTP endpoints using thin wrapper handlers:
  - `POST /api/v1/database/mariadb/install`
  - `POST /api/v1/database/valkey/install`
  - `POST /api/v1/database/postgres/app`
  - `POST /api/v1/deploy/systemd-app`
  - `POST /api/v1/proxy/{name}/install`
  - `POST /api/v1/storage/s3/garage/node`
  - `POST /api/v1/storage/s3/garage/token`
  - `POST /api/v1/proxmox/lxc`
  - `POST /api/v1/proxmox/vm`
  - `POST /api/v1/proxmox/vm/template`
  - `POST /api/v1/proxmox/pve-user`
  - `POST /api/v1/proxmox/api-token`
- Swagger/client artifacts were refreshed so deployment request bodies now expose concrete fields instead of empty `{}` objects in generated consumers.
- The original endpoint migration roadmap is complete; remaining work should focus on hardening, testing, auth/permissions, and any later async job model.

## Job Model

The initial implementation can run synchronously. Before exposing the heavier commands broadly, add an in-memory job runner:

- `POST /api/v1/jobs/...`
- `GET /api/v1/jobs/{id}`
- `GET /api/v1/jobs/{id}/logs`

Later, `go-infra` can persist job state in Postgres and stream logs through the existing web API patterns.

## Security Notes

- Require authentication before exposing the API beyond localhost.
- Treat SSH passphrases, DB passwords, generated S3 secrets, and tokens as sensitive fields.
- Prefer `use_agent`, SSH config aliases, future secret references, or `private_key_base64`/`private_key_pem` over server-local `key_path` in HTTP requests.
- Avoid logging secrets in handler request bodies or service results.
- Require explicit confirmation fields for destructive operations such as database drops.
