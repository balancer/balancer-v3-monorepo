import path from 'path';
import { homedir } from 'os';
import { mkdirSync, writeFileSync } from 'fs';

const ENV_CONFIG_FILENAME = `${homedir()}/.env`;

if (process.env.CI) {
  const content = `export MAINNET_RPC_URL="${process.env.MAINNET_RPC_URL}"`;

  mkdirSync(path.dirname(ENV_CONFIG_FILENAME), { recursive: true });
  writeFileSync(ENV_CONFIG_FILENAME, content);
}
