# Decentralized Stablecoin (DSC) Protocol

A decentralized, overcollateralized stablecoin protocol built with Solidity and Foundry. This project implements a algorithmic stablecoin system similar to MakerDAO's DAI, but without governance and fees.

## 📋 Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Architecture](#architecture)
- [Smart Contracts](#smart-contracts)
- [Getting Started](#getting-started)
- [Testing](#testing)
- [Deployment](#deployment)
- [Security Considerations](#security-considerations)
- [Contributing](#contributing)
- [License](#license)

## Overview

The DSC Protocol maintains a 1:1 peg with the US Dollar through an overcollateralization mechanism. Users can mint DSC tokens by depositing approved collateral (WETH and WBTC), and the system ensures the protocol always remains overcollateralized through liquidation mechanisms.

### Key Properties

- **Exogenously Collateralized**: Backed by external crypto assets (WETH, WBTC)
- **Dollar Pegged**: Maintains 1 DSC = $1 USD
- **Algorithmically Stable**: No governance, purely algorithmic stabilization
- **Overcollateralized**: Requires 200% collateralization ratio

## Features

- **Collateral Deposit & Withdrawal**: Support for WETH and WBTC collateral
- **DSC Minting & Burning**: Mint stablecoins against collateral
- **Liquidation System**: Automated liquidation with 10% bonus incentive
- **Health Factor Monitoring**: Real-time solvency tracking
- **Chainlink Price Feeds**: Reliable price data for collateral assets
- **Reentrancy Protection**: Secure against common attack vectors

## Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   DSCEngine     │    │ DecentralizedSC │    │  Chainlink      │
│   (Core Logic)  │◄──►│   (ERC20 Token) │    │  Price Feeds    │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                                              │
         ▼                                              ▼
┌─────────────────┐                          ┌─────────────────┐
│   Collateral    │                          │   Price Oracle  │
│   (WETH/WBTC)   │                          │   Integration   │
└─────────────────┘                          └─────────────────┘
```

## Smart Contracts

### Core Contracts

#### `DSCEngine.sol`

The main protocol contract that handles:

- Collateral deposits and withdrawals
- DSC minting and burning
- Liquidation logic
- Health factor calculations

#### `DecentralizedStableCoin.sol`

ERC20 token contract for the DSC stablecoin with:

- Minting/burning capabilities (only by DSCEngine)
- Standard ERC20 functionality
- Ownable pattern for access control

### Key Functions

#### User Functions

```solidity
// Deposit collateral and mint DSC in one transaction
function depositCollateralAndMintDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToMint)

// Deposit collateral tokens
function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)

// Mint DSC tokens (requires sufficient collateral)
function mintDsc(uint256 amountDscToMint)

// Burn DSC tokens
function burnDsc(uint256 amount)

// Redeem collateral
function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
```

#### Liquidation Functions

```solidity
// Liquidate undercollateralized positions
function liquidate(address collateral, address user, uint256 debtToCover)
```

## Getting Started

### Prerequisites

- [Git](https://git-scm.com/book/en/v2/Getting-Started-Installing-Git)
- [Foundry](https://getfoundry.sh/)

### Installation

1. Clone the repository

```bash
git clone https://github.com/anshmehta-22/foundry-defi-stablecoin
cd foundry-defi-stablecoin
```

2. Install dependencies

```bash
forge install
```

3. Build the project

```bash
forge build
```

## Testing

This project includes comprehensive test suites:

### Run All Tests

```bash
forge test
```

### Run Specific Test Categories

#### Unit Tests

```bash
forge test --match-path test/unit/*
```

#### Integration Tests

```bash
forge test --match-path test/integration/*
```

#### Invariant/Fuzz Tests

```bash
forge test --match-path test/fuzz/*
```

### Test Coverage

```bash
forge coverage
```

### Gas Report

```bash
forge test --gas-report
```

## Test Categories

### Unit Tests (`test/unit/`)

- ✅ Constructor validation
- ✅ Collateral deposit/withdrawal
- ✅ DSC minting/burning
- ✅ Liquidation mechanics
- ✅ Price feed integration
- ✅ Health factor calculations

### Invariant Tests (`test/fuzz/`)

- ✅ Protocol must always be overcollateralized
- ✅ Getter functions should never revert
- ✅ Users can't create bad debt

### Integration Tests

- ✅ End-to-end user workflows
- ✅ Multi-user scenarios
- ✅ Edge case handling

## Deployment

### Local Deployment

```bash
# Deploy to local Anvil network
forge script script/DeployDSC.s.sol --rpc-url http://localhost:8545 --private-key $PRIVATE_KEY --broadcast
```

### Testnet Deployment

```bash
# Deploy to Sepolia testnet
forge script script/DeployDSC.s.sol --rpc-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY --broadcast --verify --etherscan-api-key $ETHERSCAN_API_KEY
```

### Environment Variables

Create a `.env` file:

```bash
PRIVATE_KEY=your_private_key_here
SEPOLIA_RPC_URL=your_rpc_url_here
ETHERSCAN_API_KEY=your_etherscan_api_key_here
```

## Security Considerations

### Implemented Security Measures

- ✅ **Reentrancy Guards**: All external functions protected
- ✅ **Integer Overflow Protection**: Solidity 0.8.30+ built-in protection
- ✅ **Access Control**: Proper ownership and permission patterns
- ✅ **Input Validation**: Comprehensive input sanitization
- ✅ **Price Feed Validation**: Chainlink oracle integration

### Known Limitations

- 🚨 **Oracle Dependency**: System relies on Chainlink price feeds
- 🚨 **Liquidation Risk**: Rapid price movements could affect system stability
- 🚨 **Collateral Risk**: Limited to WETH and WBTC initially

## Contributing

Contributions are welcome! Please follow these steps:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request


## Learning Resources

This project demonstrates:

- DeFi protocol development
- Solidity smart contract patterns
- Foundry testing framework
- Chainlink oracle integration
- OpenZeppelin contract libraries

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

