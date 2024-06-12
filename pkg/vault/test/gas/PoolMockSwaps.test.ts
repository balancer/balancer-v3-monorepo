/* eslint-disable @typescript-eslint/no-non-null-assertion */
import { BaseContract } from 'ethers';
import { deploy } from '@balancer-labs/v3-helpers/src/contract';
import { MONTH } from '@balancer-labs/v3-helpers/src/time';

import { Benchmark } from '@balancer-labs/v3-benchmarks/src/SwapBenchmark.behavior';
import { PoolFactoryMock } from '@balancer-labs/v3-vault/typechain-types';

class PoolMockBenchmark extends Benchmark {
  constructor(dirname: string) {
    super(dirname, 'PoolMock');
  }

  override async deployPool(): Promise<BaseContract> {
    const factory = (await deploy('PoolFactoryMock', {
      args: [await this.vault.getAddress(), MONTH * 12],
    })) as unknown as PoolFactoryMock;

    const pool = await deploy('PoolMock', { args: [this.vault, 'Pool Mock', 'MOCK'] });

    await factory.registerTestPool(pool, this.tokenConfig);

    return pool as unknown as BaseContract;
  }
}

describe('PoolMock Gas Benchmark', function () {
  new PoolMockBenchmark(__dirname).itBenchmarksSwap();
});
