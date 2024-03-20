import { Contract } from 'ethers';
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/dist/src/signer-with-address';
import { LiquidityManagementStruct } from '@balancer-labs/v3-vault/typechain-types/contracts/Vault';

export type NAry<T> = T | Array<T>;

export type Account = string | SignerWithAddress | Contract | { address: string };

export type TxParams = {
  from?: SignerWithAddress;
};

export enum TokenType {
  STANDARD = 0,
  WITH_RATE,
  ERC4626,
}

export type TokenConfig = {
  token: string;
  tokenType: TokenType;
  rateProvider: string;
  yieldFeeExempt: boolean;
};

export type BasePoolParams = {
  name: string;
  symbol: string;
  tokens: TokenConfig[];
  pauseManager: string;
  poolHooks: PoolHooksStruct;
  liquidityManagement: LiquidityManagementStruct;
};

export function defaultPoolHooks(): PoolHooksStruct {
  return {
    shouldCallBeforeInitialize: false,
    shouldCallAfterInitialize: false,
    shouldCallBeforeSwap: false,
    shouldCallAfterSwap: false,
    shouldCallBeforeAddLiquidity: false,
    shouldCallAfterAddLiquidity: false,
    shouldCallBeforeRemoveLiquidity: false,
    shouldCallAfterRemoveLiquidity: false,
  };
}

export function defaultLiquidityManagement(): LiquidityManagementStruct {
  return { supportsAddLiquidityCustom: false, supportsRemoveLiquidityCustom: false };
}
