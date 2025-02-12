import 'dotenv/config';
import {
  VaultMockForFeeSweeper__factory,
  CowSwapFeeBurner__factory,
  ProtocolFeeSweeper__factory,
  IERC20__factory,
} from '../typechain-types';
import { task } from 'hardhat/config';
import { HardhatRuntimeEnvironment } from 'hardhat/types';

const orderLifeTime = 60 * 10; // 10 minutes
const appDataHash = '0xc990bae86208bfdfba8879b64ab68da5905e8bb97aa3da5c701ec1183317a6f6';

task('setup-smoke-test-fee-sweeper-contracts', 'Setup contracts for smoke testing fee sweeper').setAction(
  async (hre: HardhatRuntimeEnvironment) => {
    if (process.env.COMPOSABLE_COW_ADDRESS === undefined) {
      throw new Error('COMPOSABLE_COW_ADDRESS is not set');
    } else if (process.env.VAULT_RELAYER_ADDRESS === undefined) {
      throw new Error('VAULT_RELAYER_ADDRESS is not set');
    }

    const composableCow = process.env.COMPOSABLE_COW_ADDRESS;
    const cowVaultRelayer = process.env.VAULT_RELAYER_ADDRESS;

    const account = await hre.ethers.provider.getSigner(0);

    console.log('deploying vaultMock...');
    const vaultMock = await new VaultMockForFeeSweeper__factory(account).deploy();
    await vaultMock.deploymentTransaction()?.wait();
    const vaultMockAddress = await vaultMock.getAddress();
    console.log('vaultMock deployed at: ', vaultMockAddress);

    console.log('deploying cowSwapBurner...');
    const cowSwapBurner = await new CowSwapFeeBurner__factory(account).deploy(
      vaultMockAddress,
      composableCow,
      cowVaultRelayer,
      appDataHash
    );
    await cowSwapBurner.deploymentTransaction()?.wait();
    const cowSwapBurnerAddress = await cowSwapBurner.getAddress();
    console.log('cowSwapBurner deployed at: ', cowSwapBurnerAddress);

    console.log('deploying protocolFeeSweeper...');
    const protocolFeeSweeper = await new ProtocolFeeSweeper__factory(account).deploy(vaultMockAddress, account.address);
    await protocolFeeSweeper.deploymentTransaction()?.wait();
    const protocolFeeSweeperAddress = await protocolFeeSweeper.getAddress();
    console.log('protocolFeeSweeper deployed at: ', protocolFeeSweeperAddress);

    console.log('add cowSwapBurner to protocolFeeSweeper...');
    const addingCowSwapBurnerTx = await protocolFeeSweeper.addProtocolFeeBurner(cowSwapBurnerAddress);
    console.log('addingCowSwapBurnerTx: ', addingCowSwapBurnerTx.hash);
    await addingCowSwapBurnerTx.wait();

    console.log('contracts have been successfully configured!');
  }
);

task(
  'smoke-test-fee-sweeper',
  'Smoke test fee sweeper.' +
    'Before running this script, make sure to run Cow Watch-Tower (https://github.com/cowprotocol/watch-tower)' +
    'and .env file is properly configured. For running this script, you need to call' +
    "'npx hardhat run ./script/createBurnerOrder.ts --network sepolia'" +
    'in the terminal'
)
  .addParam('token', 'Token address for deposit as fee')
  .addFlag('tokenAmount', 'Amount of token to deposit as fee')
  .addFlag('minTargetTokenAmountOut', 'Min target token amount out')
  .addFlag('vaultMockAddress', 'Vault mock address')
  .addFlag('feeSweeperAddress', 'Fee sweeper address')
  .addFlag('cowSwapBurnerAddress', 'Cow swap burner address')
  .addOptionalParam('deadline', 'Deadline for burning')
  .setAction(
    async (
      args: {
        token: string;
        tokenAmount: number;
        minTargetTokenAmountOut: number;
        vaultMockAddress: string;
        feeSweeperAddress: string;
        cowSwapBurnerAddress: string;
        deadline?: number;
      },
      hre: HardhatRuntimeEnvironment
    ) => {
      const account = await hre.ethers.provider.getSigner(0);

      const protocolFeeSweeper = ProtocolFeeSweeper__factory.connect(args.feeSweeperAddress, account);
      const vaultAddress = await protocolFeeSweeper.getVault();

      console.log('depositing token as fee...');
      let tx = await IERC20__factory.connect(args.token, account).transfer(vaultAddress, args.tokenAmount);
      console.log('deposit tx: ', tx.hash);
      await tx.wait();

      const lastBlock = await hre.ethers.provider.getBlock('latest');
      if (!lastBlock) {
        throw new Error('last block not found');
      }

      console.log('last block: ', lastBlock?.number);

      if (args.deadline === undefined) {
        args.deadline = lastBlock.timestamp + orderLifeTime;
      }

      console.log('sweepProtocolFeesForToken...');
      tx = await protocolFeeSweeper.sweepProtocolFeesForToken(
        hre.ethers.ZeroAddress,
        args.token,
        args.minTargetTokenAmountOut,
        args.deadline,
        args.cowSwapBurnerAddress
      );
      console.log('sweepProtocolFeesForToken tx: ', tx.hash);
      await tx.wait();

      const receipt = await hre.ethers.provider.getTransactionReceipt(tx.hash);

      //TODO: parse event with the order id and write as result

      console.log('order created successfully!');
    }
  );
