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

# Install runtime dependencies, MySQL client, and curl for healthcheck
RUN apk add --no-cache mysql-client bash curl

# Install pnpm
RUN npm install -g pnpm

# Copy package files and patches from builder
COPY package.json pnpm-lock.yaml ./
COPY --from=builder /app/patches ./patches

# Install production dependencies only
RUN pnpm install --frozen-lockfile --prod

# Copy built application from builder
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/dist/public ./client/dist

# Create startup script using RUN with proper shell
RUN cat > /app/start.sh << 'EOF'
#!/bin/bash
set -e

echo "Waiting for database to be ready..."
for i in {1..30}; do
  if mysql -h "$DATABASE_HOST" -u "$DATABASE_USER" -p"$DATABASE_PASSWORD" -e "SELECT 1" > /dev/null 2>&1; then
    echo "Database is ready!"
    break
  fi
  echo "Attempt $i/30 - Database not ready yet..."
  sleep 2
done

echo "Running database migrations..."
pnpm db:push || true

echo "Starting application..."
node dist/index.js
EOF
RUN chmod +x /app/start.sh

# Expose port
EXPOSE 3009

# Health check using curl
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
  CMD curl -f http://localhost:3009/ || exit 1

# Start the application
CMD ["/app/start.sh"]
