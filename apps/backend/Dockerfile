# Stage 1: Build
FROM node:22-slim AS builder

WORKDIR /app

# Configure npm network timeouts and retries for stability
RUN npm config set fetch-retries 5 \
 && npm config set fetch-retry-mintimeout 20000 \
 && npm config set fetch-retry-maxtimeout 120000

# Copy root workspace manifests
COPY package.json package-lock.json turbo.json ./
COPY apps/backend/package.json ./apps/backend/
COPY apps/storefront/package.json ./apps/storefront/

# Install dependencies across workspace using BuildKit cache mount
RUN --mount=type=cache,target=/root/.npm npm ci

# Copy backend source
COPY apps/backend ./apps/backend

# Build backend
WORKDIR /app/apps/backend
RUN npm run build

# Stage 2: Production Runner
FROM node:22-slim AS runner

# Install dumb-init for proper signal handling and curl for healthcheck
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    dumb-init \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy installed workspace node_modules and built backend artifacts with non-root ownership
COPY --chown=node:node --from=builder /app/package.json /app/package-lock.json ./
COPY --chown=node:node --from=builder /app/node_modules ./node_modules
COPY --chown=node:node --from=builder /app/apps/backend ./apps/backend

RUN chmod +x /app/apps/backend/docker-entrypoint.sh

USER node

WORKDIR /app/apps/backend

ENV NODE_ENV=production
ENV PORT=9000
ENV PATH="/app/node_modules/.bin:${PATH}"

EXPOSE 9000

HEALTHCHECK --interval=10s --timeout=5s --start-period=30s --retries=3 \
  CMD curl -f http://localhost:9000/health || exit 1

ENTRYPOINT ["dumb-init", "--", "/app/apps/backend/docker-entrypoint.sh"]
CMD ["medusa", "start"]
