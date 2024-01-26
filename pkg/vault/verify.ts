import { tenderly } from 'hardhat';

async function main() {
  const vaultAddress = '0x816e90DC85bF016455017a76Bc09CC0451Eeb308'; // vault

  await tenderly.verify({
    address: vaultAddress,
    name: 'Vault',
  });

  const vaultExtensionAddress = '0x86a0E97eC0D5dB8DAE106D3067358d41968fD12c'; // vault extension

  await tenderly.verify({
    address: vaultExtensionAddress,
    name: 'VaultExtension',
  });
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
