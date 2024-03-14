import { tenderly } from 'hardhat';

async function main() {
  const vault = '0x1FC7F1F84CFE61a04224AC8D3F87f56214FeC08c';
  await tenderly.verify({
    address: vault,
    name: 'Vault',
  });

  const vaultExtension = '0x718e1176f01dDBb2409A77B2847B749c8dF4457f';
  await tenderly.verify({
    address: vaultExtension,
    name: 'VaultExtension',
  });

  const vaultAdmin = '0x83bf399FA3DC49Af8fb5c34031a50c7C93F56129';
  await tenderly.verify({
    address: vaultAdmin,
    name: 'VaultAdmin',
  });

  const router = '0xA0De078cd5cFa7088821B83e0bD7545ccfb7c883';
  await tenderly.verify({
    address: router,
    name: 'Router',
  });

  const batchRouter = '0x8A8B9f35765899B3a0291700141470D79EA2eA88';
  await tenderly.verify({
    address: batchRouter,
    name: 'BatchRouter',
  });
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
