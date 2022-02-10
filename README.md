# Revenue Splitter

## Description

Revenue Splitter is an extensible smart contract for splitting revenues according to shares owned.

For example, a Revenue Splitter contract can facilitate multiple actors raising funds by purchasing shares (ERC20 tokens) to purchase an asset(s), such as NFTs, Liquidity Provider tokens, or "real-world" assets such as cars or real estate.

Revenue incurred on selling or renting out assets owned by the contract can then be distributed (withdrawn) by share owners.

While this contract has an ever-powerful "owner", this role can be replaced by DAO governance mechanisms.

## Core Features

1. The contract is ERC20 compliant and provides tokens that represent shares of the given asset. Users can purchase and transfer tokens.

2. Collected revenues are made available to token owners for withdrawal, according to a schedule, via a `withdraw()` method.

3. The contract's owner can execute lists of arbitrary transactions for the sake of purchasing, liquidating, and withdrawing value from assets (e.g. withdrawing revenue from LP tokens to the contract).

4. The contract is extensible, enabling customization.

## Notes on the Revenue/Withdrawal Schedule

The complex part of this contract is the schedule by which token (share) owners can withdraw their share of revenue.

Each period is 30 days long, after which the period can be ended (and a new one started) using `startNewPeriod()`.

When a period has ended, the revenues from that period can then be withdrawn by token owners.

--

After the first revenue period, token purchases are awarded "token grants" that vest after a the following 2 revenue periods have ended. This is for the sake of decentivizing investors from purchasing shares right before hefty revenues are open for withdrawal.

Once token grants have vested they are availalbe to be redeemed for tokens, which, in the same period, can be used to withdraw corresponding proportions of revenue.

The contract has a 3 day blackout period following each period's end where revenue shares cannot be withdrawn but vested token grants can be redeemed for tokens. This is to insure that token grant holders have an opportunity to redeem their tokens before revenues can be withdrawn by other token holders.
