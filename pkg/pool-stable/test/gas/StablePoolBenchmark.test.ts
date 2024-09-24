/* eslint-disable @typescript-eslint/no-non-null-assertion */
import { BaseContract } from 'ethers';
import { deploy, deployedAt } from '@balancer-labs/v3-helpers/src/contract';
import { fp } from '@balancer-labs/v3-helpers/src/numbers';
import { ZERO_BYTES32, ZERO_ADDRESS } from '@balancer-labs/v3-helpers/src/constants';
import { MONTH } from '@balancer-labs/v3-helpers/src/time';
import * as expectEvent from '@balancer-labs/v3-helpers/src/test/expectEvent';
import { StablePoolFactory } from '@balancer-labs/v3-pool-stable/typechain-types';
import { PoolRoleAccountsStruct } from '@balancer-labs/v3-vault/typechain-types/contracts/Vault';

import { Benchmark } from '@balancer-labs/v3-benchmarks/src/PoolBenchmark.behavior';

class StablePoolBenchmark extends Benchmark {
  AMPLIFICATION_PARAMETER = 200n;

  constructor(dirname: string) {
    super(dirname, 'StablePool');
  }

  override async deployPool(): Promise<BaseContract> {
    const factory = (await deploy('v3-pool-stable/StablePoolFactory', {
      args: [await this.vault.getAddress(), MONTH * 12, '', ''],
    })) as unknown as StablePoolFactory;

    const poolRoleAccounts: PoolRoleAccountsStruct = {
      pauseManager: ZERO_ADDRESS,
      swapFeeManager: ZERO_ADDRESS,
      poolCreator: ZERO_ADDRESS,
    };

    const enableDonation = true;

    const tx = await factory.create(
      'StablePool',
      'Test',
      this.tokenConfig,
      this.AMPLIFICATION_PARAMETER,
      poolRoleAccounts,
      fp(0.1),
      ZERO_ADDRESS,
      enableDonation,
      false, // keep support to unbalanced add/remove liquidity
      ZERO_BYTES32
    );
    const receipt = await tx.wait();
    const event = expectEvent.inReceipt(receipt, 'PoolCreated');

    const pool = (await deployedAt('v3-pool-stable/StablePool', event.args.pool)) as unknown as BaseContract;
    return pool;
  }
}

describe('StablePool Gas Benchmark', function () {
  new StablePoolBenchmark(__dirname).itBenchmarks();
});
