# Medusa Ecommerce Monorepo â€” Docker Containerization & Orchestration

This document details the containerization, orchestration, service communication, and operational procedures for the Medusa ecommerce monorepo (Phase 2 DevOps implementation).

---

## 1. System Architecture & Service Communication

The application stack consists of four containerized services managed via Docker Compose under the isolated project namespace `ecomm-phase2`:

```
+---------------------------------------------------------------------------------------------------+
| Host Machine / Client Browser                                                                     |
|                                                                                                   |
|  Browser -> http://localhost:8001 (Storefront UI)                                                 |
|  Browser -> http://localhost:9001 (Medusa REST API / Admin)                                       |
+--------|-------------------------------------------------------|----------------------------------+
         | (Host port 8001)                                      | (Host port 9001)
         v                                                       v
+---------------------------------------------------------------------------------------------------+
| Docker Compose Isolated Bridge Network (`ecomm_phase2_network`)                                   |
|                                                                                                   |
|  +---------------------------+                +---------------------------+                       |
|  |   storefront              |  SSR / API     |   backend                 |                       |
|  |   (Next.js App Router)    | -------------> |   (Medusa v2 Application) |                       |
|  |   Port 8000               |  Internal HTTP |   Port 9000               |                       |
|  +---------------------------+  (backend:9000)+-------------|-------------+                       |
|                                                             |                                     |
|                                           PostgreSQL TCP    |    Redis TCP                        |
|                                           (postgres:5432)   |    (redis:6379)                     |
|                                                             v                                     |
|                               +-----------------------------+-----------------------------+       |
|                               |                                                           |       |
|                               v                                                           v       |
|                 +---------------------------+               +---------------------------+ |       |
|                 |   postgres                |               |   redis                   | |       |
|                 |   (PostgreSQL 16 Alpine)  |               |   (Redis 7 Alpine)        | |       |
|                 |   Port 5432 (Internal)    |               |   Port 6379 (Internal)    | |       |
|                 +-------------|-------------+               +-------------|-------------+ |       |
+-------------------------------|-------------------------------------------|-----------------------+
                                v                                           v
                 +---------------------------+               +---------------------------+
                 | Named Persistent Volume:  |               | Named Persistent Volume:  |
                 | `ecomm_phase2_postgres_   |               | `ecomm_phase2_redis_data` |
                 |  data`                    |               +---------------------------+
                 +---------------------------+
```

### Dual-Channel Communication Pattern

Storefront communication with Medusa uses a dual-channel pattern:

1. **Client-Side (Browser Execution)**:
   - The user's web browser runs on the host network.
   - It communicates with the backend via `NEXT_PUBLIC_MEDUSA_BACKEND_URL` (`http://localhost:9001` or `http://localhost:9000`).
2. **Server-Side (Next.js SSR, Server Actions, Middleware)**:
   - Next.js server components and middleware run inside the `storefront` container.
   - They communicate directly across the internal Docker bridge network via `MEDUSA_BACKEND_URL` (`http://backend:9000`).
   - This bypasses host loopback restrictions and ensures reliable SSR data fetching.

### Redis Architecture & Module Strategy

Medusa v2.22.0 leverages Redis for state management and background task execution when `REDIS_URL` is configured:
1. **HTTP Session Management**: Handled via `connect-redis` (`RedisStore`) configured directly from `projectConfig.redisUrl`, persisting `connect.sid` sessions under the `sess:` prefix.
2. **Distributed Event Bus**: Backed by `@medusajs/medusa/event-bus-redis` using BullMQ to queue and process domain events reliably across workers.
3. **Workflow Engine**: Backed by `@medusajs/medusa/workflow-engine-redis` using BullMQ to manage workflow state, step retries, timeouts, and asynchronous step execution.
4. **Architectural Trade-offs (Locking & Caching)**:
   - **Distributed Locking**: Uses Medusa v2's default in-memory locking (`@medusajs/medusa/locking`) for single-node backend deployment, avoiding external network lock overhead while PostgreSQL enforces row-level transactional integrity. When horizontally scaling to multiple backend replicas, `@medusajs/medusa/locking-postgres` or `@medusajs/medusa/locking-redis` can be enabled in `medusa-config.ts`.
   - **Caching**: Uses in-memory caching (`@medusajs/medusa/caching`) for low-latency in-process lookups, while Next.js App Router provides ISR/Data Cache tag revalidation (`revalidateTag`) at the HTTP boundary. Redis caching is omitted to avoid unnecessary serialization and network hops on fast read paths.
