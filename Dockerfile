# Build Moltbot from source to avoid npm packaging gaps (some build artifacts are not published).
FROM node:22-bookworm AS moltbot-build

# Dependencies needed for Moltbot build
RUN apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    git \
    ca-certificates \
    curl \
    python3 \
    make \
    g++ \
  && rm -rf /var/lib/apt/lists/*

# Install Bun (Moltbot build uses it)
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:${PATH}"

RUN corepack enable

WORKDIR /moltbot

# Pin to a known ref (tag/branch/commit). Defaults to main branch.
# If main branch has dependency issues, try a specific commit hash or tag.
ARG MOLTBOT_GIT_REF=main
RUN git clone --depth 50 https://github.com/moltbot/moltbot.git . \
  && git checkout "${MOLTBOT_GIT_REF}" 2>/dev/null || git checkout main

# Ensure pnpm links workspace packages (avoid fetching moltbot from npm).
# This is safer than rewriting package.json (which can accidentally change other keys like "bin").
RUN printf "link-workspace-packages=true\nprefer-workspace-packages=true\n" >> .npmrc

# Fix @typescript/native-preview version to use latest available (some dev tags may lag)
# Match various version formats: 7.0.0-dev.20260125.1, ^7.0.0-dev.20260125.1, etc.
RUN find . -name "package.json" -type f -exec sed -i 's/7\.0\.0-dev\.20260125\.1/7.0.0-dev.20260124.1/g' {} \;

# Install dependencies. Allow lockfile updates if package.json has changed.
RUN pnpm install --no-frozen-lockfile
RUN pnpm build
ENV MOLTBOT_PREFER_PNPM=1
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

# Copy built Moltbot
COPY --from=moltbot-build /moltbot /moltbot

# Provide a moltbot executable
RUN printf '%s\n' '#!/usr/bin/env bash' 'exec node /moltbot/dist/entry.js "$@"' > /usr/local/bin/moltbot \
  && chmod +x /usr/local/bin/moltbot

COPY src ./src
COPY public ./public

EXPOSE 8080
CMD ["node", "src/server.js"]
