# Terra Stablecoin Engine

Terra is a simplified algorithmic stablecoin system built with [Foundry](https://github.com/foundry-rs/foundry).  
It issues an ERC20 token called **TerraStableCoin (TSC)** that aims to maintain a 1&nbsp;TSC = 1&nbsp;USD peg.

## Overview

The system uses exogenous collateral (e.g. WETH, WBTC).  
Users deposit supported collateral tokens and mint TSC against them.  
A minimum collateralization ratio of 200% is enforced and Chainlink price feeds
protect against stale data via `OracleLib`.

Key contracts:

| Contract | Description |
|----------|-------------|
| `TerraStableCoin` | ERC20 with owner-only mint/burn hooks used by the engine. |
| `TerraEngine` | Core logic for depositing collateral, minting and burning TSC, redeeming collateral and performing liquidations. |
| `OracleLib` | Library that wraps Chainlink feeds and reverts on stale prices. |

Scripts in `script/` use Foundry's scripting environment to deploy the system
on local networks or Sepolia via `ConfigProvider`.

## Project Structure

- `src/` – Solidity sources
- `test/` – Unit, fuzz and invariant tests
- `script/` – Deployment scripts
- `Makefile` – Example command for broadcasting deployment

## Getting Started

Install [Foundry](https://book.getfoundry.sh/getting-started/installation):

```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

Install dependencies and build:

```bash
forge build
```

Run the tests:

```bash
forge test
```

### Deployment

Deploy the contracts to an Anvil instance:

```bash
make deploy
```

`ConfigProvider` supplies token and oracle addresses for local (Anvil) and
Sepolia networks.

## License

This project is licensed under the MIT license.  See individual files for
full license text.

