import 'dotenv/config';
import { ethers } from 'hardhat';
import {
  VaultMockForFeeSweeper__factory,
  CowSwapFeeBurner__factory,
  ProtocolFeeSweeper__factory,
  IERC20__factory,
} from '../typechain-types';

const DEFAULT_ORDER_LIFETIME = 60 * 10; // 10 minutes
const APP_DATA_HASH = '0xc990bae86208bfdfba8879b64ab68da5905e8bb97aa3da5c701ec1183317a6f6';

export type ConditionalOrderParams = {
  handler: string;
  salt: string;
  staticInput: string;
};

export const setupContracts = async (args: { target: string }) => {
  if (process.env.COMPOSABLE_COW_ADDRESS === undefined) {
    throw new Error('COMPOSABLE_COW_ADDRESS is not set');
  } else if (process.env.COW_VAULT_RELAYER_ADDRESS === undefined) {
    throw new Error('COW_VAULT_RELAYER_ADDRESS is not set');
  }

  const composableCow = process.env.COMPOSABLE_COW_ADDRESS;
  const cowVaultRelayer = process.env.COW_VAULT_RELAYER_ADDRESS;

  const account = (await ethers.getSigners())[0];

  console.log('deploying vaultMock...');
  const vaultMock = await new VaultMockForFeeSweeper__factory(account).deploy();

  console.log('waiting for transaction...');
  await vaultMock.deploymentTransaction()?.wait();

  const vaultMockAddress = await vaultMock.getAddress();

  console.log('deploying cowSwapBurner...');
  const cowSwapBurner = await new CowSwapFeeBurner__factory(account).deploy(
    vaultMockAddress,
    composableCow,
    cowVaultRelayer,
    APP_DATA_HASH
  );

  console.log('waiting for transaction...');
  await cowSwapBurner.deploymentTransaction()?.wait();

  const cowSwapBurnerAddress = await cowSwapBurner.getAddress();

  console.log('deploying protocolFeeSweeper...');
  const protocolFeeSweeper = await new ProtocolFeeSweeper__factory(account).deploy(vaultMockAddress, account.address);

  console.log('waiting for transaction...');
  await protocolFeeSweeper.deploymentTransaction()?.wait();

  console.log('add cowSwapBurner to protocolFeeSweeper...');
  const addingCowSwapBurnerTx = await protocolFeeSweeper.addProtocolFeeBurner(cowSwapBurnerAddress);

  console.log('waiting for transaction...');
  await addingCowSwapBurnerTx.wait();

  console.log('add target token to protocolFeeSweeper...');
  const addingTargetTokenTx = await protocolFeeSweeper.setTargetToken(args.target);

  console.log('waiting for transaction...');
  await addingTargetTokenTx.wait();

  const protocolFeeSweeperAddress = await protocolFeeSweeper.getAddress();
  console.log('add permission for sweeper to cow burner...');
  const addingSweeperPermissionTx = await vaultMock.addOwner(protocolFeeSweeperAddress);

  console.log('waiting for transaction...');
  await addingSweeperPermissionTx.wait();

  console.log('\n------------------------------------\n');
  console.log('vaultMock deployed at: ', vaultMockAddress);
  console.log('protocolFeeSweeper deployed at: ', await protocolFeeSweeper.getAddress());
  console.log('cowSwapBurner deployed at: ', cowSwapBurnerAddress);

  console.log('\ncontracts have been successfully configured!');
};

export const runSmokeTest = async (args: {
  token: string;
  amount: string;
  min: string;
  vault: string;
  sweeper: string;
  burner: string;
  lifetime?: number;
}) => {
  const { ethers } = await import('hardhat');

  const account = await ethers.provider.getSigner(0);

  const protocolFeeSweeper = ProtocolFeeSweeper__factory.connect(args.sweeper, account);
  const vaultAddress = await protocolFeeSweeper.getVault();

  console.log('depositing token as fee...');
  let tx = await IERC20__factory.connect(args.token, account).transfer(vaultAddress, ethers.parseEther(args.amount));
  console.log('deposit tx: ', tx.hash);
  await tx.wait();

  const lastBlock = await ethers.provider.getBlock('latest');
  if (!lastBlock) {
    throw new Error('last block not found');
  }

  console.log('last block: ', lastBlock?.number);

  let deadline;
  if (args.lifetime === undefined) {
    deadline = lastBlock.timestamp + DEFAULT_ORDER_LIFETIME;
  } else {
    deadline = lastBlock.timestamp + args.lifetime * 60;
  }

  console.log('order deadline: ', deadline);

  console.log('sweepProtocolFeesForToken...');
  tx = await protocolFeeSweeper.sweepProtocolFeesForToken(
    ethers.ZeroAddress,
    args.token,
    ethers.parseEther(args.min),
    deadline,
    args.burner,
    { gasLimit: 1000000 }
  );
  console.log('sweepProtocolFeesForToken tx: ', tx.hash);
  await tx.wait();

  console.log('order created successfully!');
};
