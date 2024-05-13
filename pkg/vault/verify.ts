import { tenderly } from 'hardhat';

async function main() {
  await tenderly.verify({
    address: '0xc19F5ff2fef08196E9f43448A9cE296e447a4820',
    name: 'VaultAdmin',
  });

  await tenderly.verify({
    address: '0xA9AEeB57Efe61338C0d07f3e5Bb82519C4Ad1103',
    name: 'VaultExtension',
  });

  await tenderly.verify({
    address: '0x89aa28a8D2B327cD9dB4aDc0f259D757F000AE66',
    name: 'Vault',
  });

  await tenderly.verify({
    address: '0xa59F164d6cf6ee5d63580C0bcEA5CCB2e50b908c',
    name: 'Router',
  });

  await tenderly.verify({
    address: '0x0252Cdbd41114e657945772d02cB1eE8008E9E1D',
    name: 'BatchRouter',
  });
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
