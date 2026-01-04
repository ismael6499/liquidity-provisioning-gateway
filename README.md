# ⚡ Smart Router Core: Best Execution Aggregator

A gas-optimized DEX aggregation protocol that routes trades across multiple liquidity sources (Uniswap V2, SushiSwap, etc.) to guarantee the best price execution for users.

## 🚀 Engineering Context

As a **Java Software Engineer**, handling high availability typically involves a Load Balancer (like NGINX) distributing traffic across healthy microservices. If one service fails, the balancer detects it and reroutes requests.

In **DeFi**, liquidity is fragmented across multiple protocols. This project implements an on-chain **Smart Order Router (SOR)**. Unlike a standard swap, this contract queries multiple endpoints (Routers) dynamically. Crucially, it implements a **Circuit Breaker** pattern using Solidity's `try/catch` syntax: if one liquidity source is down or reverts, the protocol seamlessly skips it and continues execution, ensuring the user's transaction never fails due to third-party instability.

## 💡 Project Overview

**Smart Router Core** acts as a proxy execution layer. It accepts a user's trade intent, queries a whitelist of on-chain routers, and executes the swap via the provider offering the highest output amount.

### 🔍 Key Technical Features:

* **Fault-Tolerant Routing (`try/catch`):**
    * **Architecture:** The `getBestQuote` function iterates through external contracts.
    * **Resilience:** Instead of allowing a single reverting router to bubble up an exception and revert the entire transaction, I handled external calls with low-level `try/catch` blocks. This ensures 100% uptime for the aggregator even if a connected DEX suffers an outage.

* **Dynamic Whitelisting & Storage Optimization:**
    * **Data Structures:** Implemented an array with an auxiliary mapping (`O(1)` lookups) for router management.
    * **Gas Efficiency:** Used the "Swap-and-Pop" idiom in `removeRouter` to delete elements from the array without leaving gaps or shifting elements (saving significant gas on admin operations).

* **Arbitrum Mainnet Fork Testing:**
    * **Methodology:** The test suite does not run on a blank chain. It forks the **Arbitrum Mainnet** state to test against *real* deployed liquidity pools (Uniswap, SushiSwap) and real tokens (USDT, DAI), validating the integration in a production-mirror environment.

* **Fuzzing & Invariants:**
    * Extensive usage of Foundry's `testFuzz` to validate fee calculations and solvency invariants across random input amounts and boundary conditions.

## 🛠️ Stack & Tools

* **Language:** Solidity `0.8.24`.
* **Framework:** Foundry (Forge).
    * *Highlights:* Mainnet Forking, Fuzz Testing, Mocking.
* **Network Target:** EVM Compatible (Tested on Arbitrum One).

---

*This repository contains the settlement and routing logic for decentralized trading execution.*