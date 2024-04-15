import { WarningRule } from 'hardhat-ignore-warnings/dist/type-extensions';
import './skipFoundryTests.ts';

type SolcConfig = {
  version: string;
  settings: {
    optimizer: {
      enabled: boolean;
      runs?: number;
    };
    evmVersion: string;
  };
};

export const compilers: [SolcConfig] = [
  {
    version: '0.8.24',
    settings: {
      optimizer: {
        enabled: true,
        runs: 9999,
      },
      evmVersion: 'cancun',
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
    version: '0.8.24',
    runs: 500,
  },
  '@balancer-labs/v3-vault/contracts/VaultExtension.sol': {
    version: '0.8.24',
    runs: 500,
  },
  '@balancer-labs/v3-vault/contracts/VaultAdmin.sol': {
    version: '0.8.24',
    runs: 500,
  },
};

export const warnings = {
  // Ignore code-size in test files: mocks may make contracts not deployable on real networks, but we don't care about
  // that.
  'contracts/test/**/*': {
    'code-size': 'off' as WarningRule,
  },
  // Make all warnings cause errors, except code-size (contracts may go over the limit during development).
  '*': {
    'code-size': 'warn' as WarningRule,
    'unused-param': 'warn' as WarningRule,
    'shadowing-opcode': 'off' as WarningRule,
    'transient-storage': 'off' as WarningRule,
    'initcode-size': 'off' as WarningRule,
    default: 'error' as WarningRule,
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
        evmVersion: 'cancun',
      },
    };
  }

  return overrides;
};
