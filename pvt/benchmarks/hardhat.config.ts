import '@nomiclabs/hardhat-ethers';

import { hardhatBaseConfig } from '@balancer-labs/v3-common';

export default {
  networks: {
    hardhat: {
      allowUnlimitedContractSize: true,
    },
  },
  solidity: {
    compilers: hardhatBaseConfig.compilers,
  },
};
