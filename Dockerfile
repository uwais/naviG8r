# Logistics MVP — Node API (TypeScript stripped at runtime)
FROM node:22-bookworm-slim

WORKDIR /app

# No npm install required for runtime (zero third-party deps).
COPY package.json ./
COPY apps ./apps
COPY packages ./packages

ENV NODE_ENV=production

# Render injects PORT; default kept for local docker run.
EXPOSE 3000

CMD ["node", "--experimental-strip-types", "apps/api/src/index.ts"]
