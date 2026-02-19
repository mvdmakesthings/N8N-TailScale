# Multi-stage build for n8n with dev license bypass
# For local development / home-lab use only — not production.
#
# Build:  docker compose build n8n-patched
# Expect: ~15-30 min first build, 8+ GB RAM

ARG NODE_VERSION=22

# ───────────────────────────────────────────────────
# Stage 1: Builder — clone, patch, build
# ───────────────────────────────────────────────────
FROM node:${NODE_VERSION}-alpine AS builder

ARG N8N_VERSION=2.8.3

RUN apk add --no-cache git python3 make g++ curl bash

# Enable corepack and activate the exact pnpm version n8n expects
RUN corepack enable && corepack prepare pnpm@10.22.0 --activate

WORKDIR /build

# Clone the pinned n8n release (shallow clone to save time)
RUN git clone --depth 1 --branch "n8n@${N8N_VERSION}" \
    https://github.com/n8n-io/n8n.git .

# Apply the dev license bypass patch
COPY dev-license-bypass.patch .
RUN git apply dev-license-bypass.patch

# Bake the Vite build-time env var into the frontend bundle
RUN echo "VITE_DEV_LICENSE_BYPASS=true" > packages/frontend/editor-ui/.env.local

# Install all dependencies (including devDeps needed for the build)
RUN pnpm install --frozen-lockfile

# Build all packages (backend + frontend)
RUN pnpm build

# Create the pruned production deployment artifact
RUN NODE_ENV=production DOCKER_BUILD=true \
    pnpm --filter=n8n --prod --legacy deploy --no-optional ./compiled

# ───────────────────────────────────────────────────
# Stage 2: Production — minimal runtime image
# ───────────────────────────────────────────────────
FROM node:${NODE_VERSION}-alpine

RUN apk add --no-cache \
    git openssh openssl graphicsmagick tini tzdata ca-certificates

# Install full-icu for internationalization support
RUN npm install -g full-icu@1.5.0 && rm -rf /root/.npm /tmp/*

ENV NODE_ENV=production
ENV NODE_ICU_DATA=/usr/local/lib/node_modules/full-icu
ENV SHELL=/bin/sh

WORKDIR /home/node

# Copy the compiled production artifact from the builder
COPY --from=builder /build/compiled /usr/local/lib/node_modules/n8n
COPY --from=builder /build/docker/images/n8n/docker-entrypoint.sh /

# Rebuild native modules, create symlinks, set up user directory
RUN cd /usr/local/lib/node_modules/n8n && \
    npm rebuild sqlite3 && \
    ln -s /usr/local/lib/node_modules/n8n/bin/n8n /usr/local/bin/n8n && \
    mkdir -p /home/node/.n8n && \
    chown -R node:node /home/node && \
    rm -rf /root/.npm /tmp/*

EXPOSE 5678/tcp
USER node
ENTRYPOINT ["tini", "--", "/docker-entrypoint.sh"]

LABEL org.opencontainers.image.title="n8n (dev-license-bypass)" \
      org.opencontainers.image.description="n8n with enterprise features unlocked for development" \
      org.opencontainers.image.source="https://github.com/n8n-io/n8n" \
      org.opencontainers.image.version=${N8N_VERSION}
