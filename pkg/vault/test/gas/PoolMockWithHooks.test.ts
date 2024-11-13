/* eslint-disable @typescript-eslint/no-non-null-assertion */
import { BaseContract } from 'ethers';
import { deploy } from '@balancer-labs/v3-helpers/src/contract';
import { MONTH } from '@balancer-labs/v3-helpers/src/time';
import { buildTokenConfig } from '@balancer-labs/v3-helpers/src/models/tokens/tokenConfig';

import { Benchmark, PoolTag, PoolInfo } from '@balancer-labs/v3-benchmarks/src/PoolBenchmark.behavior';
import { PoolFactoryMock, MinimalHooksPoolMock } from '@balancer-labs/v3-vault/typechain-types';
import { ZERO_ADDRESS } from '@balancer-labs/v3-helpers/src/constants';
import { LiquidityManagementStruct, PoolRoleAccountsStruct } from '../../typechain-types/contracts/Vault';

class PoolMockWithHooksBenchmark extends Benchmark {
  constructor(dirname: string) {
    super(dirname, 'PoolMockWithHooks');
  }

  override async deployPool(tag: PoolTag, poolTokens: string[], withRate: boolean): Promise<PoolInfo> {
    const factory = (await deploy('PoolFactoryMock', {
      args: [await this.vault.getAddress(), MONTH * 12],
    })) as unknown as PoolFactoryMock;

    const hooks = (await deploy('MinimalHooksPoolMock')) as unknown as MinimalHooksPoolMock;

    await hooks.setHookFlags({
      enableHookAdjustedAmounts: false,
      shouldCallBeforeInitialize: true,
      shouldCallAfterInitialize: true,
      shouldCallComputeDynamicSwapFee: true,
      shouldCallBeforeSwap: true,
      shouldCallAfterSwap: true,
      shouldCallBeforeAddLiquidity: true,
      shouldCallAfterAddLiquidity: true,
      shouldCallBeforeRemoveLiquidity: true,
      shouldCallAfterRemoveLiquidity: true,
    });

    const pool: string = await deploy('PoolMock', { args: [this.vault, 'Pool Mock', 'MOCK'] });

    const roleAccounts: PoolRoleAccountsStruct = {
      poolCreator: ZERO_ADDRESS,
      pauseManager: ZERO_ADDRESS,
      swapFeeManager: ZERO_ADDRESS,
    };

    const liquidityManagement: LiquidityManagementStruct = {
      disableUnbalancedLiquidity: false,
      enableAddLiquidityCustom: true,
      enableRemoveLiquidityCustom: true,
      enableDonation: true,
    };

    await factory.registerPool(pool, buildTokenConfig(poolTokens, withRate), roleAccounts, hooks, liquidityManagement);

    return {
      pool: pool as unknown as BaseContract,
      poolTokens: poolTokens,
    };
  }
}

describe('PoolMock with Hooks Gas Benchmark', function () {
  new PoolMockWithHooksBenchmark(__dirname).itBenchmarks();
});
