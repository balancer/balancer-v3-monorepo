import { HardhatUserConfig } from 'hardhat/config';
import { hardhatBaseConfig } from '@balancer-labs/v3-common';

import '@nomicfoundation/hardhat-toolbox';
import '@nomicfoundation/hardhat-ethers';
import '@typechain/hardhat';

import 'hardhat-ignore-warnings';
import 'hardhat-gas-reporter';
import 'hardhat-contract-sizer';

const config: HardhatUserConfig = {
  solidity: {
    compilers: hardhatBaseConfig.compilers,
  },
};

export default config;