5. **Conditional Local Fallback**: In `apps/backend/medusa-config.ts`, the Redis event-bus and workflow-engine modules are conditionally loaded only when `process.env.REDIS_URL` is defined, allowing lightweight local non-Docker development without requiring a local Redis daemon while automatically activating full Redis backing inside Docker Compose and production.

### Next.js Build Output & Monorepo Architecture

The storefront Dockerfile uses a 3-stage build (`deps` -> `builder` -> `runner` on `node:22-slim`) running `npm run start` (`next start -p 8000`) rather than Next.js `output: "standalone"`:
- **Feasibility & Trade-offs**: In an npm workspaces monorepo (`apps/storefront` + root `node_modules` hoisting), Next.js standalone file tracing (`@vercel/nft`) outputs a nested directory structure (`.next/standalone/apps/storefront/server.js`) and requires manual copying of `.next/static` and `public` directories into the nested standalone tree, alongside potential edge cases with hoisted native bindings (`sharp`) and workspace symlinks.
- **Decision**: Multi-stage `node:22-slim` with `COPY --chown=node:node` and standard `next start` preserves 100% compatibility with Next.js 16.4.x App Router server actions, middleware, and monorepo hoisting without fragile post-build path restructuring.

### Development vs. Production Configuration & Secrets Strategy

Configuration is strictly separated by environment:

| Concern | Local Native Dev (`npm run dev`) | Local Docker (`compose.yaml` + `.env.docker`) | Production (CI/CD & Cloud Runtime) |
| :--- | :--- | :--- | :--- |
| **Environment Source** | `apps/backend/.env`, `apps/storefront/.env.local` | `.env.docker` (gitignored) | Platform Secret Manager / CI Secrets |
| **`COOKIE_SECURE`** | `false` (implicit via `NODE_ENV=development`) | `false` (explicit in `.env.docker` for HTTP localhost) | `true` (default in `compose.yaml` & `medusa-config.ts`) |
| **`DATABASE_SSL`** | `false` | `false` (internal Docker bridge network) | `true` (`rejectUnauthorized: true` for managed RDS/Postgres) |
| **Redis Modules** | Optional (in-memory fallback if `REDIS_URL` unset) | Active (`redis://redis:6379`) | Active (`rediss://...` managed Redis) |
| **Secrets Fallback** | Local dev placeholders | Fail-fast `${VAR:?error}` in `compose.yaml` | Fail-fast + injected from encrypted vault |

#### Production Secrets Strategy
1. **Zero Secrets in Git**: `.gitignore` and `.dockerignore` block `.env`, `.env.*`, `.env.local`, and `.env.docker`. Only `.env.docker.example` is tracked with non-sensitive placeholder strings.
2. **Fail-Fast Validation**: `compose.yaml` enforces `${POSTGRES_PASSWORD:?}`, `${JWT_SECRET:?}`, `${COOKIE_SECRET:?}`, and `${NEXT_PUBLIC_MEDUSA_PUBLISHABLE_KEY:?}` with no insecure default fallbacks.
3. **CI/CD & Runtime Injection**:
   - **GitHub Actions CI**: Store build-time and test variables in GitHub Actions Encrypted Secrets (`Settings -> Secrets and variables -> Actions`). Pass `NEXT_PUBLIC_MEDUSA_PUBLISHABLE_KEY` only as a Docker build argument (`--build-arg`), never baked into base layers or logged.
   - **Production Runtime**: Inject `DATABASE_URL`, `REDIS_URL`, `JWT_SECRET`, and `COOKIE_SECRET` at container runtime via AWS Secrets Manager / SSM Parameter Store, Docker Swarm Secrets, or Kubernetes `Secret` envFrom mounts. Generate `JWT_SECRET` and `COOKIE_SECRET` using at least 64 cryptographically random hex characters (`openssl rand -hex 32`).

### Startup, Shutdown, Health Checks & Recovery

