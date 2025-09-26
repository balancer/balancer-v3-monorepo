import '@nomicfoundation/hardhat-ethers';
import '@nomicfoundation/hardhat-toolbox';
import '@typechain/hardhat';

import 'hardhat-ignore-warnings';
import 'hardhat-gas-reporter';

import { hardhatBaseConfig } from '@balancer-labs/v3-common';

export default {
  solidity: {
    compilers: hardhatBaseConfig.compilers,
  },
  warnings: hardhatBaseConfig.warnings,
  mocha: {
    timeout: process.env.COVERAGE ? 600000 : 40000, // 10 minutes for coverage, 40s normal
  },
};
