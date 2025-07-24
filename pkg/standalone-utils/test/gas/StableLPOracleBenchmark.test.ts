import { BaseContract } from 'ethers';

import { LPOracleBenchmark, OracleInfo, PoolInfo } from '@balancer-labs/v3-benchmarks/src/OracleBenchmark.behavior';
import { deploy, deployedAt } from '@balancer-labs/v3-helpers/src/contract';
import { StablePoolFactory } from '@balancer-labs/v3-pool-stable/typechain-types';
import { MONTH } from '@balancer-labs/v3-helpers/src/time';
import { ZERO_ADDRESS } from '@balancer-labs/v3-helpers/src/constants';
import { PoolRoleAccountsStruct } from '@balancer-labs/v3-vault/typechain-types/contracts/Vault';
import { buildTokenConfig } from '@balancer-labs/v3-helpers/src/models/tokens/tokenConfig';
import { fp } from '@balancer-labs/v3-helpers/src/numbers';
import { ZERO_BYTES32 } from '@balancer-labs/v3-helpers/src/constants';
import * as expectEvent from '@balancer-labs/v3-helpers/src/test/expectEvent';
import { AggregatorV3Interface } from '@balancer-labs/v3-interfaces/typechain-types';

class StableLPOracleBenchmark extends LPOracleBenchmark {
  constructor(dirname: string) {
    super(dirname, 'StableLPOracle');
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
      buildTokenConfig(poolTokens),
      4567,
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

  override async deployOracle(poolAddress: string, feeds: AggregatorV3Interface[]): Promise<OracleInfo> {
    const oracle = (await deploy('v3-standalone-utils/StableLPOracleMock', {
      args: [await this.vault.getAddress(), poolAddress, feeds, 1],
    })) as unknown as AggregatorV3Interface;
    return {
      oracle: oracle,
    };
  }
}

describe('StableOracle Gas Benchmark', function () {
  new StableLPOracleBenchmark(__dirname).itBenchmarks();
});