1. **Deterministic Startup Order**:
   - `postgres` and `redis` start first and run `pg_isready` and `redis-cli ping` health checks (5s interval).
   - `backend` waits for both `postgres` and `redis` to report `service_healthy` before executing `docker-entrypoint.sh` (`npx medusa db:migrate` followed by `exec npx medusa start`).
   - `storefront` waits for `backend` to pass its HTTP `/health` check (`service_healthy`) before starting Next.js, ensuring `/store/regions` is reachable during initial requests.
2. **PID 1 Signal Handling & Graceful Shutdown**:
   - Both `backend` and `storefront` containers use `ENTRYPOINT ["dumb-init", "--", ...]` and `exec` to ensure `SIGTERM` and `SIGINT` signals from `docker stop` or orchestrators are forwarded directly to the Node.js process, allowing in-flight HTTP requests and database connections to close cleanly without a 10-second SIGKILL timeout.
3. **Automated Recovery**:
   - All four services configure `restart: unless-stopped` along with active container `HEALTHCHECK` definitions, allowing the Docker daemon to detect unhealthy states and recover services automatically while keeping `ecomm_phase2_postgres_data` and `ecomm_phase2_redis_data` volumes intact.

### Port Isolation & Conflict Protection

To protect existing host services (such as existing Postgres on 5432/5433, Redis on 6379, and existing local processes):
- **Database & Cache Ports**: Internal ports `5432` and `6379` are **not** exposed to the host by default. All communication occurs strictly within `ecomm_phase2_network`.
- **Backend Host Port**: Exposed on host port `9001` by default (mapped to container port `9000`).
- **Storefront Host Port**: Exposed on host port `8001` by default (mapped to container port `8000`).
- **Everyday Mode**: If local Node.js processes are stopped, set `MEDUSA_PORT=9000` and `STOREFRONT_PORT=8000` in `.env.docker` to use standard ports.

---

## 2. Prerequisites

- **Docker Desktop** (version 24.0+ recommended) or **Docker Engine** with the Compose plugin (`docker compose version` >= 2.20).
- Valid network access to pull base Docker images (`node:22-slim`, `postgres:16-alpine`, `redis:7-alpine`).

---

## 3. Environment Configuration

The repository includes a template file `.env.docker.example`.

Create your local `.env.docker` file:

```bash
cp .env.docker.example .env.docker
```

Key configuration variables:

| Variable | Description | Default (Co-existence) | Everyday Standard |
| :--- | :--- | :--- | :--- |
| `POSTGRES_USER` | PostgreSQL superuser | `postgres` | `postgres` |
| `POSTGRES_PASSWORD` | PostgreSQL password | `postgres` | `postgres` |
| `POSTGRES_DB` | Medusa database name | `medusa_db` | `medusa_db` |
| `MEDUSA_PORT` | Host port for Medusa API | `9001` | `9000` |
| `STOREFRONT_PORT` | Host port for Storefront UI | `8001` | `8000` |
| `JWT_SECRET` | Secret key for JWT tokens | *Pre-configured secret* | *Generate random string* |
| `COOKIE_SECRET` | Secret key for cookies | *Pre-configured secret* | *Generate random string* |
| `STORE_CORS` | Allowed CORS origins for store | Includes 8000, 8001 | Includes 8000, 8001 |
| `NEXT_PUBLIC_MEDUSA_PUBLISHABLE_KEY` | Storefront publishable API key | `pk_...` | Generated/configured key |
| `NEXT_PUBLIC_MEDUSA_BACKEND_URL` | Browser-accessible Medusa URL | `http://localhost:9001` | `http://localhost:9000` |
| `NEXT_PUBLIC_BASE_URL` | Storefront canonical base URL | `http://localhost:8001` | `http://localhost:8000` |

> [!IMPORTANT]
> Never commit `.env.docker` containing production secrets to version control. The file `.env.docker` is excluded via `.gitignore`.

---

## 4. Operation Commands

All commands use the isolated project configuration.

### Build Images

Build all service images without starting containers:

```bash
docker compose --env-file .env.docker build
```

Rebuild from scratch (ignoring build cache):

```bash
docker compose --env-file .env.docker build --no-cache
```

### Start the Complete Stack

Start all services in detached mode:

```bash
docker compose --env-file .env.docker up -d
```

### Check Service Status

View status and health check outcomes for all containers:

```bash
docker compose --env-file .env.docker ps
```

### View Service Logs

