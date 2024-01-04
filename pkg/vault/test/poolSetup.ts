import { deploy } from '@balancer-labs/v3-helpers/src/contract';
import { VaultMock } from '../typechain-types/contracts/test/VaultMock';
import { ERC20TestToken } from '@balancer-labs/v3-solidity-utils/typechain-types/contracts/test/ERC20TestToken';
import { PoolMock } from '@balancer-labs/v3-vault/typechain-types/contracts/test/PoolMock';
import { ZERO_ADDRESS } from '@balancer-labs/v3-helpers/src/constants';
import { deploy as VaultDeployer } from '@balancer-labs/v3-helpers/src/models/vault/VaultDeployer';
import { PoolRegistrationLib } from '../typechain-types';

// This deploys a Vault, then creates 3 tokens and 2 pools. The first pool (A) is registered; the second (B) )s not,
// which, along with a registration flag in the Pool mock, permits separate testing of registration functions.
export async function setupEnvironment(pauseWindowDuration: number): Promise<{
  vault: VaultMock;
  tokens: ERC20TestToken[];
  pools: PoolMock[];
  poolRegistrationLib: PoolRegistrationLib;
}> {
  const { vault, poolRegistrationLib } = await VaultDeployer({ pauseWindowDuration, mocked: true });
  const vaultAddress = await vault.getAddress();

  const tokenA: ERC20TestToken = await deploy('v3-solidity-utils/ERC20TestToken', { args: ['Token A', 'TKNA', 18] });
  const tokenB: ERC20TestToken = await deploy('v3-solidity-utils/ERC20TestToken', { args: ['Token B', 'TKNB', 6] });
  const tokenC: ERC20TestToken = await deploy('v3-solidity-utils/ERC20TestToken', { args: ['Token C', 'TKNC', 8] });

  const tokenAAddress = await tokenA.getAddress();
  const tokenBAddress = await tokenB.getAddress();
  const tokenCAddress = await tokenC.getAddress();

  const poolATokens = [tokenAAddress, tokenBAddress, tokenCAddress];
  const poolBTokens = [tokenAAddress, tokenCAddress];

  const poolA: PoolMock = await deploy('v3-vault/PoolMock', {
    args: [
      vaultAddress,
      'Pool A',
      'POOLA',
      poolATokens,
      Array(poolATokens.length).fill(ZERO_ADDRESS),
      true,
      365 * 24 * 3600,
      ZERO_ADDRESS,
    ],
  });

  const poolB: PoolMock = await deploy('v3-vault/PoolMock', {
    args: [
      vaultAddress,
      'Pool B',
      'POOLB',
      poolBTokens,
      Array(poolBTokens.length).fill(ZERO_ADDRESS),
      false,
      365 * 24 * 3600,
      ZERO_ADDRESS,
    ],
  });

  return {
    vault: vault as VaultMock,
    tokens: [tokenA, tokenB, tokenC],
    pools: [poolA, poolB],
    poolRegistrationLib,
  };
}
