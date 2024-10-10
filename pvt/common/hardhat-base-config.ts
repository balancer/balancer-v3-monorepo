import { WarningRule } from 'hardhat-ignore-warnings/dist/type-extensions';
import './skipFoundryTests.ts';

type SolcConfig = {
  version: string;
  settings: {
    viaIR: boolean;
    evmVersion: string;
    optimizer: {
      enabled: boolean;
      runs?: number;
      details: {
        yulDetails: {
          optimizerSteps: string;
        };
      };
    };
  };
};

// The coverage report doesn't work well with via-ir flags, so we disable it
const viaIR = !process.env.COVERAGE;
const optimizerSteps =
  'dhfoDgvulfnTUtnIf [ xa[r]EscLM cCTUtTOntnfDIul Lcul Vcul [j] Tpeul xa[rul] xa[r]cL gvif CTUca[r]LSsTFOtfDnca[r]Iulc ] jmul[jul] VcTOcul jmul : fDnTOcmu';

export const compilers: [SolcConfig] = [
  {
    version: '0.8.27',
    settings: {
      viaIR,
      evmVersion: 'cancun',
      optimizer: {
        enabled: true,
        runs: 9999,
        details: {
          yulDetails: {
            optimizerSteps,
          },
        },
      },
    },
  },
];

type ContractSettings = Record<
  string,
  {
    viaIR: boolean;
    version: string;
    runs: number | undefined;
  }
>;

const contractSettings: ContractSettings = {
  '@balancer-labs/v3-vault/contracts': {
    version: compilers[0].version,
    runs: compilers[0].settings.optimizer.runs,
    viaIR,
  },
  '@balancer-labs/v3-vault/contracts/Vault.sol': {
    version: '0.8.27',
    runs: 500,
    viaIR,
  },
  '@balancer-labs/v3-vault/contracts/VaultExtension.sol': {
    version: '0.8.27',
    runs: 500,
    viaIR,
  },
  '@balancer-labs/v3-vault/contracts/CompositeLiquidityRouter.sol': {
    version: '0.8.27',
    runs: 500,
    viaIR: false,
  },
  '@balancer-labs/v3-vault/contracts/test/CompositeLiquidityRouterMock.sol': {
    version: '0.8.27',
    runs: 9999,
    viaIR: false,
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
        viaIR: contractSettings[contract].viaIR,
        evmVersion: 'cancun',
        optimizer: {
          enabled: true,
          runs: contractSettings[contract].runs,
          details: {
            yulDetails: {
              optimizerSteps,
            },
          },
        },
      },
    };
  }

  return overrides;
};