Follow logs for the entire stack:

```bash
docker compose --env-file .env.docker logs -f
```

Follow logs for a specific service (e.g., backend):

```bash
docker compose --env-file .env.docker logs -f backend
```

Follow logs for database migrations during startup:

```bash
docker compose --env-file .env.docker logs backend | grep -i migration
```

### Stop the Complete Stack

Stop containers while keeping volumes and database data intact:

```bash
docker compose --env-file .env.docker down
```

---

## 5. Health & Connectivity Verification

### Container Health Checks

Each service defines an automated container health check in `compose.yaml`:

1. **PostgreSQL**:
   ```bash
   docker exec ecomm-phase2-postgres pg_isready -U postgres -d medusa_db
   ```
2. **Redis**:
   ```bash
   docker exec ecomm-phase2-redis redis-cli ping
   ```
   *(Expected response: `PONG`)*
3. **Medusa Backend**:
   ```bash
   curl -I http://localhost:9001/health
   ```
   *(Expected response: `HTTP/1.1 200 OK`)*
4. **Storefront**:
   ```bash
   curl -I http://localhost:8001
   ```
   *(Expected response: `HTTP/1.1 200 OK` or `307 Temporary Redirect` to `/dk`)*

### Storefront to Backend Connectivity

Test server-side network connectivity from inside the storefront container to the backend container:

```bash
docker exec ecomm-phase2-storefront curl -I http://backend:9000/health
```

Test public store API endpoint from the host:

```bash
curl -s http://localhost:9001/store/regions
```

---

## 6. Database Persistence & Safe Reset Procedures

### Data Persistence Guarantee

Data persists across container restarts, image updates, and `docker compose down` commands because PostgreSQL data is stored in the dedicated named Docker volume `ecomm_phase2_postgres_data`.

Verify existing volume:

```bash
docker volume ls | grep ecomm_phase2
```

### Safe Database Reset (Wiping Volume)

To wipe the database and restart from a clean slate without affecting any other database on your machine:

```bash
# 1. Stop all containers in the project and remove volumes
docker compose --env-file .env.docker down -v

# 2. Restart stack (this re-creates fresh volumes and automatically applies migrations and seed data)
docker compose --env-file .env.docker up -d
```

> [!CAUTION]
> Running `docker compose down -v` permanently removes the `ecomm_phase2_postgres_data` volume. Existing databases belonging to other projects (`medusa-postgres-ecom`, etc.) will remain untouched.

---

## 7. Troubleshooting Common Errors

### 1. Port Conflict (`bind: address already in use`)
- **Symptom**: `docker compose up` fails with `listen tcp 0.0.0.0:9000: bind: Only one usage of each socket address is normally permitted`.
- **Cause**: A local process or container is already bound to that host port.
- **Solution**: Edit `.env.docker` to set `MEDUSA_PORT=9001` and `STOREFRONT_PORT=8001`, or kill the conflicting local Node process (`Get-Process -Id <PID> | Stop-Process`).

### 2. Backend Migration Timeout / Postgres Not Ready
- **Symptom**: Backend container fails on `npx medusa db:migrate`.
- **Cause**: Postgres container was not ready to accept connections.
- **Solution**: The `compose.yaml` uses `depends_on` with `condition: service_healthy` and `pg_isready` check. If Postgres takes longer to initialize on slower disks, increase `healthcheck.retries` and `start_period`.

### 3. Storefront Cannot Reach Backend in SSR
- **Symptom**: `Middleware.ts: Error fetching regions` or `ECONNREFUSED 127.0.0.1:9000`.
- **Cause**: Next.js server components inside the container trying to fetch `http://localhost:9000` instead of `http://backend:9000`.
- **Solution**: Ensure `MEDUSA_BACKEND_URL=http://backend:9000` is set in the `storefront` service environment in `compose.yaml`.

### 4. Publishable Key Mismatch / Unauthorized
- **Symptom**: Storefront gets 401 or empty regions when fetching `/store/regions`.
- **Cause**: The key passed in `NEXT_PUBLIC_MEDUSA_PUBLISHABLE_KEY` does not exist in the database.
- **Solution**: Verify `STOREFRONT_PUBLISHABLE_KEY` is configured in `backend` service environment. The migration seed automatically matches the key token upon initial database creation.
