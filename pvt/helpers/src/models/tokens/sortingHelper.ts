function assert(condition: boolean, error: string): asserts condition {
  if (!condition) throw new Error(error);
}

const cmpTokens = (tokenA: string, tokenB: string): number => (tokenA.toLowerCase() > tokenB.toLowerCase() ? 1 : -1);

const transposeMatrix = (matrix: unknown[][]): unknown[][] =>
  matrix[0].map((_, columnIndex) => matrix.map((row) => row[columnIndex]));

export function sortTokens(tokens: string[], ...others: unknown[][]): [string[], ...unknown[][]] {
  others.forEach((array) => assert(tokens.length === array.length, 'array length mismatch'));

  const transpose = transposeMatrix([tokens, ...others]) as [string, ...unknown[]][];
  const sortedTranspose = transpose.sort(([tokenA], [tokenB]) => cmpTokens(tokenA, tokenB));
  const [sortedTokens, ...sortedOthers] = transposeMatrix(sortedTranspose) as [string[], ...unknown[][]];

  return [sortedTokens, ...sortedOthers];
}
