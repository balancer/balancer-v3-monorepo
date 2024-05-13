import { tenderly } from 'hardhat';

async function main() {
  await tenderly.verify({
    address: '0xC09244C585F59cB61Cfb08e4fE7A560cD448834b',
    name: 'StablePoolFactory',
  });

  await tenderly.verify({
    address: '0x8846C5dbd8e9Dd6766A81ecDDa3Fb9636f28d872',
    name: 'StablePool',
  });
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
