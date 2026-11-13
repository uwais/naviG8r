# syntax=docker/dockerfile:1

FROM node:22-bookworm-slim

LABEL org.opencontainers.image.source="https://github.com/uwais/naviG8r"
ARG RELEASE_SHA=unknown
ENV NODE_ENV=production
ENV RELEASE_SHA=${RELEASE_SHA}

WORKDIR /app

# Every workspace package.json is copied so npm ci can match the whole package-lock.json.
COPY package.json package-lock.json ./
COPY apps/api/package.json ./apps/api/package.json
COPY apps/www/package.json ./apps/www/package.json
COPY packages/core/package.json ./packages/core/package.json

RUN npm ci --omit=dev --workspace apps/api --include-workspace-root=false --ignore-scripts

COPY packages ./packages
COPY apps/api ./apps/api

WORKDIR /app/apps/api

RUN npx prisma generate

EXPOSE 3000

CMD ["node", "--experimental-strip-types", "src/index.ts"]
