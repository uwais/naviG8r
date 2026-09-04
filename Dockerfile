# syntax=docker/dockerfile:1

FROM node:22-bookworm-slim

LABEL org.opencontainers.image.source="https://github.com/uwais/naviG8r"
ARG RELEASE_SHA=unknown
ENV NODE_ENV=production
ENV RELEASE_SHA=${RELEASE_SHA}

WORKDIR /app

COPY apps/api/package.json ./apps/api/package.json
WORKDIR /app/apps/api

RUN npm install --ignore-scripts

WORKDIR /app

COPY packages ./packages
COPY apps/api ./apps/api

WORKDIR /app/apps/api

RUN npx prisma generate

EXPOSE 3000

CMD ["node", "--experimental-strip-types", "src/index.ts"]
