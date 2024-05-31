import { ethers } from 'hardhat';
import { BaseContract, BigNumberish } from 'ethers';
import { ZERO_ADDRESS } from '../../constants';
import { Account } from './types';
import {
  RawTokenApproval,
  RawTokenMint,
  RawTokensDeployment,
  TokenApproval,
  TokenMint,
  TokenDeployment,
  RawTokenDeployment,
} from '../tokens/types';
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/signers';
import { VaultDeploymentInputParams, VaultDeploymentParams } from '../vault/types';
import { IVault, IVault__factory, Vault, VaultMock } from '@balancer-labs/v3-vault/typechain-types';
import { IVaultMock, IVaultMock__factory } from '@balancer-labs/v3-interfaces/typechain-types';
import { IAuthentication } from '@balancer-labs/v3-solidity-utils/typechain-types';
import { IAuthentication__factory } from '@balancer-labs/v3-pool-weighted/typechain-types';

export function computeDecimalsFromIndex(i: number): number {
  // Produces repeating series (0..18)
  return i % 19;
}

export default {
  async toVaultDeployment(params: VaultDeploymentInputParams): Promise<VaultDeploymentParams> {
    let { admin, pauseWindowDuration, bufferPeriodDuration } = params;
    if (!admin) admin = (await ethers.getSigners())[0];
    if (!pauseWindowDuration) pauseWindowDuration = 0;
    if (!bufferPeriodDuration) bufferPeriodDuration = 0;
    return { admin, pauseWindowDuration, bufferPeriodDuration };
  },

  async toIVault(vault: Vault | VaultMock): Promise<IVault> {
    return IVault__factory.connect(await vault.getAddress(), vault.runner);
  },

  async toIVaultMock(vault: VaultMock): Promise<IVaultMock> {
    return IVaultMock__factory.connect(await vault.getAddress(), vault.runner);
  },

  async toIAuthentication(contract: BaseContract): Promise<IAuthentication> {
    try {
      contract.getFunction('getActionId');
    } catch (error) {
      const address = await contract.getAddress();
      throw Error(`Contract ${address} is not IAuthentication`);
    }
    return IAuthentication__factory.connect(await contract.getAddress(), contract.runner);
  },

  /***
   * Converts a raw list of token deployments into a consistent deployment request
   * @param params It can be a number specifying the number of tokens to be deployed, a list of strings denoting the
   * token symbols to be used, or a list of token attributes (decimals, symbol, name).
   * @param from A default signer can be specified as the deployer address of the entire list, otherwise a single
   * signer per token can be defined.
   */
  toTokenDeployments(params: RawTokensDeployment, from?: SignerWithAddress, varyDecimals = false): TokenDeployment[] {
    params = typeof params === 'number' ? Array(params).fill({}) : params;
    if (!Array.isArray(params)) params = [params];

    return params.map((param, i) => {
      if (typeof param === 'string') param = { symbol: param, from };
      const args = Object.assign(
        {},
        { symbol: `TK${i}`, name: `Token ${i}`, decimals: varyDecimals ? computeDecimalsFromIndex(i) : 18, from },
        param
      );
      return this.toTokenDeployment(args);
    });
  },

  /***
   * Converts a raw token deployment into a consistent deployment request
   * @param params Could be a single string denoting the token symbol or optional token attributes (decimals, symbol, name)
   */
  toTokenDeployment(params: RawTokenDeployment): TokenDeployment {
    if (typeof params === 'string') params = { symbol: params };
    const { name, symbol, decimals, from } = params;
    return {
      from,
      name: name ?? `Token`,
      symbol: symbol ?? `TKN`,
      decimals: decimals ?? 18,
    };
  },

  /***
   * Converts a raw token mint param into a consistent minting list
   */
  toTokenMints(params: RawTokenMint): TokenMint[] {
    if (Array.isArray(params)) return params.flatMap(this.toTokenMints);

    const { to, amount, from } = params;

    if (!Array.isArray(to)) {
      if (Array.isArray(from)) throw Error('Inconsistent mint sender length');
      return [{ to, amount, from }];
    }

    if (Array.isArray(from) && to.length !== from.length) throw Error('Inconsistent mint sender length');
    return to.map((to, i) => ({ to, amount, from: Array.isArray(from) ? from[i] : from }));
  },

  /***
   * Converts a raw token approval param into a consistent approval list
   */
  toTokenApprovals(params: RawTokenApproval): TokenApproval[] {
    if (Array.isArray(params)) return params.flatMap(this.toTokenApprovals);

    const { to: recipients, amount, from } = params;
    const to = Array.isArray(recipients) ? recipients : [recipients];

    return to.flatMap((to) =>
      Array.isArray(from) ? from.map((from) => ({ to, amount, from })) : [{ to, amount, from }]
    );
  },

  toAddresses(to: Account[]): string[] {
    return to.map(this.toAddress);
  },

  toAddress(to?: Account): string {
    if (!to) return ZERO_ADDRESS;
    return typeof to === 'string' ? to : to.address;
  },

  toBytes32(value: BigNumberish): string {
    const hexy = ethers.toBeHex(value);
    return ethers.zeroPadValue(hexy, 32);
  },
};
