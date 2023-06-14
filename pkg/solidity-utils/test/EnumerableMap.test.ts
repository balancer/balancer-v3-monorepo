import { Contract } from 'ethers';

import { deploy } from '@balancer-labs/v3-helpers/src/contract';
import { shouldBehaveLikeMap } from './EnumerableMap.behavior';
import { sharedBeforeEach } from '@balancer-labs/v3-common/sharedBeforeEach';

describe('EnumerableMap', () => {
  describe('EnumerableIERC20ToUint256Map', () => {
    const keys = [
      '0x8B40ECf815AC8d53aB4AD2a00248DE77296344Db',
      '0x638141Eb8905D9A55D81610f45bC2B47120059e7',
      '0x7571A57e94F046725612f786Aa9bf44ce6b56894',
    ];

    const values = [42n, 1337n, 9999n];

    const store: { map?: Contract } = {};

    sharedBeforeEach(async () => {
      store.map = await deploy('EnumerableIERC20ToUint256MapMock');
    });

    shouldBehaveLikeMap(store as { map: Contract }, keys, values);
  });
});
