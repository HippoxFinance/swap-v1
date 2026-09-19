# swap-v1

EVM network smart contracts for the HippoxOS token trading system — a decentralized exchange (DEX).

## Overview

hippox-swap-v1 is the core trading protocol of the HippoxOS ecosystem, providing decentralized swapping and liquidity services for tokens.

## Core Features

- Token Swapping: Decentralized token-to-token exchange based on an automated market maker (AMM) mechanism.
- Liquidity Pools: Users can provide liquidity, receive LP tokens as proof of deposit, and earn trading fees.
- Liquidity Management: Supports adding/removing liquidity and redeeming underlying assets by share.
- Price Discovery: Exchange prices are determined automatically by pool reserves via a pricing curve.

## Project Structure

src/ Core trading contracts
test/ Tests
script/ Deployment and interaction scripts

## Development

Build: forge build
Test: forge test
Local node: anvil
Deploy: forge script script/Deploy.s.sol --rpc-url <your_rpc_url> --private-key <your_private_key>
