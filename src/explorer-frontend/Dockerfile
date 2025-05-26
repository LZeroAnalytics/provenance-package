# Multi-architecture Dockerfile for Provenance Explorer Frontend
# Supports both amd64 and arm64 architectures

# Build stage
FROM --platform=$BUILDPLATFORM node:18 AS build

# Set working directory
WORKDIR /app

# Copy package.json and package-lock.json
COPY package*.json ./

# Install dependencies
RUN npm ci

# Copy source code
COPY . .

# Build the application
RUN npm run build

# Runtime stage
FROM --platform=$TARGETPLATFORM nginx:alpine

# Copy the built files from the build stage
COPY --from=build /app/dist /usr/share/nginx/html

# Copy nginx configuration
COPY nginx.conf /etc/nginx/nginx.conf

# Expose the web server port
EXPOSE 80

# Start nginx
CMD ["nginx", "-g", "daemon off;"]
