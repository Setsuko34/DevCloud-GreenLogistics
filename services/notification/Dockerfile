FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production=false
COPY tsconfig.json ./
COPY src ./src
RUN npm run build

FROM node:20-alpine AS runner
WORKDIR /app
RUN apk upgrade --no-cache && npm install -g npm@latest --quiet
COPY package*.json ./
RUN npm ci --omit=dev && rm -rf /usr/local/lib/node_modules/npm /usr/local/bin/npm /usr/local/bin/npx
COPY --from=builder /app/dist ./dist
CMD ["node", "dist/index.js"]
