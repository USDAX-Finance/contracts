# USDAX Finance — Contracts

Smart contracts for the USDAX Protocol, deployed on [Robinhood Chain](https://robinhood.com/us/en/chain/) (Arbitrum Orbit, chain ID 46630).

USDAX is an overcollateralized stablecoin pegged to $1.00. Users lock crypto collateral, mint USDAX against it, and repay to unlock their assets. No custodian, no credit check — fully on-chain.

---

## Deployed Contracts (Robinhood Chain Testnet — Chain ID 46630)

| Contract | Address |
|---|---|
| WETH (mock) | `0x728a06069E7A7DBafe2a92bc1E3e4d48e8fC49Dc` |
| WBTC (mock) | `0xBA4120eA7aA703cA1BBCdD03a1B4Ff15e15F2e34` |
| stETH (mock) | `0xE571b0C36B3EF817950f7Fe3Aa296F2a1fB7479e` |
| USDAxToken | `0x89F2c042def8719930904A474FF999A0F8fddd64` |
| VaultEngine | `0xB5d971d69728B0C31b19A8f184d31813F29EEA20` |
| CollateralManager | `0x2472DCBA450e0AA2f81e69AaCD33f91528343854` |
| MockPriceOracle | `0xe5211fF6a85F51b290600B4807d0ee5F978cEC2D` |
| USDAxSavings | `0x1Ce84b4Fb6E6b44C767d4575bE56890DbC8EFA00` |

Explorer: [explorer.testnet.chain.robinhood.com](https://explorer.testnet.chain.robinhood.com)

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                       User Wallet                        │
└──────────────────────────┬──────────────────────────────┘
                           │ deposit / mint / repay / withdraw
┌──────────────────────────▼──────────────────────────────┐
│                      VaultEngine                         │
│  • Accepts collateral (WETH / WBTC / stETH)              │
│  • Mints / burns USDAX                                   │
│  • Enforces LTV, min debt, liquidation rules             │
│  • Charges 0.5% mint fee → feeRecipient                  │
└────────┬──────────────────┬──────────────────┬──────────┘
         │                  │                  │
┌────────▼────────┐ ┌───────▼───────┐ ┌───────▼────────┐
│  USDAxToken     │ │CollateralMgr  │ │ MockPriceOracle │
│  ERC-20         │ │ Risk params   │ │ USD prices per  │
│  mint/burn only │ │ per token     │ │ collateral token│
│  by VaultEngine │ │ LTV / liq /  │ │ 24h staleness   │
└─────────────────┘ │ bonus         │ │ check           │
                    └───────────────┘ └────────────────┘

┌─────────────────────────────────────────────────────────┐
│                     USDAxSavings                         │
│  • Deposit USDAX → earn 4.20% APY                        │
│  • Rewards funded by protocol mint fees                  │
│  • Linear accrual per second, no lock-up                 │
│  • Withdraw principal and claim rewards separately       │
└─────────────────────────────────────────────────────────┘
```

---

## Contract Details

### VaultEngine
Core CDP engine. Handles all user-facing vault operations.

| Parameter | Value |
|---|---|
| Mint fee | 50 bps (0.5%) |
| Minimum debt | 10 USDAX |
| WETH max LTV | 80% |
| WETH liquidation threshold | 85% |
| WBTC max LTV | 75% |
| WBTC liquidation threshold | 80% |
| stETH max LTV | 75% |
| stETH liquidation threshold | 80% |
| Liquidation bonus | 5% |

**Health Factor** = `(collateralValueUSD × liquidationThreshold) / debtUSDax`  
A vault with HF < 1.0 is eligible for liquidation.

### USDAxToken
Standard ERC-20 with ERC-20 Permit. Mint and burn are permissioned exclusively to VaultEngine — set once at deployment, immutable thereafter.

### CollateralManager
Stores risk parameters for each whitelisted collateral token. Owner-controlled; can add, update, or disable collateral types.

### MockPriceOracle
Owner-controlled price feed. Prices expire after 24 hours (staleness check in `getPrice`). Unsafe read available via `getPriceUnsafe` for off-chain tooling.

### USDAxSavings
USDAX savings rate module. 4.20% APY funded by a pre-seeded reward pool. Rewards accrue linearly per second from last checkpoint. No lock-up period. `withdraw()` does not auto-claim rewards — call `claimRewards()` separately first.

---

## Development

### Requirements
- [Foundry](https://getfoundry.sh/) — `curl -L https://foundry.paradigm.xyz | bash && foundryup`

### Install dependencies
```bash
forge install
```

### Build
```bash
forge build
```

### Test
```bash
forge test -vvv
```

---

## Deployment

### Full protocol deploy (testnet)
```bash
forge script script/Deploy.s.sol \
  --rpc-url https://rpc.testnet.chain.robinhood.com/rpc \
  --broadcast --legacy --skip-simulation \
  --private-key $DEPLOYER_PRIVATE_KEY -vvvv
```

### Deploy USDAxSavings (after core protocol is live)
Update the addresses in `script/DeploySavings.s.sol`, then:
```bash
forge script script/DeploySavings.s.sol \
  --rpc-url https://rpc.testnet.chain.robinhood.com/rpc \
  --broadcast --legacy --skip-simulation \
  --private-key $DEPLOYER_PRIVATE_KEY -vvvv
```

---

## Security

These contracts are deployed on testnet. An independent security audit is scheduled prior to mainnet deployment. Do not use with real funds on mainnet without a completed audit.

**Audit scope:** VaultEngine, CollateralManager, MockPriceOracle, USDAxSavings, USDAxToken.

---

## License

MIT
