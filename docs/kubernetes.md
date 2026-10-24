# Medusa Ecommerce Monorepo — Local Kubernetes Deployment & Operations

This guide documents the Kubernetes architecture, local cluster setup, staged deployment procedure, integration verification, troubleshooting, and cleanup for the Medusa v2.22.0 + Next.js 16.4.3 ecommerce stack.

---

## 1. Kubernetes Architecture & Service Discovery

All resources are isolated inside the `ecomm` namespace and defined under [`k8s/`](../k8s/):

| Manifest | Resource Kind(s) | Name | Exposure / Port | Purpose |
| :--- | :--- | :--- | :--- | :--- |
| [`k8s/00-namespace.yaml`](../k8s/00-namespace.yaml) | `Namespace` | `ecomm` | — | Dedicated namespace for the ecommerce stack |
| [`k8s/01-configmap.yaml`](../k8s/01-configmap.yaml) | `ConfigMap` | `ecomm-config` | — | Non-sensitive runtime configuration, CORS origins, internal DNS URLs |
| [`k8s/02-secret.example.yaml`](../k8s/02-secret.example.yaml) | `Secret` (template) | `ecomm-secrets` | — | Template for database password, JWT/cookie secrets, and publishable key |
| [`k8s/03-postgres.yaml`](../k8s/03-postgres.yaml) | `StatefulSet`, `Service` | `postgres` | Headless `5432/TCP` | PostgreSQL 16 with `volumeClaimTemplates` (`2Gi` `ReadWriteOnce` PVC) |
| [`k8s/04-redis.yaml`](../k8s/04-redis.yaml) | `Deployment`, `Service` | `redis` | ClusterIP `6379/TCP` | Redis 7 backing Medusa session store, event bus, and workflow engine |
| [`k8s/05-backend.yaml`](../k8s/05-backend.yaml) | `Deployment`, `Service` | `backend` | NodePort `9000:30090/TCP` | Medusa v2.22.0 API & Admin UI (`Recreate` strategy, DB migration + seed entrypoint) |
| [`k8s/06-storefront.yaml`](../k8s/06-storefront.yaml) | `Deployment`, `Service` | `storefront` | NodePort `8000:30080/TCP` | Next.js 16.4.3 App Router storefront |

### Dual-Channel Service Discovery in Kubernetes

Just like in Docker Compose, Next.js runs in two execution contexts:
1. **Cluster-Internal (Next.js SSR, Server Actions, Middleware)**:
   - Uses `MEDUSA_BACKEND_URL=http://backend:9000` (from `ecomm-config`), resolving via Kubernetes CoreDNS (`backend.ecomm.svc.cluster.local`).
2. **Browser / Client-Side**:
   - Uses `NEXT_PUBLIC_MEDUSA_BACKEND_URL=http://localhost:9000` (when accessed via `kubectl port-forward` or Docker Desktop NodePort) and `STOREFRONT_PUBLISHABLE_KEY` / `NEXT_PUBLIC_MEDUSA_PUBLISHABLE_KEY` (from `ecomm-secrets`).

### Probe Design (`startupProbe`, `readinessProbe`, `livenessProbe`)

Every workload configures all three Kubernetes probes:
- **`postgres`**: Executes `pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB" -h 127.0.0.1` against the `PGDATA=/var/lib/postgresql/data/pgdata` directory on the persistent volume.
- **`redis`**: Executes `redis-cli ping`.
- **`backend`**:
  - Init containers `wait-for-postgres` and `wait-for-redis` block container startup until both data stores accept connections.
  - `startupProbe` checks `GET /health` on port `9000` (`failureThreshold: 36`, `periodSeconds: 5` = up to 180s) so initial database migrations and `initial-data-seed` complete without premature `livenessProbe` restarts.
  - `readinessProbe` and `livenessProbe` monitor `GET /health` continuously thereafter.
- **`storefront`**:
  - Init container `wait-for-backend` waits until `http://backend:9000/health` returns `200 OK` before starting Next.js.
  - `startupProbe`, `readinessProbe`, and `livenessProbe` check `GET /` on port `8000` (Kubernetes `httpGet` treats HTTP `200–399`, including the `307` redirect to `/dk`, as healthy).

---

## 2. Prerequisites & Making Images Available to the Cluster

1. **Build the Application Images** using the existing Dockerfiles:
   ```bash
   docker compose --env-file .env.docker.example build backend storefront
   ```
   This produces `ecomm-phase2-backend:latest` and `ecomm-phase2-storefront:latest`. Both Kubernetes Deployments set `imagePullPolicy: IfNotPresent` so the cluster uses local images without attempting to pull from a remote registry.

2. **Local Kubernetes Cluster**:
   - **Option A — Docker Desktop Kubernetes**:
     Enable Kubernetes in **Docker Desktop $\rightarrow$ Settings $\rightarrow$ Kubernetes $\rightarrow$ Enable Kubernetes**. Images built on the local Docker daemon are automatically visible to the `docker-desktop` cluster.
   - **Option B — `kind` (Kubernetes in Docker)**:
     Create a cluster and load the locally built `linux/amd64` images into the `kind` node's `containerd` store (using `docker save --platform linux/amd64` avoids multi-platform attestation digest errors on Docker Desktop 29+):
     ```bash
     kind create cluster --name ecomm-k8s --wait 120s
     for img in ecomm-phase2-backend:latest ecomm-phase2-storefront:latest; do
       docker save --platform linux/amd64 "$img" | docker exec -i ecomm-k8s-control-plane ctr --namespace=k8s.io images import --platform=linux/amd64 --digests -
     done
     ```

---

## 3. Staged Deployment Procedure

