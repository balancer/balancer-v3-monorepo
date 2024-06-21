/* eslint-disable @typescript-eslint/no-non-null-assertion */
import { BaseContract } from 'ethers';
import { deploy } from '@balancer-labs/v3-helpers/src/contract';
import { MONTH } from '@balancer-labs/v3-helpers/src/time';

import { Benchmark } from '@balancer-labs/v3-benchmarks/src/SwapBenchmark.behavior';
import { PoolFactoryMock } from '@balancer-labs/v3-vault/typechain-types';
import { ANY_ADDRESS, ZERO_ADDRESS } from '@balancer-labs/v3-helpers/src/constants';
import { LiquidityManagementStruct, PoolRoleAccountsStruct } from '../../typechain-types/contracts/Vault';

class PoolMockBenchmark extends Benchmark {
  constructor(dirname: string) {
    super(dirname, 'PoolMock');
  }

  override async deployPool(): Promise<BaseContract> {
    const factory = (await deploy('PoolFactoryMock', {
      args: [await this.vault.getAddress(), MONTH * 12],
    })) as unknown as PoolFactoryMock;

    const pool: string = await deploy('PoolMock', { args: [this.vault, 'Pool Mock', 'MOCK'] });

    const roleAccounts: PoolRoleAccountsStruct = {
      poolCreator: ZERO_ADDRESS,
      pauseManager: ZERO_ADDRESS,
      swapFeeManager: ZERO_ADDRESS,
    };

    const liquidityManagement: LiquidityManagementStruct = {
      disableUnbalancedLiquidity: false,
      enableAddLiquidityCustom: false,
      enableRemoveLiquidityCustom: false,
      enableDonation: true,
    };

    await factory.registerPool(pool, this.tokenConfig, roleAccounts, ZERO_ADDRESS, liquidityManagement);

    return pool as unknown as BaseContract;
  }
}

describe('PoolMock Gas Benchmark', function () {
  new PoolMockBenchmark(__dirname).itBenchmarksSwap();
});
