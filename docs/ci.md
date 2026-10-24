# Continuous Integration (GitHub Actions)

CI is defined in [`.github/workflows/ci.yml`](../.github/workflows/ci.yml). It is **verification only**: it does not deploy, push images, or use any cloud credentials.

## Triggers

| Event | Condition |
| :--- | :--- |
| `pull_request` | Targeting `main` |
| `push` | To `main` |
| `workflow_dispatch` | Manual run from the **Actions** tab |

Superseded runs on a pull request are cancelled automatically. Runs on `main` are never cancelled.

## Job structure

Two independent jobs run in parallel. Dependencies are installed once in `verify` (the Docker job builds inside its own images, so it does not need `node_modules`).

```
verify (Node 22, 20 min timeout)            docker-build (matrix: backend | storefront, 30 min timeout)
  Gate 1  npm ci                              Gate 6  docker compose config --quiet
  Gate 2  backend tsc                                 docker compose build <service>
  Gate 3  storefront tsc
  Gate 4  turbo lint
  Gate 5  turbo test
```

## Gates

| # | Step | Command (from repo root unless noted) | What it catches |
| :-: | :--- | :--- | :--- |
| 1 | Install | `npm ci --no-audit --no-fund` | `package.json` and `package-lock.json` out of sync; unresolvable deps |
| 2 | Backend TypeScript | `cd apps/backend && npx tsc --noEmit --incremental false` | Type errors in the Medusa backend |
| 3 | Storefront TypeScript | `cd apps/storefront && npx tsc --noEmit --incremental false` | Type errors in the Next.js storefront |
| 4 | Lint | `npx turbo lint` | ESLint errors (`medusa lint` for backend, `eslint .` for storefront). Warnings do not fail the build |
| 5 | Unit tests | `npx turbo test --force` | Failing backend (Jest) and storefront (Node test script) tests |
| 6 | Docker builds | `docker compose --env-file .env.docker.example build <service>` | Broken Dockerfiles, bad build contexts, failing `npm ci`/`medusa build`/`next build` inside images |

Notes:

- `--incremental false` keeps `tsc` from reading or writing the tracked `apps/storefront/tsconfig.tsbuildinfo`.
- `--force` bypasses the Turborepo cache so tests always run.
- Node 22 is used because the project requires `>=22.22.0` (`engines`) and the Dockerfiles use `node:22-slim`.
- The tests are self-contained: they need **no PostgreSQL, no Redis, no `.env` file and no network**. The backend suite imports route handlers and a pure helper; the storefront suite tests pure utilities. Integration tests (`test:integration:*`) exist as scripts but are **not** run in CI.
- Docker builds use the tracked `.env.docker.example`, which contains placeholder values only. Images are built but never started or pushed.

## Run the same checks locally

```bash
npm ci
(cd apps/backend && npx tsc --noEmit --incremental false)
(cd apps/storefront && npx tsc --noEmit --incremental false)
npx turbo lint
npx turbo test --force
docker compose --env-file .env.docker.example config --quiet
docker compose --env-file .env.docker.example build backend
docker compose --env-file .env.docker.example build storefront
```

PowerShell: replace the subshell lines with `Push-Location apps/backend; npx tsc --noEmit --incremental false; Pop-Location` (and the same for `apps/storefront`).

> `npm ci` deletes and recreates `node_modules`. Do not run it while a local dev server is using them.

To reproduce CI most faithfully, run inside a clean Node 22 container, because local Node/npm versions may differ from CI.

## Inspect a failed run

1. Open the repository's **Actions** tab, select the **CI** workflow, then the failing run.
2. Open the red job (`verify`, or `Gate 6: Docker build (backend|storefront)`).
3. Expand the first red step; the failing command and its output are there. Later steps are skipped after a failure.
4. Use **Re-run failed jobs** after pushing a fix, or **Re-run all jobs**.
5. Docker failures show BuildKit output; search for `ERROR` to find the failing Dockerfile step.

## Reproduce common failures

| Symptom | Likely cause | Reproduce / fix |
| :--- | :--- | :--- |
| Gate 1 `npm ci` fails with "lock file out of sync" | `package.json` changed without updating the lockfile | Run `npm install`, commit `package-lock.json`, then `npm ci` locally |
| Gate 2/3 TypeScript error | New type error | Run the `tsc` command for that workspace locally |
| Gate 4 lint error | ESLint rule violation | `npx turbo lint`; fix the code rather than disabling the rule |
| Gate 5 failing test | Regression | `npm test --workspace=@dtc/backend` or `npm test --workspace=@dtc/storefront` |
| Gate 5 "No tests found" | Test file moved/renamed, or `testMatch` no longer matches | Backend tests must match `src/**/__tests__/**/*.unit.spec.[jt]s` |
| Gate 6 compose config error | A required `${VAR:?}` has no value in `.env.docker.example` | Add the variable (placeholder value only) to `.env.docker.example` |
| Gate 6 image build fails | Dockerfile or build-context change | Run the same `docker compose ... build <service>` command locally |

## Current limitations

- **Storefront test script lists one file explicitly** (`apps/storefront/package.json`). New storefront test files must be added to that script or they will not run.
- **No coverage reporting** and no minimum coverage threshold.
- **Test depth is minimal**: backend covers two trivial route handlers and one helper; storefront covers `medusaError` and `isEmpty`. Cart and checkout flows are **not** covered by automated tests.
- **No integration or end-to-end tests** and no container start/health check in CI. Docker jobs only prove the images build.
- **No Docker layer cache** between runs, so image builds are slow (several minutes). Caching needs `docker/setup-buildx-action`, which was intentionally not added.
- **No dependency audit gate.** `npm audit --omit=dev` still reports transitive advisories pinned inside `@medusajs/*@2.22.0` (see `docs/docker.md`), so an audit gate would fail until upstream updates.
- **Lint warnings are not enforced** (~27 `react-hooks` warnings in the storefront).
- **Only Node 22 on Linux** is tested.
- Actions are pinned to commit SHAs and will not update automatically. Consider enabling Dependabot for `github-actions` in a later phase.
