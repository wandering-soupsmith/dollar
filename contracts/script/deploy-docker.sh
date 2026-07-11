#!/usr/bin/env bash
set -eo pipefail

# Helper to deploy and verify contracts using a standardized Linux Docker container.
# This prevents compilation differences (Yul/via_ir non-determinism) between macOS and Etherscan's Linux servers.

if [ -z "$1" ]; then
    echo "Usage: $0 <env-file> [extra-forge-args]"
    echo "Example: $0 .env.sepolia --broadcast --verify"
    exit 1
fi

ENV_FILE="$1"
shift

if [ ! -f "$ENV_FILE" ]; then
    echo "Error: Environment file '$ENV_FILE' not found."
    exit 1
fi

CLEAN_ENV_FILE="${ENV_FILE}.clean"

# Strip comments and inline comments from the environment file for Docker compatibility
echo "Cleaning environment file for Docker..."
grep -v '^#' "$ENV_FILE" | sed -E 's/[[:space:]]*#.*$//g' | grep -v '^[[:space:]]*$' > "$CLEAN_ENV_FILE"

# Detect RPC alias from environment file
RPC_ALIAS="sepolia"
if grep -qE "MAINNET_RPC_URL=https?://" "$CLEAN_ENV_FILE"; then
    RPC_ALIAS="mainnet"
fi

echo "Detected RPC alias: $RPC_ALIAS"
echo "Running compilation and deployment inside Docker container..."

docker run --rm \
  --env-file "$CLEAN_ENV_FILE" \
  -v "$(pwd)":/app \
  -w /app \
  ghcr.io/foundry-rs/foundry:latest \
  "forge script script/DeployGovernance.s.sol:DeployGovernance --rpc-url $RPC_ALIAS $*"

# Clean up
rm -f "$CLEAN_ENV_FILE"
echo "Deployment process completed."
