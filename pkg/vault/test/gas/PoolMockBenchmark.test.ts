/* eslint-disable @typescript-eslint/no-non-null-assertion */
import { BaseContract } from 'ethers';
import { deploy } from '@balancer-labs/v3-helpers/src/contract';
import { MONTH } from '@balancer-labs/v3-helpers/src/time';
import { buildTokenConfig } from '@balancer-labs/v3-helpers/src/models/tokens/tokenConfig';

import { Benchmark, PoolTag, PoolInfo } from '@balancer-labs/v3-benchmarks/src/PoolBenchmark.behavior';
import { PoolFactoryMock } from '@balancer-labs/v3-vault/typechain-types';
import { ZERO_ADDRESS } from '@balancer-labs/v3-helpers/src/constants';

import { LiquidityManagementStruct, PoolRoleAccountsStruct } from '../../typechain-types/contracts/Vault';

class PoolMockBenchmark extends Benchmark {
  constructor(dirname: string) {
    super(dirname, 'PoolMock');
  }

  override async deployPool(tag: PoolTag, poolTokens: string[], withRate: boolean): Promise<PoolInfo> {
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

    await factory.registerPool(
      pool,
      buildTokenConfig(poolTokens, withRate),
      roleAccounts,
      ZERO_ADDRESS,
      liquidityManagement
    );

    return {
      pool: pool as unknown as BaseContract,
      poolTokens: poolTokens,
    };
  }
}

describe('PoolMock Gas Benchmark', function () {
  new PoolMockBenchmark(__dirname).itBenchmarks();
});
