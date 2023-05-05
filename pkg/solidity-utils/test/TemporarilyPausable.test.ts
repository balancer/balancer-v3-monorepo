import { deploy } from '@balancer-labs/v3-helpers/src/contract';

describe('TemporarilyPausable', function () {
  describe('initialization', () => {
    it('can be initialized ', async () => {
      await deploy('TemporarilyPausableMock', { args: [3600, 3600] });
    });
  });
});
