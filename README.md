# 🏰 Loot Dungeon

A composable system for going on adventures with your Loot / synthetic Loot / More Loot.

High level:

- a `Player` is either the owner of a Loot token or More Loot token, or just any address (we then use their synthetic loot)
- there is a central `AdventureRegistry` contract, that knows about what adventures are available to players and is responsible for making sure players are only in a single adventure
- an `Adventure` is a contract that has:
    - requirements for entering (e.g. based on player level, specific pieces of loot, or number of players in the party)
    - a time to complete the adventure
    - offers some rewards for completion
- a `Reward` is a contract that holds balances for players.
    - `Experience` is a non-transferable kind of reward

In the case of real Loot / More Loot, the rewards are attached to the NFT itself. So if someone plays with their Loot #X until it gets level 5, that token will still be level 5 even if the token is transferred to a new owner.

## Quick Start

Contracts: https://github.com/karmacoma-eth/loot-dungeon/tree/main/packages/hardhat/contracts

Compile with 

```
yarn compile
```

## Misc

Based on 🏗 [scaffold-eth](https://github.com/austintgriffith/scaffold-eth.git)
