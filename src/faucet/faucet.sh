#!/bin/sh
set -e

CHAIN_ID=$CHAIN_ID
NODE_URL=$NODE_URL
TRANSFER_AMOUNT=$TRANSFER_AMOUNT
PORT=${PORT:-8090}
MONITORING_PORT=${MONITORING_PORT:-8091}

echo "Starting Provenance faucet service..."
echo "Chain ID: $CHAIN_ID"
echo "Node URL: $NODE_URL"
echo "Transfer amount: $TRANSFER_AMOUNT"

if [ -f /tmp/mnemonic/mnemonic.txt ]; then
    echo "Importing faucet key from mnemonic..."
    mkdir -p /root/.provenance
    cat /tmp/mnemonic/mnemonic.txt | provenanced keys add faucet --recover --keyring-backend test
else
    echo "Error: Mnemonic file not found at /tmp/mnemonic/mnemonic.txt"
    exit 1
fi

echo "Starting faucet service on port $PORT"
socat TCP-LISTEN:$PORT,fork,reuseaddr EXEC:"sh -c 'read request; \
    address=\$(echo \"\$request\" | grep -oE \"\\\"address\\\":\\\"[^\\\"]+\\\"\" | cut -d\\\" -f4); \
    echo \"HTTP/1.1 200 OK\"; \
    echo \"Content-Type: application/json\"; \
    echo \"\"; \
    if [ -n \"\$address\" ]; then \
        echo \"Funding address: \$address\" >&2; \
        result=\$(provenanced tx bank send faucet \"\$address\" \"$TRANSFER_AMOUNT\" --chain-id \"$CHAIN_ID\" --node \"$NODE_URL\" --keyring-backend test --yes 2>&1); \
        success=\$?; \
        if [ \$success -eq 0 ]; then \
            echo \"{\\\"status\\\":\\\"success\\\",\\\"message\\\":\\\"Funded \$address with $TRANSFER_AMOUNT\\\"}\"; \
        else \
            echo \"{\\\"status\\\":\\\"error\\\",\\\"message\\\":\\\"Failed to fund address: \$result\\\"}\"; \
        fi; \
    else \
        echo \"{\\\"status\\\":\\\"error\\\",\\\"message\\\":\\\"Invalid request format. Expected {\\\\\\\"address\\\\\\\":\\\\\\\"...\\\\\\\"}\\\"}\";\
    fi'" &

echo "Starting monitoring endpoint on port $MONITORING_PORT"
socat TCP-LISTEN:$MONITORING_PORT,fork,reuseaddr EXEC:"sh -c 'echo \"HTTP/1.1 200 OK\"; echo \"Content-Type: application/json\"; echo \"\"; echo \"{\\\"status\\\":\\\"up\\\"}\"'" &

while true; do
    sleep 60
done
