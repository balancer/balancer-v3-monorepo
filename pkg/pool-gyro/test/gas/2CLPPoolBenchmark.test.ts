/* eslint-disable @typescript-eslint/no-non-null-assertion */
import { BaseContract } from 'ethers';
import { deploy, deployedAt } from '@balancer-labs/v3-helpers/src/contract';
import { fp } from '@balancer-labs/v3-helpers/src/numbers';
import { ZERO_BYTES32, ZERO_ADDRESS } from '@balancer-labs/v3-helpers/src/constants';
import { MONTH } from '@balancer-labs/v3-helpers/src/time';
import * as expectEvent from '@balancer-labs/v3-helpers/src/test/expectEvent';
import { Gyro2CLPPoolFactory } from '@balancer-labs/v3-pool-gyro/typechain-types';
import { PoolRoleAccountsStruct } from '@balancer-labs/v3-vault/typechain-types/contracts/Vault';
import { buildTokenConfig } from '@balancer-labs/v3-helpers/src/models/tokens/tokenConfig';
import { Benchmark, PoolTag, PoolInfo } from '@balancer-labs/v3-benchmarks/src/PoolBenchmark.behavior';

class Gyro2CLPPoolBenchmark extends Benchmark {
  constructor(dirname: string) {
    super(dirname, 'Gyro2CLPPool', {
      disableNestedPoolTests: true, // Pool does not support 3 tokens
    });
  }

  override async deployPool(tag: PoolTag, poolTokens: string[], withRate: boolean): Promise<PoolInfo> {
    const factory = (await deploy('v3-pool-gyro/Gyro2CLPPoolFactory', {
      args: [await this.vault.getAddress(), MONTH * 12, '', ''],
    })) as unknown as Gyro2CLPPoolFactory;

    const poolRoleAccounts: PoolRoleAccountsStruct = {
      pauseManager: ZERO_ADDRESS,
      swapFeeManager: ZERO_ADDRESS,
      poolCreator: ZERO_ADDRESS,
    };

    const enableDonation = true;

    const sqrtAlpha = 997496867163000167n;
    const sqrtBeta = 1002496882788171068n;

    const tx = await factory.create(
      'Gyro2CLPPool',
      'Test',
      buildTokenConfig(poolTokens, withRate),
      sqrtAlpha,
      sqrtBeta,
      poolRoleAccounts,
      fp(0.1),
      ZERO_ADDRESS,
      enableDonation,
      false, // keep support to unbalanced add/remove liquidity
      ZERO_BYTES32
    );
    const receipt = await tx.wait();
    const event = expectEvent.inReceipt(receipt, 'PoolCreated');

    const pool = (await deployedAt('v3-pool-gyro/Gyro2CLPPool', event.args.pool)) as unknown as BaseContract;
    return {
      pool: pool,
      poolTokens: poolTokens,
    };
  }
}

describe('Gyro2CLPPool Gas Benchmark', function () {
  new Gyro2CLPPoolBenchmark(__dirname).itBenchmarks();
});
