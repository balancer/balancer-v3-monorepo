import { BaseContract } from 'ethers';

import { LPOracleBenchmark, OracleInfo, PoolInfo } from '@balancer-labs/v3-benchmarks/src/OracleBenchmark.behavior';
import { deploy, deployedAt } from '@balancer-labs/v3-helpers/src/contract';
import { GyroECLPPoolFactory } from '@balancer-labs/v3-pool-gyro/typechain-types';
import { MONTH } from '@balancer-labs/v3-helpers/src/time';
import { ZERO_ADDRESS } from '@balancer-labs/v3-helpers/src/constants';
import { PoolRoleAccountsStruct } from '@balancer-labs/v3-vault/typechain-types/contracts/Vault';
import { buildTokenConfig } from '@balancer-labs/v3-helpers/src/models/tokens/tokenConfig';
import { fp } from '@balancer-labs/v3-helpers/src/numbers';
import { ZERO_BYTES32 } from '@balancer-labs/v3-helpers/src/constants';
import * as expectEvent from '@balancer-labs/v3-helpers/src/test/expectEvent';
import { AggregatorV3Interface } from '@balancer-labs/v3-interfaces/typechain-types';
import { WrappedBalancerPoolToken } from '@balancer-labs/v3-vault/typechain-types';

// Extracted from pool 0x2191df821c198600499aa1f0031b1a7514d7a7d9 on Mainnet.
const PARAMS_ALPHA = 998502246630054917n;
const PARAMS_BETA = 1000200040008001600n;
const PARAMS_C = 707106781186547524n;
const PARAMS_S = 707106781186547524n;
const PARAMS_LAMBDA = 4000000000000000000000n;

const TAU_ALPHA_X = -94861212813096057289512505574275160547n;
const TAU_ALPHA_Y = 31644119574235279926451292677567331630n;
const TAU_BETA_X = 37142269533113549537591131345643981951n;
const TAU_BETA_Y = 92846388265400743995957747409218517601n;
const U = 66001741173104803338721745994955553010n;
const V = 62245253919818011890633399060291020887n;
const W = 30601134345582732000058913853921008022n;
const Z = -28859471639991253843240999485797747790n;
const DSQ = 99999999999999999886624093342106115200n;

class EclpLPOracleBenchmark extends LPOracleBenchmark {
  constructor(dirname: string) {
    super(dirname, 'EclpLPOracle', 2, 2);
  }

  override async deployPool(poolTokens: string[]): Promise<PoolInfo> {
    const factory = (await deploy('v3-pool-gyro/GyroECLPPoolFactory', {
      args: [await this.vault.getAddress(), MONTH * 12, '', ''],
    })) as unknown as GyroECLPPoolFactory;

    const poolRoleAccounts: PoolRoleAccountsStruct = {
      pauseManager: ZERO_ADDRESS,
      swapFeeManager: ZERO_ADDRESS,
      poolCreator: ZERO_ADDRESS,
    };

    const tx = await factory.create(
      'E-CLP',
      'Test',
      buildTokenConfig(poolTokens),
      { alpha: PARAMS_ALPHA, beta: PARAMS_BETA, c: PARAMS_C, s: PARAMS_S, lambda: PARAMS_LAMBDA },
      {
        tauAlpha: { x: TAU_ALPHA_X, y: TAU_ALPHA_Y },
        tauBeta: { x: TAU_BETA_X, y: TAU_BETA_Y },
        u: U,
        v: V,
        w: W,
        z: Z,
        dSq: DSQ,
      },
      poolRoleAccounts,
      fp(0.1),
      ZERO_ADDRESS,
      false, // no donations
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

  override async deployOracle(poolAddress: string, feeds: AggregatorV3Interface[]): Promise<OracleInfo> {
    const wrappedPool = (await deploy('v3-vault/WrappedBalancerPoolToken', {
      args: [this.vault.getAddress(), poolAddress, 'WBPT', 'WBPT'],
    })) as WrappedBalancerPoolToken;

    const oracle = (await deploy('v3-oracles/EclpLPOracleMock', {
      args: [await this.vault.getAddress(), await wrappedPool.getAddress(), feeds, ZERO_ADDRESS, 0, true, 1],
    })) as unknown as AggregatorV3Interface;
    return {
      oracle: oracle,
    };
  }
}

describe('ECLP Oracle Gas Benchmark', function () {
  new EclpLPOracleBenchmark(__dirname).itBenchmarks();
});
