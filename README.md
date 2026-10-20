# MultiSig Wallet

A multi-signature wallet written from scratch in Solidity. A transaction only executes after a set number of owners approve it. Built with Hardhat 3 and tested with a full Foundry-style test suite.

## How it works

1. An owner **submits** a transaction (send ETH, call a contract, or both)
2. Owners **confirm** it, and can **revoke** a confirmation before execution
3. Once confirmations reach the threshold, any owner **executes** it

Example: 3 owners with a threshold of 2 means any 2 owners must approve before funds move.

## Security design

- Constructor rejects zero-address owners, duplicate owners, and invalid thresholds
- Modifiers enforce ownership, transaction existence, and non-execution on every action
- Each owner can confirm a transaction only once
- `executed` is set before the external call (checks-effects-interactions), preventing double execution
- Failed calls revert the whole transaction, so it stays pending and can be retried
- Custom errors for clear, gas-efficient reverts

## Tests

21 Solidity tests using `forge-std`, run through Hardhat 3:

- Constructor validation: zero threshold, threshold above owner count, duplicate and zero-address owners
- ETH deposits and `Deposit` event
- Submitting, confirming, and revoking, including access control for non-owners
- Executing ETH transfers and arbitrary contract calls
- Reverts for insufficient confirmations, double execution, and double confirmation
- Revoking below the threshold blocks execution
- Failed calls roll back and leave the transaction pending
- Fuzz test: executed transfers always send the exact amount (256 runs)

## Running locally

    npm install
    npx hardhat compile
    npx hardhat test

## Tech

Solidity 0.8.x · Hardhat 3 · forge-std