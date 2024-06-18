import { HardhatUserConfig } from 'hardhat/config';
import { hardhatBaseConfig } from '@balancer-labs/v3-common';

import '@nomicfoundation/hardhat-toolbox';
import '@nomicfoundation/hardhat-ethers';
import '@typechain/hardhat';

import 'hardhat-ignore-warnings';
import 'hardhat-gas-reporter';
import 'hardhat-contract-sizer';
import { warnings } from '@balancer-labs/v3-common/hardhat-base-config';

const config: HardhatUserConfig = {
  solidity: {
    compilers: hardhatBaseConfig.compilers,
  },
  warnings,
};

export default config;