Deploy in stages: **Namespace & Config/Secrets $\rightarrow$ Infrastructure (PostgreSQL & Redis) $\rightarrow$ Backend $\rightarrow$ Storefront**.

### Stage 1: Namespace, ConfigMap, and Secret

```bash
# 1. Create the namespace and ConfigMap
kubectl apply -f k8s/00-namespace.yaml
kubectl apply -f k8s/01-configmap.yaml

# 2. Create the runtime Secret (never commit real secrets to Git)
kubectl create secret generic ecomm-secrets -n ecomm \
  --from-literal=POSTGRES_PASSWORD='postgres' \
  --from-literal=JWT_SECRET='supersecret_jwt_for_medusa_k8s_local' \
  --from-literal=COOKIE_SECRET='supersecret_cookie_for_medusa_k8s_local' \
  --from-literal=STOREFRONT_PUBLISHABLE_KEY='pk_47267c6066285a660ebb8491f6cfe576bab6b2df10c3c3d0f843f67ef4f5d027' \
  --from-literal=NEXT_PUBLIC_MEDUSA_PUBLISHABLE_KEY='pk_47267c6066285a660ebb8491f6cfe576bab6b2df10c3c3d0f843f67ef4f5d027'
```
*(Wait note: the `NEXT_PUBLIC_MEDUSA_PUBLISHABLE_KEY` passed here should match the publishable key baked into `ecomm-phase2-storefront:latest` at build time; `initial-data-seed.ts` automatically syncs `STOREFRONT_PUBLISHABLE_KEY` into PostgreSQL on initial database migration.)*

### Stage 2: Deploy Infrastructure (PostgreSQL StatefulSet & Redis Deployment)

```bash
kubectl apply -f k8s/03-postgres.yaml
kubectl apply -f k8s/04-redis.yaml

# Wait for both infrastructure workloads to become Ready
kubectl rollout status statefulset/postgres -n ecomm --timeout=120s
kubectl rollout status deployment/redis -n ecomm --timeout=120s
```

### Stage 3: Deploy Medusa Backend

```bash
kubectl apply -f k8s/05-backend.yaml

# Watch backend migration, seed, and startup probe completion
kubectl rollout status deployment/backend -n ecomm --timeout=240s
```

### Stage 4: Deploy Next.js Storefront

```bash
kubectl apply -f k8s/06-storefront.yaml

# Wait for storefront readiness
kubectl rollout status deployment/storefront -n ecomm --timeout=120s
```

---

## 4. Verification & Integration Testing

### 1. Pod, Service, and PVC Status
```bash
kubectl get pods,svc,pvc -n ecomm -o wide
```

### 2. In-Cluster & Port-Forwarded Endpoint Verification
Forward the backend and storefront services (use ports `19000` and `18000` if Docker Compose is already bound to `9000` and `8000` on the host):
```bash
kubectl port-forward -n ecomm svc/backend 19000:9000 &
kubectl port-forward -n ecomm svc/storefront 18000:8000 &

# Backend health check
curl -i http://localhost:19000/health

# Admin dashboard UI
curl -I http://localhost:19000/app

# Storefront regions retrieval (authenticated with publishable API key)
curl -H "x-publishable-api-key: <your-pk_key>" http://localhost:19000/store/regions

# Storefront SSR page render (/dk)
curl -I http://localhost:18000/dk
```

### 3. PostgreSQL StatefulSet Persistence Verification
Delete the `postgres-0` pod and confirm that the StatefulSet recreates it attached to the same `postgres-data-postgres-0` PersistentVolumeClaim with all seeded regions and products intact:
```bash
kubectl delete pod postgres-0 -n ecomm
kubectl wait --for=condition=Ready pod/postgres-0 -n ecomm --timeout=90s
kubectl exec -n ecomm postgres-0 -- psql -U postgres -d medusa_db -c "SELECT id, name, currency_code FROM region;"
```

---

## 5. Troubleshooting Common Issues

| Symptom | Cause | Fix |
| :--- | :--- | :--- |
| `ErrImagePull` / `ImagePullBackOff` on `backend` or `storefront` | Local images were not loaded into the `kind` cluster node | Run `kind load docker-image ecomm-phase2-backend:latest ecomm-phase2-storefront:latest --name ecomm-k8s` |
| `CreateContainerConfigError` on `postgres`, `backend`, or `storefront` | `ecomm-secrets` Secret has not been created in namespace `ecomm` | Create `ecomm-secrets` via `kubectl create secret generic ecomm-secrets -n ecomm ...` |
| `postgres-0` fails `initdb` with `directory "/var/lib/postgresql/data" exists but is not empty` | Volume root contains `lost+found` | Handled in `k8s/03-postgres.yaml` via `PGDATA: /var/lib/postgresql/data/pgdata` |
| Storefront returns `Error fetching regions` / `401` | `STOREFRONT_PUBLISHABLE_KEY` in `ecomm-secrets` does not match `NEXT_PUBLIC_MEDUSA_PUBLISHABLE_KEY` baked into the storefront image | Ensure both keys in `ecomm-secrets` match the build-arg key used when building `ecomm-phase2-storefront:latest` |
| `backend` pod restarts during first boot | `livenessProbe` fired before initial DB migrations finished | Handled in `k8s/05-backend.yaml` via `startupProbe` (`failureThreshold: 36` $\times$ `5s` = 180s window) |

---

## 6. Safe Cleanup Instructions

To remove the Kubernetes deployment without affecting your Docker Compose stack or local source files:

```bash
# Delete all resources in the ecomm namespace
kubectl delete namespace ecomm

# (Optional) If using a temporary kind cluster, delete the kind cluster
kind delete cluster --name ecomm-k8s
```
