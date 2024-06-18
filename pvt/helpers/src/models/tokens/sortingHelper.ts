import { BaseContract } from 'ethers';

const cmpAddresses = (tokenA: string, tokenB: string): number => (tokenA.toLowerCase() > tokenB.toLowerCase() ? 1 : -1);

export function sortAddresses(tokens: string[]): string[] {
  return tokens.sort((tokenA, tokenB) => cmpAddresses(tokenA, tokenB));
}

export async function sortTokens(tokens: BaseContract[]): Promise<BaseContract[]> {
  const sortableArray = (await Promise.all(
    tokens.map(async (token) => [await token.getAddress(), token])
  )) as unknown as [string, BaseContract][];
  const sortedArray = sortableArray.sort((a, b) => (a[0].toLowerCase() > b[0].toLowerCase() ? 1 : -1));
  return sortedArray.map((x) => x[1]);
}
