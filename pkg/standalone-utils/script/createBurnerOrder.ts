import { CowSwapBurner__factory, FeeCollectorMock__factory, IERC20__factory } from '../typechain-types';
import { ethers } from 'hardhat';
import { expect } from 'chai';

// Before running this script, make sure to run Cow Watch-Tower (https://github.com/cowprotocol/watch-tower) and .env file is properly configured
// For running this script, you need to call 'npx hardhat run ./script/createBurnerOrder.ts --network sepolia' in the terminal
async function main() {
  const wethAddress = '0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14';
  const daiAddress = '0xB4F1737Af37711e9A5890D9510c9bB60e170CB0D';
  const composableCow = '0xfdaFc9d1902f4e0b84f65F49f244b32b31013b74';
  const vaultRelayer = '0xC92E8bdf79f0507f65a392b0ab4667716BFE0110';

  const account = await ethers.provider.getSigner(0);

  const testAmount = ethers.parseEther('0.011');
  const fee = ethers.parseEther('0.001');

  const weth = IERC20__factory.connect(wethAddress, account);

  const wethBalance = await weth.balanceOf(account.address);
  console.log('weth balance: ', ethers.formatEther(wethBalance));

  if (wethBalance < testAmount) {
    const amount = testAmount - wethBalance;
    console.log(`wrapping ${ethers.formatEther(amount)} eth to weth...`);
    await (
      await account.sendTransaction({
        to: wethAddress,
        value: amount,
      })
    ).wait();

    console.log('weth wrapped');

    expect(await weth.balanceOf(account.address)).to.be.greaterThanOrEqual(testAmount);
  }

  console.log('deploying feeCollector...');
  const feeCollector = await new FeeCollectorMock__factory(account).deploy(
    fee,
    daiAddress,
    account.address,
    account.address
  );
  const feeCollectorAddress = await feeCollector.getAddress();
  await feeCollector.deploymentTransaction()!.wait();

  console.log('feeCollector deployed at: ', feeCollectorAddress);

  console.log('deploying cowSwapBurner...');
  const cowSwapBurner = await new CowSwapBurner__factory(account).deploy(
    await feeCollector.getAddress(),
    composableCow,
    vaultRelayer,
    1
  );
  await cowSwapBurner.deploymentTransaction()!.wait();
  const cowSwapBurnerAddress = await cowSwapBurner.getAddress();

  console.log('cowSwapBurner deployed at: ', cowSwapBurnerAddress);

  console.log('setup cowSwapBurner in feeCollector...');
  await (await feeCollector.setCowSwapBurner(cowSwapBurnerAddress)).wait();

  console.log('move wei to feeCollector...');
  await (await weth.transfer(feeCollectorAddress, testAmount)).wait();

  console.log('burning...');
  await (await feeCollector.burn([wethAddress], account.address)).wait();

  console.log('order for burning created');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
