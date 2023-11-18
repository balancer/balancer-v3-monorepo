import { expect } from 'chai';
import { Typed } from 'ethers';

import { deploy } from '@balancer-labs/v3-helpers/src/contract';
import { sharedBeforeEach } from '@balancer-labs/v3-common/sharedBeforeEach';
import { ANY_ADDRESS, ZERO_ADDRESS } from '@balancer-labs/v3-helpers/src/constants';

import { AssetHelpersMock } from '../typechain-types/contracts/test/AssetHelpersMock';

describe('AssetHelpers', function () {
  const WETH = '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2';
  const ETH_SENTINEL = ZERO_ADDRESS;

  const BAL = '0xba100000625a3754423978a60c9317c58a424e3d';
  const DAI = '0x6b175474e89094c44da98b954eedeac495271d0f';
  const WBTC = '0x2260fac5e5542a773aa44fbcfedf7c193bc2c599';

  let lib: AssetHelpersMock;

  sharedBeforeEach('deploy lib', async () => {
    lib = await deploy('AssetHelpersMock', { args: [] });
  });

  describe('native ETH handling', () => {
    it('detects the ETH asset', async () => {
      expect(await lib.isETH(ETH_SENTINEL)).to.be.true;
      expect(await lib.isETH(ANY_ADDRESS)).to.be.false;
    });

    it('translates native ETH', async () => {
      expect(await lib.toIERC20(Typed.address(ETH_SENTINEL), WETH)).to.equal(WETH);
      expect(await lib.toIERC20(Typed.address(ANY_ADDRESS), WETH)).to.equal(ANY_ADDRESS);
    });

    it('translates an array of tokens', async () => {
      const tokensIn = [WETH, BAL, ETH_SENTINEL, DAI, WBTC];
      const tokensOut = [WETH, BAL, WETH, DAI, WBTC];

      expect(await lib['toIERC20(address[], address)'](tokensIn, WETH)).to.deep.equal(tokensOut);
    });
  });
});
