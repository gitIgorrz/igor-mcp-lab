# Multi-stage build — keeps the final image small and production-safe.
#
# Stage 1 (builder): installs ALL dependencies (including devDependencies)
#   and compiles TypeScript → JavaScript into /app/dist.
#   This stage is discarded after the build; its large node_modules never
#   reach the final image.
#
# Stage 2 (runtime): copies only the compiled output and installs
#   production-only dependencies. The result is a lean image with no
#   TypeScript compiler, test frameworks, or source maps.

# ── Stage 1: compile TypeScript ──────────────────────────────────────────────
FROM node:22-alpine AS builder
WORKDIR /app

# Copy manifests first so Docker can cache the npm install layer.
# If package.json hasn't changed, this layer is reused on subsequent builds.
COPY package*.json ./
RUN npm ci

COPY tsconfig.json ./
COPY src ./src
# Outputs compiled JavaScript to /app/dist (see tsconfig.json outDir)
RUN npm run build

# ── Stage 2: production runtime ──────────────────────────────────────────────
FROM node:22-alpine AS runtime
WORKDIR /app

ENV NODE_ENV=production

COPY package*.json ./
# --omit=dev skips devDependencies (TypeScript, tsx, @types/*, etc.)
RUN npm ci --omit=dev && npm cache clean --force

# Copy only the compiled output from the builder stage
COPY --from=builder /app/dist ./dist

EXPOSE 3000

# Run as non-root for security (node user is built into the node:alpine image)
USER node

# ACI liveness probe (infra/main.tf) hits GET /health — this confirms
# the server is up before the container is considered healthy.
HEALTHCHECK --interval=15s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -qO- http://localhost:3000/health || exit 1

CMD ["node", "dist/index.js"]
