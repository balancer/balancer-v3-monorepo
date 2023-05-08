import { getArtifact } from '@balancer-labs/v3-helpers/src/contract';

async function main() {
  console.log('== Deployment measurements ==');

  await measureDeployment('v3-vault/Vault');
}

async function measureDeployment(name: string) {
  console.log(`\n# ${name}`);

  const artifact = getArtifact(name);
  const bytecodeSizeBytes = artifact.deployedBytecode.slice(2).length / 2;

  console.log(`Deployed bytecode size is ${bytecodeSizeBytes} bytes`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
