# Build OpenClaw from source to avoid npm packaging gaps (some build artifacts are not published).
FROM node:22-bookworm AS openclaw-build

# Dependencies needed for OpenClaw build
RUN apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    git \
    ca-certificates \
    curl \
    python3 \
    make \
    g++ \
  && rm -rf /var/lib/apt/lists/*

# Install Bun (OpenClaw build uses it)
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:${PATH}"

RUN corepack enable

WORKDIR /openclaw

# Pin to a known ref (tag/branch/commit). Defaults to main branch.
ARG OPENCLAW_GIT_REF=main
RUN git clone --depth 50 https://github.com/openclaw/openclaw.git . \
  && git checkout "${OPENCLAW_GIT_REF}" 2>/dev/null || git checkout main

# Ensure pnpm links workspace packages (avoid fetching openclaw from npm).
RUN printf "link-workspace-packages=true\nprefer-workspace-packages=true\n" >> .npmrc

# Fix @typescript/native-preview version to use latest available (some dev tags may lag)
# Match various version formats: 7.0.0-dev.20260125.1, ^7.0.0-dev.20260125.1, etc.
RUN find . -name "package.json" -type f -exec sed -i 's/7\.0\.0-dev\.20260125\.1/7.0.0-dev.20260124.1/g' {} \;

# Install dependencies. Allow lockfile updates if package.json has changed.
RUN pnpm install --no-frozen-lockfile
RUN pnpm build
ENV OPENCLAW_PREFER_PNPM=1
RUN pnpm ui:install && pnpm ui:build


# Runtime image
FROM node:22-bookworm
ENV NODE_ENV=production

RUN apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    ca-certificates \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Wrapper deps
COPY package.json ./
RUN npm install --omit=dev && npm cache clean --force

# Copy built OpenClaw
COPY --from=openclaw-build /openclaw /openclaw

# Provide openclaw executable
RUN printf '%s\n' '#!/usr/bin/env bash' 'exec node /openclaw/dist/entry.js "$@"' > /usr/local/bin/openclaw \
  && chmod +x /usr/local/bin/openclaw

COPY src ./src
COPY public ./public

EXPOSE 8080
CMD ["node", "src/server.js"]
