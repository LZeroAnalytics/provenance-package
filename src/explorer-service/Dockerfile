# Multi-architecture Dockerfile for Provenance Explorer Service
# Supports both amd64 and arm64 architectures

# Build stage
FROM --platform=$BUILDPLATFORM gradle:8-jdk21 AS build

# Set working directory
WORKDIR /app

# Copy only dependency-related files first for better caching
COPY build.gradle.kts gradle.properties settings.gradle.kts /app/
COPY buildSrc/build.gradle.kts /app/buildSrc/

# Download dependencies (allow expected build failure since no source code yet)
RUN gradle clean build --no-daemon > /dev/null 2>&1 || true

# Copy all source files
COPY .editorconfig /app/
COPY buildSrc/ /app/buildSrc/
COPY api-model/ /app/api-model/
COPY database/ /app/database/
COPY service/ /app/service/
COPY gradle/ /app/gradle/
COPY CHANGELOG.md CODE_OF_CONDUCT.md CONTRIBUTING.md LICENSE README.md /app/

# Build the application
RUN gradle clean build --no-daemon

# Runtime stage
FROM --platform=$TARGETPLATFORM eclipse-temurin:21-jre

# Set working directory
WORKDIR /app

# Copy the built jar from the build stage
COPY --from=build /app/service/build/libs/*.jar /app/service.jar

# Copy configuration script
COPY docker/service-configure /app/configure

# Make the configuration script executable
RUN chmod +x /app/configure

# Expose the service port
EXPOSE 8612/tcp

# Set the entrypoint to the configuration script
ENTRYPOINT ["/app/configure"]

# Default command to run the service
CMD ["java", "-jar", "/app/service.jar"]
