import '@nomiclabs/hardhat-ethers';
import '@nomicfoundation/hardhat-toolbox';
import 'hardhat-ignore-warnings';

import { hardhatBaseConfig } from '@balancer-labs/v3-common';

export default {
  solidity: {
    compilers: hardhatBaseConfig.compilers,
  },
  warnings: hardhatBaseConfig.warnings,
};
