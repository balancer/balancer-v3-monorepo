import { HardhatRuntimeEnvironment } from 'hardhat/types';
import * as tdly from '@tenderly/hardhat-tenderly';
import './skipFoundryTests.ts';
import { task } from 'hardhat/config';

require('dotenv').config({ path: '../../.env' });

const { SEPOLIA_RPC_URL } = process.env;

tdly.setup({ automaticVerifications: false });

type SolcConfig = {
  version: string;
  settings: {
    optimizer: {
      enabled: boolean;
      runs?: number;
    };
  };
};

export const compilers: [SolcConfig] = [
  {
    version: '0.8.21',
    settings: {
      optimizer: {
        enabled: true,
        runs: 9999,
      },
    },
  },
];

type ContractSettings = Record<
  string,
  {
    version: string;
    runs: number;
  }
>;

const contractSettings: ContractSettings = {
  '@balancer-labs/v3-vault/contracts/Vault.sol': {
    version: '0.8.21',
    runs: 500,
  },
  '@balancer-labs/v3-vault/contracts/VaultExtension.sol': {
    version: '0.8.21',
    runs: 500,
  },
};

export const warnings = {
  // Ignore code-size in test files: mocks may make contracts not deployable on real networks, but we don't care about
  // that.
  'contracts/test/**/*': {
    'code-size': 'off',
  },
  // Make all warnings cause errors, except code-size (contracts may go over the limit during development).
  '*': {
    'code-size': 'warn',
    'unused-param': 'warn',
    'shadowing-opcode': 'off',
    default: 'error',
  },
};

export const networks = {
  sepolia: {
    url: SEPOLIA_RPC_URL,
  },
};

export const overrides = (packageName: string): Record<string, SolcConfig> => {
  const overrides: Record<string, SolcConfig> = {};

  for (const contract of Object.keys(contractSettings)) {
    overrides[contract.replace(`${packageName}/`, '')] = {
      version: contractSettings[contract].version,
      settings: {
        optimizer: {
          enabled: true,
          runs: contractSettings[contract].runs,
        },
      },
    };
  }

  return overrides;
};

task('verify:tenderly', 'Verifies contract on Tenderly')
  .addParam('address', "The contract's address")
  .addParam('name', "The contract's name")
  .setAction(async (taskArgs, hre) => {
    const { address, name } = taskArgs;
    console.log(`Verifying contract ${name} at address ${address}...`);
    await hre.tenderly.verify({ address, name });
  });
