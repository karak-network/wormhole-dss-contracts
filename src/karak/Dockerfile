# Use the latest foundry image for x86
FROM --platform=linux/amd64 ghcr.io/foundry-rs/foundry

# Copy our source code into the container
WORKDIR /app

# Install Node.js and dependencies
RUN apk add --no-cache nodejs npm
COPY . .
RUN npm i

# Build and test the source code
RUN forge build
RUN forge test

# Expose the default Anvil port
EXPOSE 8545

# Start Anvil and deploy contracts
CMD ["anvil --host 0.0.0.0 & \
    sleep 10 && \
    forge script script/v2/SetupCoreLocal.s.sol --broadcast --rpc-url http://localhost:8545 --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 --code-size-limit 100000 && \
    wait \
    "]