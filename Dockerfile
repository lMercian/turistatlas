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

# Install runtime dependencies and MySQL client
RUN apk add --no-cache mysql-client bash

# Install pnpm
RUN npm install -g pnpm

# Copy package files and patches from builder
COPY package.json pnpm-lock.yaml ./
COPY --from=builder /app/patches ./patches

# Install production dependencies only
RUN pnpm install --frozen-lockfile --prod

# Copy built application from builder
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/client/dist ./client/dist
COPY --from=builder /app/drizzle ./drizzle

# Create a startup script
RUN echo '#!/bin/bash\n\
set -e\n\
\n\
echo "Waiting for database to be ready..."\n\
for i in {1..30}; do\n\
  if mysql -h "$DATABASE_HOST" -u "$DATABASE_USER" -p"$DATABASE_PASSWORD" -e "SELECT 1" > /dev/null 2>&1; then\n\
    echo "Database is ready!"\n\
    break\n\
  fi\n\
  echo "Attempt $i/30 - Database not ready yet..."\n\
  sleep 2\n\
done\n\
\n\
echo "Running database migrations..."\n\
pnpm db:push || true\n\
\n\
echo "Starting application..."\n\
node dist/index.js\n\
' > /app/start.sh && chmod +x /app/start.sh

# Expose port
EXPOSE 3009

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
  CMD mysql -h "$DATABASE_HOST" -u "$DATABASE_USER" -p"$DATABASE_PASSWORD" -e "SELECT 1" > /dev/null 2>&1 || exit 1

# Start the application
CMD ["/app/start.sh"]
