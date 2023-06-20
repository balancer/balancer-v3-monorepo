import { expect } from 'chai';
import { BigNumberish, Typed } from 'ethers';
import { deploy } from '@balancer-labs/v3-helpers/src/contract';
import { fromNow, MONTH } from '@balancer-labs/v3-helpers/src/time';
import '@balancer-labs/v3-common/setupTests';

import { VaultMock } from '../typechain-types/contracts/test/VaultMock';
import { bn } from '@balancer-labs/v3-helpers/src/numbers';
import { ANY_ADDRESS, ZERO_ADDRESS } from '@balancer-labs/v3-helpers/src/constants';

describe('Vault', function () {
  const WETH = '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2';
  const ETH_SENTINEL = ZERO_ADDRESS;

  const BAL = '0xba100000625a3754423978a60c9317c58a424e3d';
  const DAI = '0x6b175474e89094c44da98b954eedeac495271d0f';
  const WBTC = '0x2260fac5e5542a773aa44fbcfedf7c193bc2c599';

  const pauseWindowDuration = MONTH;
  const bufferPeriodDuration = MONTH;

  let instance: VaultMock;

  const deployVault = async (weth: string, pauseWindowDuration: BigNumberish, bufferPeriodDuration: BigNumberish) => {
    instance = await deploy('VaultMock', {
      args: [weth, bn(pauseWindowDuration), bn(bufferPeriodDuration)],
    });
  };

  describe('initialization', () => {
    sharedBeforeEach('deploy Vault', async () => {
      await deployVault(WETH, pauseWindowDuration, bufferPeriodDuration);
    });

    it('initializes WETH', async () => {
      expect(await instance.WETH()).to.equal(WETH);
    });

    it('is temporarily pausable', async () => {
      expect(await instance.paused()).to.equal(false);

      const [pauseWindowEndTime, bufferPeriodEndTime] = await instance.getPauseEndTimes();
      expect(pauseWindowEndTime).to.equal(await fromNow(pauseWindowDuration));
      expect(bufferPeriodEndTime).to.equal((await fromNow(pauseWindowDuration)) + bn(bufferPeriodDuration));
    });
  });

  describe('native ETH handling', () => {
    sharedBeforeEach('deploy Vault', async () => {
      await deployVault(WETH, pauseWindowDuration, bufferPeriodDuration);
    });

    it('detects the ETH asset', async () => {
      expect(await instance.isETH(ETH_SENTINEL)).to.be.true;
      expect(await instance.isETH(ANY_ADDRESS)).to.be.false;
    });

    it('translates native ETH', async () => {
      expect(await instance.translateToIERC20(Typed.address(ETH_SENTINEL))).to.equal(WETH);
      expect(await instance.translateToIERC20(Typed.address(ANY_ADDRESS))).to.equal(ANY_ADDRESS);
    });

    it('translates an array of tokens', async () => {
      const tokensIn = [WETH, BAL, ETH_SENTINEL, DAI, WBTC];
      const tokensOut = [WETH, BAL, WETH, DAI, WBTC];

      expect(await instance['translateToIERC20(address[])'](tokensIn)).to.deep.equal(tokensOut);
    });
  });
});
