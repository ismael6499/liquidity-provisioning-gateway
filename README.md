# 🌊 DeFi Zap Protocol: Atomic Liquidity Provisioning

![Solidity](https://img.shields.io/badge/Solidity-0.8.24-363636?style=flat-square&logo=solidity)
![Pattern](https://img.shields.io/badge/Pattern-Zapping-blueviolet?style=flat-square)
![Testing](https://img.shields.io/badge/Testing-Arbitrum_Fork-bf4904?style=flat-square)

A smart contract gateway that streamlines Liquidity Pool (LP) interactions. It implements **"Zapping"** logic, allowing users to enter and exit AMM positions with a single asset in a single atomic transaction.

## 🚀 Technical Context

In Decentralized Finance, providing liquidity to an Automated Market Maker (AMM) typically introduces significant UX friction and gas inefficiency. A user holding a single asset (e.g., USDT) must manually:
1.  Calculate the optimal split ratio.
2.  Swap 50% of the asset.
3.  Approve Token A.
4.  Approve Token B.
5.  Deposit liquidity.

This project implements an **On-Chain Facade Pattern** to abstract this complexity. By leveraging atomic execution, the protocol performs the mathematical balancing, router selection, and token deposit in a single block execution.

## 🏗 Architecture & Design Decisions

### 1. Atomic "Zapping" (Gas Optimization)
* **Mechanism:** The `addLiquidity` function calculates the optimal swap amount to ensure a perfect 50/50 value split after fees.
* **Atomicity:** It executes the swap and the deposit in the same transaction. This eliminates "dust" (leftover tokens) and protects the user from price slippage between manual transactions.
* **Result:** Reduces ~4 user transactions into 1 contract call.

### 2. Dynamic Asset Discovery
* **Pattern:** Instead of hardcoding LP Token addresses, the contract queries the `IV2Factory` of the selected Router (Uniswap/SushiSwap) at runtime.
* **Interoperability:** The protocol is router-agnostic. It can interact with any V2-compatible fork without redeployment, provided the router address is whitelisted.

### 3. Integration Testing: Mainnet Forking
* **Strategy:** The test suite utilizes Foundry to **fork the Arbitrum One Mainnet**.
* **Validation:** Tests are executed against live liquidity pools (e.g., SushiSwap USDT/DAI), simulating real market conditions to verify that the user receives the correct amount of LP tokens.

## 🛠 Tech Stack

* **Core:** Solidity `0.8.24`
* **Integrations:** Uniswap V2 / SushiSwap V2 Interfaces
* **Testing:** Foundry (Mainnet Forking, Fuzzing)
* **Security:** OpenZeppelin `SafeERC20`, `Pausable`

## 📝 Contract Interface

The protocol exposes a simplified interface for single-asset entry and exit:

```solidity
// Enters a pool with a single token (e.g., USDT -> USDT/DAI LP)
function addLiquidity(
    uint256 amountIn, 
    uint256 minOut, 
    address[] path, 
    uint256 minA, 
    uint256 minB, 
    uint256 deadline
) external;

// Exits a pool to a single token (e.g., USDT/DAI LP -> USDT)
function removeLiquidity(
    address tokenA, 
    address tokenB, 
    uint256 liquidityAmount, 
    ...
) external;

```
