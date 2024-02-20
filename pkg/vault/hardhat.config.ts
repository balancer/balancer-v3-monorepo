import '@nomicfoundation/hardhat-ethers';
import '@nomicfoundation/hardhat-toolbox';
import '@typechain/hardhat';

import 'hardhat-ignore-warnings';
import 'hardhat-gas-reporter';
import 'hardhat-contract-sizer';
import 'hardhat/config';

import { name } from './package.json';
import { hardhatBaseConfig } from '@balancer-labs/v3-common';


export default {
  networks: {
    hardhat: {
      allowUnlimitedContractSize: true,
    },
    ...hardhatBaseConfig.networks,
  },
  solidity: {
    compilers: hardhatBaseConfig.compilers,
    overrides: { ...hardhatBaseConfig.overrides(name) },
  },
  warnings: hardhatBaseConfig.warnings,
  tenderly: {
    project: 'v3',
    username: 'balancer',
    privateVerification: true,
  },
};
