import { CowSwapBurner__factory, FeeCollectorMock__factory, IERC20__factory } from '../typechain-types';
import { ethers } from 'hardhat';
import { expect } from 'chai';

describe('Test CowSwapBurner (Sepolia)', async () => {
  const testAmount = ethers.parseEther('0.01');
  const wethAddress = '0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14';
  const daiAddress = '0xB4F1737Af37711e9A5890D9510c9bB60e170CB0D';
  const composableCow = '0xfdaFc9d1902f4e0b84f65F49f244b32b31013b74';
  const vaultRelayer = '0xC92E8bdf79f0507f65a392b0ab4667716BFE0110';

  const fee = ethers.parseEther('0.0001');
  const account = await ethers.provider.getSigner(0);

  it('deploy & burn', async () => {
    const dai = IERC20__factory.connect(daiAddress, account);
    const weth = IERC20__factory.connect(wethAddress, account);

    console.log(`wrapping ${ethers.formatEther(testAmount)} eth to weth...`);
    await (
      await account.sendTransaction({
        to: wethAddress,
        value: testAmount,
      })
    ).wait();

    console.log('weth wrapped');

    expect(await weth.balanceOf(account.address)).to.be.equal(testAmount);

    console.log('deploying feeCollector...');
    const feeCollector = await new FeeCollectorMock__factory(account).deploy(
      fee,
      daiAddress,
      account.address,
      account.address
    );

    console.log('feeCollector deployed at: ', feeCollector.address);

    console.log('deploying cowSwapBurner...');
    const cowSwapBurner = new CowSwapBurner__factory().deploy(
      await feeCollector.getAddress(),
      composableCow,
      vaultRelayer,
      1
    );

    console.log('cowSwapBurner deployed at: ', cowSwapBurner.address);

    console.log('setup cowSwapBurner in feeCollector...');
    await (await feeCollector.setCowSwapBurner(cowSwapBurner.address)).wait();

    console.log('move wei to feeCollector...');
    await (await weth.transfer(feeCollector.address, testAmount)).wait();

    console.log('burning...');
    await (await feeCollector.burn()).wait();
  });
});
