# Multi-stage build for optimized production image
FROM node:22-alpine AS builder

WORKDIR /app

# Install build dependencies
RUN apk add --no-cache python3 make g++

# Copy package files and patches
COPY package.json pnpm-lock.yaml ./
COPY patches ./patches

# Install dependencies
RUN npm install -g pnpm && pnpm install --frozen-lockfile

# Copy source code
COPY . .

# Build the application
RUN pnpm run build

# Production stage
FROM node:22-alpine

WORKDIR /app

# Install runtime dependencies
RUN apk add --no-cache bash

# Install pnpm
RUN npm install -g pnpm

# Copy package files and patches from builder
COPY package.json pnpm-lock.yaml ./
COPY patches ./patches

# Copy drizzle config and schema
COPY drizzle.config.ts ./
COPY drizzle ./drizzle

# Install ALL dependencies (including dev) for drizzle-kit and vite
RUN pnpm install --frozen-lockfile

# Copy built application from builder
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/dist/public ./client/dist

# Create startup script with environment variable mapping
RUN cat > /app/start.sh << 'EOF'
#!/bin/bash
set -e

# Map Coolify environment variables to Manus template variables
export VITE_APP_ID="${VITE_APP_ID:-}"
export VITE_OAUTH_PORTAL_URL="${VITE_OAUTH_SERVER_URL:-}"
export OWNER_OPEN_ID="${OWNER_OPEN_ID:-}"
export OWNER_NAME="${OWNER_NAME:-}"
export BUILT_IN_FORGE_API_URL="${BUILT_IN_FORGE_API_URL:-}"
export BUILT_IN_FORGE_API_KEY="${BUILT_IN_FORGE_API_KEY:-}"
export VITE_FRONTEND_FORGE_API_KEY="${VITE_FRONTEND_FORGE_API_KEY:-}"
export VITE_FRONTEND_FORGE_API_URL="${VITE_FRONTEND_FORGE_API_URL:-}"
export VITE_ANALYTICS_ENDPOINT="${VITE_ANALYTICS_ENDPOINT:-}"
export VITE_ANALYTICS_WEBSITE_ID="${VITE_ANALYTICS_WEBSITE_ID:-}"
export VITE_APP_TITLE="${VITE_APP_TITLE:-Torius Atlas}"
export VITE_APP_LOGO="${VITE_APP_LOGO:-}"

echo "Running database migrations..."
pnpm db:push || true

echo "Starting application on port ${PORT:-3009}..."
node dist/index.js
EOF
RUN chmod +x /app/start.sh

# Expose port
EXPOSE 3009

# Start the application
CMD ["/app/start.sh"]
