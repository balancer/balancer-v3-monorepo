import { BaseContract } from 'ethers';

import { LPOracleBenchmark } from '@balancer-labs/v3-benchmarks/src/OracleBenchmark.behavior';
import { deploy, deployedAt } from '@balancer-labs/v3-helpers/src/contract';

class StableLPOracleBenchmark extends LPOracleBenchmark {
  constructor(dirname: string) {
    super(dirname, 'PoolMock');
  }

  override async deployPool(poolTokens: string[]): Promise<PoolInfo> {
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
      buildTokenConfig(poolTokens, withRate),
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
    return {
      pool: pool,
      poolTokens: poolTokens,
    };
  }
}

describe('PoolMock Gas Benchmark', function () {
  new StableLPOracleBenchmark(__dirname).itBenchmarks();
});
