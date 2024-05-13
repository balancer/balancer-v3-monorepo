import { tenderly } from 'hardhat';

async function main() {
  await tenderly.verify({
    address: '0x2FAa140F90f76eeEEBC191f4eF4b2634be1E4e91',
    name: 'WeightedPoolFactory',
  });

  await tenderly.verify({
    address: '0x305eae21E208B61dbaE4654FfB6A4EB8045AeeAF',
    name: 'WeightedPool',
  });
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
