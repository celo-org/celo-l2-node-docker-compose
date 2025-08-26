# Running a Challenger on Celo

This guide explains how to run a challenger for OP Succinct on the Celo network. The challenger monitors dispute games and automatically challenges invalid claims to ensure network security.

## Prerequisites

- Docker and Docker Compose installed
- Access to L1 (Ethereum) and L2 (Celo) RPC endpoints
- A funded private key for submitting challenges
- Running Celo node (this repository)

## Supported Networks

The challenger supports the following Celo networks:

- **Mainnet** (`mainnet`)
- **Alfajores** (`alfajores`)
- **Baklava** (`baklava`)

## Configuration

### 1. Environment Variables

Copy and configure the challenger environment file:

```bash
cp .env.challenger.example .env.challenger
```

Edit `.env.challenger` with your configuration:

```bash
# Required Configuration
L1_RPC=https://your-ethereum-rpc-endpoint
L2_RPC=http://localhost:9993
FACTORY_ADDRESS=0x...                # DisputeGameFactory contract address
GAME_TYPE=1                          # Dispute game type identifier
PRIVATE_KEY=0x...                    # Your funded private key
```

### 2. Main Environment File

In your main environment file (e.g., `mainnet.env`), enable the challenger:

```bash
# Enable challenger
CHALLENGER_ENABLE=true
```

## Running the Challenger

### With Docker Compose

Start the challenger along with your Celo node:

```bash
docker-compose up -d challenger
```

Or start everything including the challenger:

```bash
docker-compose up -d
```

### Check Status

Monitor challenger logs:

```bash
docker-compose logs -f challenger
```

## Security Considerations

⚠️ **Important Security Notes:**

1. **Private Key Security**: Store your private key securely. Consider using a hardware wallet or key management service for production.

2. **Funding**: Ensure your challenger account has sufficient ETH for L1 transactions and gas fees.

3. **Monitoring**: Set up monitoring and alerting for challenger health and balance.

4. **Testing**: Use `MALICIOUS_CHALLENGE_PERCENTAGE` for testing only - never in production.

## Testing Mode

For testing purposes, you can configure the challenger to randomly challenge valid games:

```bash
MALICIOUS_CHALLENGE_PERCENTAGE=10.0  # Challenge 10% of valid games (testing only)
```

Set to `0.0` or remove for production use.

## Monitoring

The challenger exposes metrics on port `9001` (configurable via `CHALLENGER_METRICS_PORT`). You can integrate with Prometheus or other monitoring tools.

For more information, see the [main README](./README.md) for general node setup and configuration.
