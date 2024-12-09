import { expect } from 'chai';
import { deploy } from '@balancer-labs/v3-helpers/src/contract';
import { StableSurgeMedianMathMock } from '../typechain-types/contracts/test/StableSurgeMedianMathMock';

describe('StableSurgeMedianMath', function () {
  const MIN_TOKENS = 2;
  const MAX_TOKENS = 8;
  const TEST_ITERATIONS = 100;
  const MAX_VALUE = 100000;

  let surgeMath: StableSurgeMedianMathMock;

  function getRandomInt(min: number, max: number) {
    return Math.floor(Math.random() * (max - min + 1)) + min;
  }

  function findMedian(arr: Array<number>): number {
    arr.sort((a, b) => a - b);
    const middleIndex = Math.floor(arr.length / 2);

    if (arr.length % 2 === 0) {
      return Math.floor((arr[middleIndex - 1] + arr[middleIndex]) / 2);
    } else {
      return arr[middleIndex];
    }
  }

  before('deploy mock', async () => {
    surgeMath = await deploy('v3-pool-hooks/test/StableSurgeMedianMathMock');
  });

  it('absSub', async () => {
    for (let i = 0; i < TEST_ITERATIONS; i++) {
      const a = getRandomInt(0, MAX_VALUE);
      const b = getRandomInt(0, MAX_VALUE);
      const expectedResult = Math.abs(a - b);
      expect(await surgeMath.absSub(a, b)).to.eq(expectedResult);
      expect(await surgeMath.absSub(b, a)).to.eq(expectedResult);
    }
  });

  it('findMedian', async () => {
    const worthCaseOne = [800, 700, 600, 500, 400, 300, 200, 100];
    const worthCaseTwo = worthCaseOne.reverse();

    expect(Number(await surgeMath.findMedian(worthCaseOne))).to.eq(450);
    expect(Number(await surgeMath.findMedian(worthCaseTwo))).to.eq(450);

    for (let i = 0; i < TEST_ITERATIONS; i++) {
      const randomCase = new Array(getRandomInt(MIN_TOKENS, MAX_TOKENS)).fill(0).map(() => getRandomInt(0, MAX_VALUE));
      expect(Number(await surgeMath.findMedian(randomCase))).to.eq(findMedian(randomCase));
    }
  });

  it('calculateImbalance', async () => {
    for (let i = 0; i < TEST_ITERATIONS; i++) {
      const randomBalances = new Array(getRandomInt(MIN_TOKENS, MAX_TOKENS))
        .fill(0)
        .map(() => getRandomInt(0, MAX_VALUE));
      const median = findMedian(randomBalances);

      let totalDiff = 0;
      let totalBalance = 0;
      for (let i = 0; i < randomBalances.length; i++) {
        totalBalance += randomBalances[i];
        totalDiff += Math.abs(randomBalances[i] - median);
      }

      const expectedResult = (BigInt(totalDiff) * BigInt(1e18)) / BigInt(totalBalance);
      expect(Number(await surgeMath.calculateImbalance(randomBalances))).to.eq(Number(expectedResult));
    }
  });
});
