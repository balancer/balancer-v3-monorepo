import { tenderly } from 'hardhat';

async function main() {
  const weightedPoolFactory = '0xc00fF743B73346c9a4C40509e0550FfC18e5426d';
  await tenderly.verify({
    address: weightedPoolFactory,
    name: 'WeightedPoolFactory',
  });

  const weightedPool = '0xb0948D31C1a2C338C68402cd58CA7f2962aa14A9';
  await tenderly.verify({
    address: weightedPool,
    name: 'WeightedPool',
  });
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
