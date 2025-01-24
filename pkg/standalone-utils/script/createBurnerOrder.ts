import { IERC20__factory, VaultAuthorizerMock__factory, CowSwapFeeBurner__factory } from '../typechain-types';
import { ethers } from 'hardhat';
import { expect } from 'chai';

// Before running this script, make sure to run Cow Watch-Tower (https://github.com/cowprotocol/watch-tower) and .env file is properly configured
// For running this script, you need to call 'npx hardhat run ./script/createBurnerOrder.ts --network sepolia' in the terminal
async function main() {
  const orderLifeTime = 60 * 10; // 10 minutes
  const wethAddress = '0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14';
  const daiAddress = '0xB4F1737Af37711e9A5890D9510c9bB60e170CB0D';
  const composableCow = '0xfdaFc9d1902f4e0b84f65F49f244b32b31013b74';
  const vaultRelayer = '0xC92E8bdf79f0507f65a392b0ab4667716BFE0110';

  const account = await ethers.provider.getSigner(0);

  const testAmount = ethers.parseEther('0.01');

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

  console.log('deploying vaultAuthorizerMock...');
  const vaultAuthorizerMock = await new VaultAuthorizerMock__factory(account).deploy();
  await vaultAuthorizerMock.deploymentTransaction().wait();

  console.log('deploying cowSwapBurner...');
  const cowSwapBurner = await new CowSwapFeeBurner__factory(account).deploy(
    await vaultAuthorizerMock.getAddress(),
    composableCow,
    vaultRelayer,
    '0xc990bae86208bfdfba8879b64ab68da5905e8bb97aa3da5c701ec1183317a6f6'
  );

  await cowSwapBurner.deploymentTransaction().wait();
  const cowSwapBurnerAddress = await cowSwapBurner.getAddress();

  console.log('cowSwapBurner deployed at: ', cowSwapBurnerAddress);

  console.log('approve wei for cowSwapBurner...');
  await (await weth.approve(cowSwapBurnerAddress, testAmount)).wait();

  const lastBlock = await ethers.provider.getBlock('latest');
  if (!lastBlock) {
    throw new Error('last block not found');
  }

  console.log('last block: ', lastBlock?.number);
  console.log('last block timestamp: ', lastBlock?.timestamp);

  console.log('burning...');
  await (
    await cowSwapBurner.burn(
      ethers.ZeroAddress,
      wethAddress,
      testAmount,
      daiAddress,
      1,
      await account.getAddress(),
      lastBlock.timestamp + orderLifeTime
    )
  ).wait();

  console.log('order for burning created');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
