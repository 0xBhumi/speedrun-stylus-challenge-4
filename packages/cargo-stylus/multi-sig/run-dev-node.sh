#!/bin/bash

set -e

# Start Nitro dev node in the background
echo "🚀 Starting Nitro dev node..."
docker run --rm --name nitro-dev -p 8547:8547 offchainlabs/nitro-node:v3.2.1-d81324d \
  --dev --http.addr 0.0.0.0 --http.api=net,web3,eth,debug --http.corsdomain="*" &

# Wait for the node to initialize
echo "⏳ Waiting for the Nitro node to initialize..."

until [[ "$(curl -s -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"net_version","params":[],"id":1}' \
  http://127.0.0.1:8547)" == *"result"* ]]; do
    sleep 0.1
done

echo "✅ Nitro node is running!"

# Make the caller a chain owner
echo "👑 Setting chain owner to pre-funded dev account..."
cast send 0x00000000000000000000000000000000000000FF "becomeChainOwner()" \
  --private-key 0xb6b15c8cb491557369f3c7d2c287b053eb229daa9c22138887752191c9520659 \
  --rpc-url http://127.0.0.1:8547

# Deploy Cache Manager Contract
echo "📦 Deploying Cache Manager contract..."
cache_deploy_output=$(cast send --private-key 0xb6b15c8cb491557369f3c7d2c287b053eb229daa9c22138887752191c9520659 \
  --rpc-url http://127.0.0.1:8547 \
  --create 0x60a06040523060805234801561001457600080fd5b50608051611d1c61003060003960006105260152611d1c6000f3fe)

# Extract Cache Manager contract address
cache_manager_address=$(echo "$cache_deploy_output" | grep "contractAddress" | grep -oE '0x[a-fA-F0-9]{40}')

if [[ -z "$cache_manager_address" ]]; then
  echo "❌ Error: Failed to extract Cache Manager contract address."
  echo "$cache_deploy_output"
  exit 1
fi

echo "✅ Cache Manager contract deployed at: $cache_manager_address"

# Register Cache Manager
echo "🔧 Registering Cache Manager as WASM cache manager..."
registration_output=$(cast send --private-key 0xb6b15c8cb491557369f3c7d2c287b053eb229daa9c22138887752191c9520659 \
  --rpc-url http://127.0.0.1:8547 \
  0x0000000000000000000000000000000000000070 \
  "addWasmCacheManager(address)" "$cache_manager_address")

if [[ "$registration_output" == *"error"* ]]; then
  echo "❌ Failed to register Cache Manager."
  echo "$registration_output"
  exit 1
fi

echo "✅ Cache Manager registered successfully."

# Deploy the contract using cargo stylus
echo "🚀 Deploying contract using cargo stylus..."
deploy_output=$(cargo stylus deploy -e http://127.0.0.1:8547 \
  --private-key 0xb6b15c8cb491557369f3c7d2c287b053eb229daa9c22138887752191c9520659 2>&1)

if [[ $? -ne 0 ]]; then
  echo "❌ Error: Contract deployment failed."
  echo "$deploy_output"
  exit 1
fi

# Extract transaction hash
deployment_tx=$(echo "$deploy_output" | grep -i "transaction\|tx" | grep -oE '0x[a-fA-F0-9]{64}' | head -1)
if [[ -z "$deployment_tx" ]]; then
  deployment_tx=$(echo "$deploy_output" | grep -oE '0x[a-fA-F0-9]{64}' | head -1)
fi

# Extract contract address
contract_address=$(echo "$deploy_output" | grep -i "contract\|deployed" | grep -oE '0x[a-fA-F0-9]{40}' | head -1)
if [[ -z "$contract_address" ]]; then
  contract_address=$(echo "$deploy_output" | grep -oE '0x[a-fA-F0-9]{40}' | head -1)
fi

# Check extracted values
if [[ -z "$deployment_tx" ]]; then
  echo "❌ Error: Could not extract deployment transaction hash."
  echo "$deploy_output"
  exit 1
fi

echo "✅ Stylus contract deployed!"
echo "📄 Transaction Hash: $deployment_tx"
if [[ ! -z "$contract_address" ]]; then
  echo "🏠 Contract Address: $contract_address"
fi

# Generate ABI
echo "📦 Generating ABI..."
cargo stylus export-abi > stylus-contract.abi
if [[ $? -ne 0 ]]; then
  echo "❌ ABI generation failed."
  exit 1
fi
echo "✅ ABI saved to stylus-contract.abi"

# Save to build info
mkdir -p build
echo "{
  \"network\": \"nitro-dev\",
  \"cache_manager_address\": \"$cache_manager_address\",
  \"contract_address\": \"$contract_address\",
  \"transaction_hash\": \"$deployment_tx\",
  \"rpc_url\": \"http://127.0.0.1:8547\",
  \"deployment_time\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"
}" > build/stylus-deployment-info.json

echo "📁 Deployment info saved to build/stylus-deployment-info.json"
echo "🎉 Deployment complete. Nitro dev node running..."

# Keep the script alive to monitor Nitro dev container
while true; do
  if ! docker ps | grep -q nitro-dev; then
    echo "❌ Nitro node container stopped unexpectedly."
    exit 1
  fi
  sleep 5
done
