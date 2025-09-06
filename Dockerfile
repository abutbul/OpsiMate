# Build stage
FROM node:20-alpine AS builder

# Install build tools and clean up in same layer
RUN npm install -g pnpm typescript && \
    npm cache clean --force

WORKDIR /app

# Copy package files first for better caching
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY apps/server/package.json ./apps/server/
COPY apps/client/package.json ./apps/client/
COPY packages/shared/package.json ./packages/shared/

# Install dependencies with cleanup in same layer
RUN pnpm install --frozen-lockfile && \
    if [ "$(uname -m)" = "aarch64" ]; then pnpm add @rollup/rollup-linux-arm64-musl --save-dev --filter @OpsiMate/client; fi && \
    pnpm store prune

# Copy source code and build
COPY . .
RUN pnpm run build && \
    pnpm prune --prod && \
    pnpm store prune && \
    rm -rf .pnpm-store node_modules/.cache

# Production stage - minimal runtime
FROM node:20-alpine

# Install only runtime essentials
RUN npm install -g serve && \
    apk add --no-cache dumb-init

# Create app user
RUN addgroup -g 1001 -S nodejs && \
    adduser -S opsimate -u 1001 && \
    mkdir -p /app/data/database /app/data/private-keys /app/config

WORKDIR /app

# Copy only built assets and runtime files
COPY --from=builder /app/packages/shared/dist ./packages/shared/dist
COPY --from=builder /app/apps/server/dist ./apps/server/dist
COPY --from=builder /app/apps/client/dist ./apps/client/dist

# Copy package files for production dependencies
COPY --from=builder /app/package.json ./
COPY --from=builder /app/pnpm-lock.yaml ./
COPY --from=builder /app/pnpm-workspace.yaml ./
COPY --from=builder /app/apps/server/package.json ./apps/server/
COPY --from=builder /app/packages/shared/package.json ./packages/shared/

# Install production dependencies using the actual package.json files
RUN npm install -g pnpm && \
    pnpm install --prod --frozen-lockfile && \
    pnpm store prune && \
    npm cache clean --force && \
    rm -rf /tmp/* /var/cache/apk/* /root/.npm

# Create workspace linking for shared package
RUN mkdir -p node_modules/@OpsiMate && \
    ln -sf /app/packages/shared node_modules/@OpsiMate/shared

# Copy config files
COPY --chown=opsimate:nodejs default-config.yml /app/config/default-config.yml
COPY --chown=opsimate:nodejs docker-entrypoint.sh /app/docker-entrypoint.sh
RUN chmod +x /app/docker-entrypoint.sh

# Adjust permissions
RUN chown -R opsimate:nodejs /app

USER opsimate

EXPOSE 3001 8080
VOLUME ["/app/data/database", "/app/data/private-keys", "/app/config"]

ENV NODE_ENV=production

ENTRYPOINT ["sh", "/app/docker-entrypoint.sh"]
CMD ["sh", "-c", "serve -s /app/apps/client/dist -l 8080 & cd /app/apps/server && node dist/src/index.js"]

# Server runtime target (for docker-compose)
FROM node:20-alpine AS server-runtime

RUN npm install -g pnpm && apk add --no-cache dumb-init postgresql-client

RUN addgroup -g 1001 -S nodejs && \
    adduser -S opsimate -u 1001 && \
    mkdir -p /app/data/database /app/data/private-keys /app/config

WORKDIR /app

COPY --from=builder /app/apps/server/dist ./apps/server/dist
COPY --from=builder /app/packages/shared/dist ./packages/shared/dist

COPY --from=builder /app/package.json ./
COPY --from=builder /app/pnpm-lock.yaml ./
COPY --from=builder /app/apps/server/package.json ./apps/server/
COPY --from=builder /app/packages/shared/package.json ./packages/shared/

# Reuse built production node_modules from the builder stage so native
# modules (e.g. better-sqlite3) are already compiled. Avoid re-running
# package installation in the runtime image which would require build
# tools.
COPY --from=builder /app/node_modules ./node_modules
RUN rm -rf /tmp/* /var/cache/apk/* /root/.npm || true

# Create workspace linking for shared package (same as in original Dockerfile)
RUN mkdir -p node_modules/@OpsiMate && \
    ln -sf /app/packages/shared node_modules/@OpsiMate/shared

# Ensure top-level symlinks exist for packages that pnpm keeps under
# .pnpm/*/node_modules so Node's require() can find native modules like
# better-sqlite3. This iterates the pnpm directory and creates missing
# links in node_modules.
RUN set -eu; \
        for pkg in /app/node_modules/.pnpm/*/node_modules/*; do \
            [ -e "$pkg" ] || continue; \
            name=$(basename "$pkg"); \
            if [ ! -e "/app/node_modules/$name" ]; then \
                ln -s "$pkg" "/app/node_modules/$name"; \
            fi; \
        done || true

# Ensure server's local node_modules contains native modules that may not
# have a top-level link. This creates a symlink for better-sqlite3 so
# require('better-sqlite3') resolves from the server package.
RUN mkdir -p /app/apps/server/node_modules && \
        for d in /app/node_modules/.pnpm/better-sqlite3@*; do \
            if [ -d "$d" ]; then \
                ln -sf "$d/node_modules/better-sqlite3" /app/apps/server/node_modules/better-sqlite3 || true; \
            fi; \
        done || true

COPY --chown=opsimate:nodejs docker-entrypoint.sh /app/docker-entrypoint.sh
RUN chmod +x /app/docker-entrypoint.sh && chown -R opsimate:nodejs /app

USER opsimate

EXPOSE 3001
VOLUME ["/app/data/database","/app/data/private-keys","/app/config"]
ENTRYPOINT ["sh","/app/docker-entrypoint.sh"]
CMD ["sh","-c","cd /app/apps/server && node dist/src/index.js"]

# Client runtime target (standalone, run on-demand)
FROM node:20-alpine AS client-runtime
RUN npm install -g serve && apk add --no-cache dumb-init

RUN addgroup -g 1001 -S nodejs && adduser -S opsimate -u 1001 && mkdir -p /app
WORKDIR /app
COPY --from=builder /app/apps/client/dist ./apps/client/dist
RUN chown -R 1001:1001 /app

USER opsimate
EXPOSE 8080
CMD ["sh","-c","serve -s /app/apps/client/dist -l 8080"]