FROM golang:1.19-alpine AS builder

# Install build dependencies
RUN apk add --no-cache git make gcc libc-dev

# Clone the Provenance repository
RUN git clone https://github.com/provenance-io/provenance.git /provenance

# Set working directory
WORKDIR /provenance

# Build the faucet
RUN cd cmd/faucet && go build -o /go/bin/faucet

# Create a minimal runtime image
FROM alpine:3.16

# Install runtime dependencies
RUN apk add --no-cache ca-certificates jq curl

# Copy the faucet binary from the builder stage
COPY --from=builder /go/bin/faucet /usr/local/bin/faucet

# Create directory for mnemonic file
RUN mkdir -p /tmp/mnemonic

# Set entrypoint
ENTRYPOINT ["faucet"]

# Default command
CMD ["--help"]
