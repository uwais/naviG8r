# syntax=docker/dockerfile:1

FROM node:22-bookworm-slim

LABEL org.opencontainers.image.source="https://github.com/uwais/naviG8r"
ARG RELEASE_SHA=unknown
ENV NODE_ENV=production
ENV RELEASE_SHA=${RELEASE_SHA}

WORKDIR /app

# The lockfile fixes every package version, so a release builds with the versions that were tested.
COPY package.json package-lock.json ./
COPY apps/api/package.json ./apps/api/package.json

RUN npm ci --workspace apps/api --ignore-scripts

COPY packages ./packages
COPY apps/api ./apps/api

WORKDIR /app/apps/api

RUN npx prisma generate

EXPOSE 3000

CMD ["node", "--experimental-strip-types", "src/index.ts"]
