/* eslint-disable @typescript-eslint/no-non-null-assertion */
import { BaseContract } from 'ethers';
import { deploy, deployedAt } from '@balancer-labs/v3-helpers/src/contract';
import { fp } from '@balancer-labs/v3-helpers/src/numbers';
import { ZERO_BYTES32, ZERO_ADDRESS } from '@balancer-labs/v3-helpers/src/constants';
import { MONTH } from '@balancer-labs/v3-helpers/src/time';
import * as expectEvent from '@balancer-labs/v3-helpers/src/test/expectEvent';
import { WeightedPoolFactory } from '@balancer-labs/v3-pool-weighted/typechain-types';
import { PoolRoleAccountsStruct } from '@balancer-labs/v3-vault/typechain-types/contracts/Vault';

import { Benchmark } from '@balancer-labs/v3-benchmarks/src/PoolBenchmark.behavior';

class WeightedPoolBenchmark extends Benchmark {
  WEIGHTS = [fp(0.5), fp(0.5)];

  constructor(dirname: string) {
    super(dirname, 'WeightedPool');
  }

  override async deployPool(): Promise<BaseContract> {
    const factory = (await deploy('v3-pool-weighted/WeightedPoolFactory', {
      args: [await this.vault.getAddress(), MONTH * 12, '', ''],
    })) as unknown as WeightedPoolFactory;

    const poolRoleAccounts: PoolRoleAccountsStruct = {
      pauseManager: ZERO_ADDRESS,
      swapFeeManager: ZERO_ADDRESS,
      poolCreator: ZERO_ADDRESS,
    };

    const enableDonation = true;

    const tx = await factory.create(
      'WeightedPool',
      'Test',
      this.tokenConfig,
      this.WEIGHTS,
      poolRoleAccounts,
      fp(0.1),
      ZERO_ADDRESS,
      enableDonation,
      false, // Do not disable add liquidity unbalanced
      false, // Do not disable remove liquidity unbalanced
      ZERO_BYTES32
    );
    const receipt = await tx.wait();
    const event = expectEvent.inReceipt(receipt, 'PoolCreated');

    const pool = (await deployedAt('v3-pool-weighted/WeightedPool', event.args.pool)) as unknown as BaseContract;
    return pool;
  }
}

describe('WeightedPool Gas Benchmark', function () {
  new WeightedPoolBenchmark(__dirname).itBenchmarks();
});
