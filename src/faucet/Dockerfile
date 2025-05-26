FROM provenanceio/provenance:latest

# Install required packages
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    netcat \
    curl \
    jq \
    && rm -rf /var/lib/apt/lists/*

# Create directory for scripts
WORKDIR /app

# Copy faucet script
COPY faucet.sh /app/
RUN chmod +x /app/faucet.sh

# Create directory for mnemonic file
RUN mkdir -p /tmp/mnemonic

# Set entrypoint
ENTRYPOINT ["/app/faucet.sh"]
