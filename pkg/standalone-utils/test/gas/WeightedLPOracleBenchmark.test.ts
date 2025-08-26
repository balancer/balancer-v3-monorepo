import { BaseContract } from 'ethers';

import { LPOracleBenchmark, OracleInfo, PoolInfo } from '@balancer-labs/v3-benchmarks/src/OracleBenchmark.behavior';
import { deploy, deployedAt } from '@balancer-labs/v3-helpers/src/contract';
import { WeightedPoolFactory } from '@balancer-labs/v3-pool-weighted/typechain-types';
import { MONTH } from '@balancer-labs/v3-helpers/src/time';
import { ZERO_ADDRESS } from '@balancer-labs/v3-helpers/src/constants';
import { PoolRoleAccountsStruct } from '@balancer-labs/v3-vault/typechain-types/contracts/Vault';
import { buildTokenConfig } from '@balancer-labs/v3-helpers/src/models/tokens/tokenConfig';
import { fp } from '@balancer-labs/v3-helpers/src/numbers';
import { ZERO_BYTES32 } from '@balancer-labs/v3-helpers/src/constants';
import * as expectEvent from '@balancer-labs/v3-helpers/src/test/expectEvent';
import { AggregatorV3Interface } from '@balancer-labs/v3-interfaces/typechain-types';

class WeightedLPOracleBenchmark extends LPOracleBenchmark {
  constructor(dirname: string) {
    super(dirname, 'WeightedLPOracle', 2, 6);
  }

  override async deployPool(poolTokens: string[]): Promise<PoolInfo> {
    const factory = (await deploy('v3-pool-weighted/WeightedPoolFactory', {
      args: [await this.vault.getAddress(), MONTH * 12, '', ''],
    })) as unknown as WeightedPoolFactory;

    const poolRoleAccounts: PoolRoleAccountsStruct = {
      pauseManager: ZERO_ADDRESS,
      swapFeeManager: ZERO_ADDRESS,
      poolCreator: ZERO_ADDRESS,
    };

    const enableDonation = true;

    // Equal weights
    const weights = [];

    for (let i = 0; i < poolTokens.length; i++) {
      weights.push(fp(1 / poolTokens.length));
    }
    const sumWeights = weights.reduce((acc, weight) => acc + weight, fp(0));
    // Sum of weights must be 1, so we adjust the first weight to absorb any rounding issue.
    weights[0] = weights[0] + (fp(1) - sumWeights);

    const tx = await factory.create(
      'WeightedPool',
      'Test',
      buildTokenConfig(poolTokens),
      weights,
      poolRoleAccounts,
      fp(0.1),
      ZERO_ADDRESS,
      enableDonation,
      false, // keep support to unbalanced add/remove liquidity
      ZERO_BYTES32
    );
    const receipt = await tx.wait();
    const event = expectEvent.inReceipt(receipt, 'PoolCreated');

    const pool = (await deployedAt('v3-pool-weighted/WeightedPool', event.args.pool)) as unknown as BaseContract;
    return {
      pool: pool,
      poolTokens: poolTokens,
    };
  }

  override async deployOracle(
    poolAddress: string,
    feeds: AggregatorV3Interface[],
    uptimeSequencerFeed: AggregatorV3Interface,
    uptimeGracePeriod: bigint
  ): Promise<OracleInfo> {
    const oracle = (await deploy('v3-standalone-utils/WeightedLPOracleMock', {
      args: [await this.vault.getAddress(), poolAddress, feeds, uptimeSequencerFeed, uptimeGracePeriod, 1],
    })) as unknown as AggregatorV3Interface;
    return {
      oracle: oracle,
    };
  }
}

describe('WeightedLPOracle Gas Benchmark', function () {
  new WeightedLPOracleBenchmark(__dirname).itBenchmarks();
});
