import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import { BatchSwapStep, FundManagement } from '@balancer-labs/balancer-js';
import { Account } from '../types/types';
import { BigNumberish } from '../../numbers';

export type RawVaultDeployment = {
  mocked?: boolean;
  admin?: SignerWithAddress;
  nextAdmin?: string;
  pauseWindowDuration?: BigNumberish;
  bufferPeriodDuration?: BigNumberish;
  maxYieldValue?: BigNumberish;
  maxAUMValue?: BigNumberish;
  from?: SignerWithAddress;
};

export type VaultDeployment = {
  mocked: boolean;
  pauseWindowDuration: BigNumberish;
  bufferPeriodDuration: BigNumberish;
  maxYieldValue: BigNumberish;
  maxAUMValue: BigNumberish;
  admin?: SignerWithAddress;
  nextAdmin: string;
  from?: SignerWithAddress;
};

export type Swap = {
  kind: number;
  poolAddress: string;
  poolId: string;
  to: Account;
  tokenIn: string;
  tokenOut: string;
  lastChangeBlock: BigNumberish;
  data: string;
  amount: BigNumberish;
  from?: SignerWithAddress;
};

export type MinimalSwap = Swap & {
  balanceTokenIn: BigNumberish;
  balanceTokenOut: BigNumberish;
};

export type GeneralSwap = Swap & {
  balances: BigNumberish[];
  indexIn: number;
  indexOut: number;
};

export type JoinPool = {
  poolId: string;
  tokens: string[];
  poolAddress?: string;
  recipient?: string;
  currentBalances?: BigNumberish[];
  lastChangeBlock?: BigNumberish;
  protocolFeePercentage?: BigNumberish;
  data?: string;
  maxAmountsIn?: BigNumberish[];
  fromInternalBalance?: boolean;
  from?: SignerWithAddress;
};

export type ExitPool = {
  poolId: string;
  tokens: string[];
  poolAddress?: string;
  recipient?: string;
  currentBalances?: BigNumberish[];
  lastChangeBlock?: BigNumberish;
  protocolFeePercentage?: BigNumberish;
  data?: string;
  minAmountsOut?: BigNumberish[];
  toInternalBalance?: boolean;
  from?: SignerWithAddress;
};

export type QueryBatchSwap = {
  kind: number;
  swaps: BatchSwapStep[];
  assets: string[];
  funds: FundManagement;
};

export enum ProtocolFee {
  SWAP = 0,
  YIELD = 2,
  AUM = 3,
}
