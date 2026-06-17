# syntax=docker/dockerfile:1

# ---- build stage: produce the static Astro output ----
FROM node:20-alpine AS build
WORKDIR /app

# Install with a clean, reproducible lockfile resolution first (better caching).
COPY package.json package-lock.json* ./
RUN npm ci

COPY . .
RUN npm run build

# ---- runtime stage: nginx serving the static output, non-root ----
FROM nginxinc/nginx-unprivileged:1.27-alpine AS runtime
# nginx-unprivileged already runs as uid 101 (nginx) and listens >1024 by design,
# which matches our :8080 config and a read-only-friendly, non-root posture.

# Replace the default config with ours (8080 site + 8081 stub_status).
COPY nginx.conf /etc/nginx/nginx.conf
COPY --from=build /app/dist /usr/share/nginx/html

EXPOSE 8080
# 9113 is the exporter sidecar's port (separate container); 8081 is loopback-only.

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -qO- http://127.0.0.1:8080/healthz >/dev/null 2>&1 || exit 1

# Image already defines USER 101; keep nginx in the foreground.
CMD ["nginx", "-g", "daemon off;"]
