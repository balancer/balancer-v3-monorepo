import 'dotenv/config';
import '@nomicfoundation/hardhat-ethers';
import '@nomicfoundation/hardhat-toolbox';
import '@typechain/hardhat';

import 'hardhat-contract-sizer';
import 'hardhat-gas-reporter';
import 'hardhat-resolc';

import { hardhatBaseConfig } from '@balancer-labs/v3-common';
import { task } from 'hardhat/config';
import { ResolcConfig } from 'hardhat-resolc/dist/types';

task('setup-smoke-test-cow-burner-contracts', 'Setup contracts for smoke testing cow burner')
  .addParam('target', 'Target token address')
  .setAction(async (args: { target: string }) => {
    const { setupContracts } = await import('./scripts/cowBurnerSmokeTest');
    await setupContracts(args);
  });

task(
  'smoke-test-cow-burner',
  'Smoke test cow burner.' +
    'Before running this script, make sure to run Cow Watch-Tower (https://github.com/cowprotocol/watch-tower)' +
    'and .env file is properly configured. For running this script, you need to call' +
    "'npx hardhat run ./script/createBurnerOrder.ts --network sepolia'" +
    'in the terminal'
)
  .addParam('token', 'Token address for deposit as fee')
  .addParam('amount', 'Amount of token to deposit as fee')
  .addParam('min', 'Min target token amount out')
  .addParam('vault', 'Vault mock address')
  .addParam('sweeper', 'Fee sweeper address')
  .addParam('burner', 'Cow swap burner address')
  .addOptionalParam('lifetime', 'Order lifetime in minutes')
  .setAction(
    async (args: {
      token: string;
      amount: string;
      min: string;
      vault: string;
      sweeper: string;
      burner: string;
      lifetime?: number;
    }) => {
      const { runSmokeTest } = await import('./scripts/cowBurnerSmokeTest');
      await runSmokeTest(args);
    }
  );

const resolc: ResolcConfig = {
  version: '0.8.27',
  compilerSource: 'binary',
  settings: {
    overwrite: true,
    optimizer: {
      enabled: true,
      parameters: 'z',
      fallbackOz: true,
    },
    compilerPath: '../../resolc-x86_64-unknown-linux-musl',
    standardJson: true,
  },
};

export default {
  networks: {
    hardhat: {
      allowUnlimitedContractSize: true,
      polkavm: true,
    },
    sepolia: {
      url: process.env.SEPOLIA_RPC_URL || '',
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
    },
  },
  solidity: {
    compilers: hardhatBaseConfig.compilers,
  },
  resolc,
  warnings: hardhatBaseConfig.warnings,
};
