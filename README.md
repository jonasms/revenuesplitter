# Revenue Splitter

## Description

Revenue Splitter is an extensible smart contract for splitting revenues according to shares owned.

For example, a Revenue Splitter contract can facilitate multiple actors raising funds by purchasing shares (ERC20 tokens) to purchase an asset(s), such as NFTs, Liquidity Provider tokens, or "real-world" assets such as cars or real estate.

Revenue incurred on selling or renting out assets owned by the contract can then be distributed (withdrawn) by share owners.

While this contract has an ever-powerful "owner", this role can be replaced by DAO governance mechanisms.

## Core Features

1. The contract is ERC20 compliant and provides tokens that represent shares of the given asset. Users can purchase and transfer tokens.

2. Collected revenues are made available to token owners for withdrawl, according to a schedule, via a `withdraw()` method.

3. The contract's owner can execute lists arbitrary transactions for the sake of purchasing, liquidating, and withdrawing value from assets (e.g. withdrawing revenue from LP tokens to the contract).

4. The contract is extensible, enabling customization.
