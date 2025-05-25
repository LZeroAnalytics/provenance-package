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

handle_funding_request() {
    local address="$1"
    echo "Funding address: $address"
    result=$(provenanced tx bank send faucet "$address" "$TRANSFER_AMOUNT" --chain-id "$CHAIN_ID" --node "$NODE_URL" --keyring-backend test --yes 2>&1)
    success=$?
    
    if [ $success -eq 0 ]; then
        echo "{\"status\":\"success\",\"message\":\"Funded $address with $TRANSFER_AMOUNT\"}"
    else
        echo "{\"status\":\"error\",\"message\":\"Failed to fund address: $result\"}"
    fi
}

(
    while true; do
        echo "Checking if node is ready..."
        provenanced status --node "$NODE_URL" > /dev/null 2>&1
        if [ $? -eq 0 ]; then
            echo "Node is ready. Faucet is operational."
            break
        fi
        echo "Node not ready yet. Waiting..."
        sleep 5
    done
) &

while true; do
    echo "Faucet service running. To request funds, use:"
    echo "curl -X POST -H \"Content-Type: application/json\" -d '{\"address\":\"your-address\"}' http://<faucet-host>:$PORT"
    sleep 60
done
