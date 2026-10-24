# Stage 1: Install dependencies
FROM node:22-slim AS deps

WORKDIR /app

# Configure npm network timeouts and retries for stability
RUN npm config set fetch-retries 5 \
 && npm config set fetch-retry-mintimeout 20000 \
 && npm config set fetch-retry-maxtimeout 120000

# Copy root and workspace manifests
COPY package.json package-lock.json turbo.json ./
COPY apps/storefront/package.json ./apps/storefront/
COPY apps/backend/package.json ./apps/backend/

# Install dependencies across workspace using BuildKit cache mount
RUN --mount=type=cache,target=/root/.npm npm ci

# Stage 2: Build Next.js storefront
FROM node:22-slim AS builder

WORKDIR /app

# Copy dependencies from deps stage
COPY --from=deps /app/node_modules ./node_modules
COPY --from=deps /app/package.json /app/package-lock.json ./
COPY apps/storefront ./apps/storefront

# Build arguments for Next.js build-time variables
ARG NEXT_PUBLIC_MEDUSA_PUBLISHABLE_KEY
ARG NEXT_PUBLIC_MEDUSA_BACKEND_URL=http://localhost:9001
ARG NEXT_PUBLIC_BASE_URL=http://localhost:8001
ARG NEXT_PUBLIC_DEFAULT_REGION=dk

ENV NEXT_PUBLIC_MEDUSA_PUBLISHABLE_KEY=${NEXT_PUBLIC_MEDUSA_PUBLISHABLE_KEY}
ENV NEXT_PUBLIC_MEDUSA_BACKEND_URL=${NEXT_PUBLIC_MEDUSA_BACKEND_URL}
ENV NEXT_PUBLIC_BASE_URL=${NEXT_PUBLIC_BASE_URL}
ENV NEXT_PUBLIC_DEFAULT_REGION=${NEXT_PUBLIC_DEFAULT_REGION}
ENV NODE_ENV=production

WORKDIR /app/apps/storefront
RUN npm run build

# Stage 3: Production runner
FROM node:22-slim AS runner

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    dumb-init \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Set non-root ownership during COPY to avoid slow overlayfs chown
COPY --chown=node:node --from=builder /app/package.json /app/package-lock.json ./
COPY --chown=node:node --from=builder /app/node_modules ./node_modules
COPY --chown=node:node --from=builder /app/apps/storefront ./apps/storefront

USER node

WORKDIR /app/apps/storefront

ENV NODE_ENV=production
ENV PORT=8000

EXPOSE 8000

HEALTHCHECK --interval=10s --timeout=5s --start-period=30s --retries=3 \
  CMD curl -f http://localhost:8000 || exit 1

ENTRYPOINT ["dumb-init", "--"]
CMD ["npm", "run", "start"]
