/* eslint-disable @typescript-eslint/no-non-null-assertion */
import { BaseContract } from 'ethers';
import { deploy, deployedAt } from '@balancer-labs/v3-helpers/src/contract';
import { fp } from '@balancer-labs/v3-helpers/src/numbers';
import { ZERO_BYTES32, ZERO_ADDRESS } from '@balancer-labs/v3-helpers/src/constants';
import { MONTH } from '@balancer-labs/v3-helpers/src/time';
import * as expectEvent from '@balancer-labs/v3-helpers/src/test/expectEvent';
import { GyroECLPPoolFactory } from '@balancer-labs/v3-pool-gyro/typechain-types';
import { PoolRoleAccountsStruct } from '@balancer-labs/v3-vault/typechain-types/contracts/Vault';
import { buildTokenConfig } from '@balancer-labs/v3-helpers/src/models/tokens/tokenConfig';
import { Benchmark, PoolTag, PoolInfo } from '@balancer-labs/v3-benchmarks/src/PoolBenchmark.behavior';

class ECLPPoolBenchmark extends Benchmark {
  constructor(dirname: string) {
    super(dirname, 'ECLPPool', {
      disableNestedPoolTests: true, // Pool does not support 3 tokens
    });
  }

  override async deployPool(tag: PoolTag, poolTokens: string[], withRate: boolean): Promise<PoolInfo> {
    const factory = (await deploy('v3-pool-gyro/GyroECLPPoolFactory', {
      args: [await this.vault.getAddress(), MONTH * 12, '', ''],
    })) as unknown as GyroECLPPoolFactory;

    const poolRoleAccounts: PoolRoleAccountsStruct = {
      pauseManager: ZERO_ADDRESS,
      swapFeeManager: ZERO_ADDRESS,
      poolCreator: ZERO_ADDRESS,
    };

    const enableDonation = true;

    const eclpParams = {
      alpha: 998502246630054917n,
      beta: 1000200040008001600n,
      c: 707106781186547524n,
      s: 707106781186547524n,
      lambda: 4000000000000000000000n,
    };

    const derivedEclpParams = {
      tauAlpha: { x: -94861212813096057289512505574275160547n, y: 31644119574235279926451292677567331630n },
      tauBeta: { x: 37142269533113549537591131345643981951n, y: 92846388265400743995957747409218517601n },
      u: 66001741173104803338721745994955553010n,
      v: 62245253919818011890633399060291020887n,
      w: 30601134345582732000058913853921008022n,
      z: -28859471639991253843240999485797747790n,
      dSq: 99999999999999999886624093342106115200n,
    };

    const tx = await factory.create(
      'ECLPPool',
      'Test',
      buildTokenConfig(poolTokens, withRate),
      eclpParams,
      derivedEclpParams,
      poolRoleAccounts,
      fp(0.1),
      ZERO_ADDRESS,
      enableDonation,
      false, // keep support to unbalanced add/remove liquidity
      ZERO_BYTES32
    );
    const receipt = await tx.wait();
    const event = expectEvent.inReceipt(receipt, 'PoolCreated');

    const pool = (await deployedAt('v3-pool-gyro/GyroECLPPool', event.args.pool)) as unknown as BaseContract;
    return {
      pool: pool,
      poolTokens: poolTokens,
    };
  }
}

describe.only('ECLPPool Gas Benchmark', function () {
  new ECLPPoolBenchmark(__dirname).itBenchmarks();
});
