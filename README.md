# Mainnet Project

**Estimated timeline:** 1 - 2 weeks

## Description

A smart contract for collective ownership of an asset and distribution of profits of said asset.

The contract has a guardian account with special privileges to execute arbitrary transactions for the contract.

The purpose of this feature is to enable the contract to invest collected revenues and liquidate said investments in order to make the funds available for withdraw.

The given asset can be digital, physical, intellectual, etc.

In the event the asset is on-chain, the contract's guardian can make the contract the owner of the asset.

## Features

1. The contract is ERC20 compliant and provides tokens that represent shares of the given asset. Users can purchase and transfer tokens.
2. The contract's guardian can execute arbitrary transactions.
3. Collected revenues are made available to token owners for withdrawl, according to a schedule, via a `withdraw()` method.
   - Users can withdraw funds from the most recently closed collection period according to their share of tokens.
4. Deploy the contract on Arbitrum Mainnet.
5. Write an extensible base contract and then extend it with one of the following
   i. A proposal system for buying/selling assets.
   ii. A multisig for buying/selling assets.
   iii. A white list implemented with a merkle tree.
   iv. A way to to track revenue events on-chain, such as a streaming service reporting a number of streams, or a 3rd party reporting the use of a rented NFT
   v. Compensate token holders not only based on the number of tokens they hold, but also for the portion of the given collection period those tokens were owned for

## External Dependencies

1. Arbitrum
