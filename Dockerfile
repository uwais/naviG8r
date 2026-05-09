# Build from this directory (logistics-mvp/), where paths apps/api and packages/ exist:
#   docker build -t logistics-mvp-api .
#
# If @prisma/client is missing at runtime, the image likely ran `npm install` at the
# wrong directory (repo root with no package.json). This image installs only under apps/api.

FROM node:22-bookworm-slim

WORKDIR /app

COPY apps/api/package.json ./apps/api/
RUN cd apps/api && npm install

COPY packages ./packages
COPY apps/api ./apps/api

RUN cd apps/api && npx prisma generate

WORKDIR /app/apps/api
ENV NODE_ENV=production
EXPOSE 3000
CMD ["node", "--experimental-strip-types", "src/index.ts"]
