import { expect } from 'chai';
import { Dictionary } from 'lodash';
import { BigNumberish, Contract } from 'ethers';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';

import { bn } from '../numbers';
import ERC20TokenList from '../models/tokens/ERC20TokenList';
import ERC20Token from '../models/tokens/ERC20Token';

// Ported from @openzeppelin/test-helpers to use with ERC20 tokens and Ethers
/* eslint-disable @typescript-eslint/no-explicit-any */

type Account = string | SignerWithAddress | Contract;
type CompareFunction =
  | 'equal'
  | 'eq'
  | 'above'
  | 'gt'
  | 'gte'
  | 'below'
  | 'lt'
  | 'lte'
  | 'least'
  | 'most'
  | 'near'
  | 'very-near';
export type Comparison = [CompareFunction, BigNumberish];

export interface BalanceChange {
  account: Account;
  changes?: Dictionary<BigNumberish | Comparison>;
}

abstract class BalanceTracker {
  private prev: bigint | undefined;

  // returns the current token balance
  async get(): Promise<bigint> {
    this.prev = await this.currentBalance();
    return this.prev;
  }

  // returns the balance difference between the current one and the
  // last call to get or delta
  async delta(): Promise<bigint> {
    const balance = await this.currentBalance();

    if (this.prev == undefined) {
      throw new Error('Tracker.get must be called before Tracker.delta');
    }

    const delta = balance - this.prev;
    this.prev = balance;

    return delta;
  }

  abstract currentBalance(): Promise<bigint>;
}

class ERC20BalanceTracker extends BalanceTracker {
  constructor(private address: string, private token: ERC20Token) {
    super();
  }

  async currentBalance(): Promise<bigint> {
    return this.token.balanceOf(this.address);
  }
}

class InternalBalanceTracker extends BalanceTracker {
  constructor(private vault: Contract, private address: string, private token: ERC20Token) {
    super();
  }

  async currentBalance(): Promise<bigint> {
    const result = await this.vault.getInternalBalance(this.address, [this.token.address]);
    return result[0];
  }
}

function accountToAddress(account: Account): string {
  return typeof account == 'string' ? account : account.address;
}

// Creates an initializes a balance tracker. Constructors cannot be async (and therefore get cannot
// be called there), so we have this helper method.
export async function balanceTracker(address: string, token: ERC20Token): Promise<ERC20BalanceTracker> {
  const tracker = new ERC20BalanceTracker(address, token);
  await tracker.get();
  return tracker;
}

export async function internalBalanceTracker(
  vault: Contract,
  address: string,
  token: ERC20Token
): Promise<InternalBalanceTracker> {
  const tracker = new InternalBalanceTracker(vault, address, token);
  await tracker.get();
  return tracker;
}

// Measures the ERC20 balance of an account for multiple tokens before and after an async operation (which
// presumably involves Ethereum transactions), and then compares the deltas to a list of expected changes.
// `tokens` can be obtained by calling `tokens.deployTokens`. Any token not specified in `balanceChanges`
// is expected to have no balance change.
//
// Sample usage, trading 50 USDC in exchange for 50 DAI
//
// await expectBalanceChange(
//   uniswap.swap('USDC', 'DAI', 50),
//   tokens,
//   { account, changes: { 'DAI': 50, 'USDC': -50 } }
// });
//
// Checks other than equality can also be performed by passing a comparison and value tuple.
//
// await expectBalanceChange(
//   uniswap.swap('USDC', 'DAI', 50),
//   tokens,
//   { account, changes: { 'DAI': 50, 'USDC': -50, 'UNI': ['gt', 0] } } // Earn an unknown amount of UNI
// });
//
// You can also track *internal* balance changes by passing an optional vault parameter
//
// await expectBalanceChange(
//   balancer.joinSwap(...),
//   tokens,
//   { account, changes: { 'DAI': 50, 'USDC': -50 } },
//   balancerVaultContract
// });
//
// Returns the result of calling `promise`.
export async function expectBalanceChange(
  promise: () => Promise<unknown>,
  tokens: ERC20TokenList,
  balanceChange: BalanceChange | Array<BalanceChange>,
  vault?: Contract
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
): Promise<any> {
  const trackers: Dictionary<Dictionary<ERC20BalanceTracker | InternalBalanceTracker>> = {};
  const balanceChanges: Array<BalanceChange> = Array.isArray(balanceChange) ? balanceChange : [balanceChange];

  for (const { account } of balanceChanges) {
    const address = accountToAddress(account);
    trackers[address] = {};

    await tokens.asyncEach(async (token) => {
      trackers[address][await token.symbol()] = vault
        ? await internalBalanceTracker(vault, address, token)
        : await balanceTracker(address, token);
    });
  }

  const result = await promise();

  for (const { account, changes } of balanceChanges) {
    const address = accountToAddress(account);
    const accountTrackers = trackers[address];

    await tokens.asyncEach(async (token) => {
      const symbol = await token.symbol();
      const delta = await accountTrackers[symbol].delta();

      const change = (changes || {})[symbol];
      if (change === undefined) {
        expect(delta, `Expected ${delta} ${symbol} to be zero`).to.equal(0);
      } else {
        const compare: CompareFunction = Array.isArray(change) ? change[0] : 'equal';
        const value = bn(Array.isArray(change) ? change[1] : change);
        const abs = (value: bigint) => (value >= 0n ? value : -value);

        if (compare == 'near') {
          const epsilon = abs(value) / 10n;
          expect(delta).to.be.at.least(value - epsilon);
          expect(delta).to.be.at.most(value + epsilon);
        } else if (compare == 'very-near') {
          const epsilon = abs(value) / 100000n;
          expect(delta).to.be.at.least(value - epsilon);
          expect(delta).to.be.at.most(value + epsilon);
        } else {
          const errorMessage = `Expected ${delta} ${symbol} to be ${compare} ${value} ${symbol}`;
          expect(delta, errorMessage).to[compare](value.toString());
        }
      }
    });
  }

  return result;
}
