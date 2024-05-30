import { deploy, deployedAt } from '@balancer-labs/v3-helpers/src/contract';
import { MONTH } from '@balancer-labs/v3-helpers/src/time';
import { VaultMock } from '../typechain-types/contracts/test/VaultMock';
import { ERC20TestToken } from '@balancer-labs/v3-solidity-utils/typechain-types/contracts/test/ERC20TestToken';
import { PoolMock } from '@balancer-labs/v3-vault/typechain-types/contracts/test/PoolMock';
import { ZERO_ADDRESS } from '@balancer-labs/v3-helpers/src/constants';
import { sortAddresses } from '@balancer-labs/v3-helpers/src/models/tokens/sortingHelper';
import * as VaultDeployer from '@balancer-labs/v3-helpers/src/models/vault/VaultDeployer';
import { IVaultMock } from '@balancer-labs/v3-interfaces/typechain-types';
import TypesConverter from '@balancer-labs/v3-helpers/src/models/types/TypesConverter';
import { TokenConfigStruct } from '../typechain-types/contracts/Vault';
import { TokenType } from '@balancer-labs/v3-helpers/src/models/types/types';

// This deploys a Vault, then creates 3 tokens and 2 pools. The first pool (A) is registered; the second (B) )s not,
// which, along with a registration flag in the Pool mock, permits separate testing of registration functions.
export async function setupEnvironment(pauseWindowDuration: number): Promise<{
  vault: IVaultMock;
  tokens: ERC20TestToken[];
  pools: PoolMock[];
}> {
  const BUFFER_PERIOD_DURATION = MONTH;

  const vault: VaultMock = await VaultDeployer.deployMock({
    pauseWindowDuration,
    bufferPeriodDuration: BUFFER_PERIOD_DURATION,
  });
  const vaultAddress = await vault.getAddress();
  const factoryAddress = await vault.getPoolFactoryMock();
  const factory = await deployedAt('PoolFactoryMock', factoryAddress);

  const tokenA: ERC20TestToken = await deploy('v3-solidity-utils/ERC20TestToken', { args: ['Token A', 'TKNA', 18] });
  const tokenB: ERC20TestToken = await deploy('v3-solidity-utils/ERC20TestToken', { args: ['Token B', 'TKNB', 6] });
  const tokenC: ERC20TestToken = await deploy('v3-solidity-utils/ERC20TestToken', { args: ['Token C', 'TKNC', 8] });

  const tokenAAddress = await tokenA.getAddress();
  const tokenBAddress = await tokenB.getAddress();
  const tokenCAddress = await tokenC.getAddress();

  const poolATokens = sortAddresses([tokenAAddress, tokenBAddress, tokenCAddress]);

  const poolA: PoolMock = await deploy('v3-vault/PoolMock', {
    args: [vaultAddress, 'Pool A', 'POOLA'],
  });

  await factory.registerTestPool(poolA, buildTokenConfig(poolATokens));
  // Don't register PoolB.
  const poolB: PoolMock = await deploy('v3-vault/PoolMock', {
    args: [vaultAddress, 'Pool B', 'POOLB'],
  });

  return { vault: await TypesConverter.toIVaultMock(vault), tokens: [tokenA, tokenB, tokenC], pools: [poolA, poolB] };
}

export function buildTokenConfig(
  tokens: string[],
  rateProviders: string[] = [],
  paysYieldFees: boolean[] = []
): TokenConfigStruct[] {
  const result: TokenConfigStruct[] = [];
  if (rateProviders.length == 0) {
    rateProviders = Array(tokens.length).fill(ZERO_ADDRESS);
  }

  tokens.map((token, i) => {
    result[i] = {
      token: token,
      tokenType: rateProviders[i] == ZERO_ADDRESS ? TokenType.STANDARD : TokenType.WITH_RATE,
      rateProvider: rateProviders[i],
      paysYieldFees: paysYieldFees.length == 0 ? rateProviders[i] != ZERO_ADDRESS : paysYieldFees[i],
    };
  });

  return result;
}
