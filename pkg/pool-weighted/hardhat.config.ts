import { HardhatUserConfig } from 'hardhat/config';

import { hardhatBaseConfig } from '@balancer-labs/v3-common';

import '@nomicfoundation/hardhat-toolbox';
import '@nomicfoundation/hardhat-ethers';
import '@typechain/hardhat';

import 'hardhat-ignore-warnings';
import 'hardhat-gas-reporter';
import 'hardhat-contract-sizer';
import { warnings } from '@balancer-labs/v3-common/hardhat-base-config';

import * as tdly from '@tenderly/hardhat-tenderly';
tdly.setup({ automaticVerifications: false });

const config: HardhatUserConfig = {
  networks: {
    hardhat: {
      allowUnlimitedContractSize: true,
    },
    sepolia: {
      url: 'SEPOLIA_RPC_URL',
      accounts: ['SEPOLIA_PRIVATE_KEY'],
    },
  },
  solidity: {
    compilers: hardhatBaseConfig.compilers,
  },
  warnings,
  tenderly: {
    project: 'v3',
    username: 'balancer',
    privateVerification: true,
  },
};

export default config;
