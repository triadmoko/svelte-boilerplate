# Stage 1: Build
FROM oven/bun:1.2-alpine AS builder

WORKDIR /app

COPY package.json bun.lock ./
RUN bun install --frozen-lockfile

COPY . .
RUN bun run build

# Stage 2: Production
FROM oven/bun:1.2-alpine AS runner

WORKDIR /app

ENV NODE_ENV=production

COPY --from=builder /app/build ./build
COPY --from=builder /app/package.json ./package.json

RUN bun install --production --frozen-lockfile --ignore-scripts

EXPOSE 3000

CMD ["bun", "build/index.js"]
