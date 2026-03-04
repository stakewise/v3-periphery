# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

```bash
forge build          # Compile contracts
forge test           # Run all tests
forge test --mt test_deposit  # Run specific test by name
forge test -vvv      # Run tests with verbose output
forge fmt            # Format code
forge lint --severity high  # Lint for high-severity issues
```

## Deployment

Scripts in `script/` follow pattern `Deploy<ContractName>.s.sol`. Run with:
```bash
forge script script/DeployX.s.sol --rpc-url $MAINNET_RPC_URL --broadcast
```

Available RPC endpoints: `mainnet`, `hoodi`, `chiado`, `gnosis` (configured in foundry.toml)

## Testing Notes

- Tests use mainnet fork (requires `MAINNET_RPC_URL` env variable)
- Fork block numbers are specified in test files (e.g., `forkBlockNumber = 23_117_000`)
- Tests often use `vm.prank()`, `vm.warp()`, and `vm.startPrank()`/`vm.stopPrank()` for impersonation and time manipulation
- Subgraph endpoints for fetching test data (vaults, allocators, leverage positions):
  - Ethereum: `https://graphs.stakewise.io/mainnet/subgraphs/name/stakewise/prod`
  - Gnosis: `https://graphs.stakewise.io/gnosis/subgraphs/name/stakewise/prod`

## Architecture Overview

This is the StakeWise v3 periphery contracts repository containing supplementary contracts that interact with the core v3-core protocol.

### Key Components

**StrategiesRegistry** (`src/StrategiesRegistry.sol`): Central registry managing strategies and their proxies. Tracks enabled strategies, proxy addresses, and strategy-specific configurations.

**StrategyProxy** (`src/StrategyProxy.sol`): Minimal proxy contract that executes transactions on behalf of leverage strategies. Each user-vault-strategy combination gets its own proxy deployed via `Clones.cloneDeterministic()`.

**LeverageStrategy** (`src/leverage/LeverageStrategy.sol`): Abstract base for leverage strategies. Uses osToken flash loans to create leveraged positions by:
1. Depositing osToken to lending protocol (e.g., Aave)
2. Borrowing asset tokens (WETH/GNO)
3. Depositing borrowed assets to vault and minting more osToken
4. Repeating via flash loan for maximum leverage

Chain-specific implementations:
- `EthAaveLeverageStrategy` - Ethereum mainnet with Aave V3
- `GnoAaveLeverageStrategy` - Gnosis chain with Aave V3

**TokensConverter** (`src/converters/`): Converts reward tokens to vault asset tokens via CoW Protocol swaps. Uses composable conditional orders.

**Helper Contracts** (`src/helpers/`):
- `BoostHelpers` - Calculates boost position details and LTV ratios
- `StakeHelpers` - Facilitates staking operations
- `VaultUserLtvTracker` - Tracks user LTV positions across vaults

**MerkleDistributor** (`src/MerkleDistributor.sol`): Distributes incentives using merkle proofs with oracle-signed root updates.

### Key Patterns

- Strategy proxies are deterministically addressed: `keccak256(abi.encode(strategyId, vault, user))`
- Flash loan pattern for leverage: borrow osToken, convert to assets, deposit to vault, mint more osToken, repay flash loan
- Strategy configs stored in StrategiesRegistry as `bytes` under `keccak256(strategyId, configName)`

## Dependencies

- `v3-core`: StakeWise core protocol (vaults, osToken, keeper)
- `aave-v3-origin`: Aave V3 for borrowing/lending
- `composable-cow`: CoW Protocol for token swaps
- `openzeppelin-contracts-upgradeable`: Upgradeable contract patterns

## Solidity Version

Solidity 0.8.26 with Cancun EVM, optimizer enabled (200 runs), via-IR compilation.

## Code Style

- Single quotes for strings (`'string'` not `"string"`)
- Number underscores for thousands (`1_000_000`)
- Multi-line function headers with params first
