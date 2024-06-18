import { expect } from 'chai';
import { Contract } from 'ethers';

import { deploy } from '@balancer-labs/v3-helpers/src/contract';
import { sharedBeforeEach } from '@balancer-labs/v3-common/sharedBeforeEach';

describe('InputHelpers (token sorting)', function () {
  const SORTED_TWO = ['0x10f3e79911A490aa5B5D5CDA6F111029c4Eab5AC', '0xc57b4BE50BF6BBe5f6a4fE379DA342B32b37bF2f'];
  const UNSORTED_TWO = ['0x1311Fbc9F60359639174c1e7cC2032DbDb5Cc4d1', '0x0f08eEf2C785AA5e7539684aF04755dEC1347b7c'];
  const CORRECTED_TWO = ['0x0f08eEf2C785AA5e7539684aF04755dEC1347b7c', '0x1311Fbc9F60359639174c1e7cC2032DbDb5Cc4d1'];

  const SORTED_THREE = [
    '0x1311Fbc9F60359639174c1e7cC2032DbDb5Cc4d1',
    '0x20356663C17D31549d1210379749E2aE36722D8f',
    '0xDB8d758BCb971e482B2C45f7F8a7740283A1bd3A',
  ];
  const UNSORTED_THREE = [
    '0xeA66501dF1A00261E3bB79D1E90444fc6A186B62',
    '0x481Ca759BABB6fF011E11890e183bE00de3714e7',
    '0x0f08eEf2C785AA5e7539684aF04755dEC1347b7c',
  ];
  const CORRECTED_THREE = [
    '0x0f08eEf2C785AA5e7539684aF04755dEC1347b7c',
    '0x481Ca759BABB6fF011E11890e183bE00de3714e7',
    '0xeA66501dF1A00261E3bB79D1E90444fc6A186B62',
  ];

  const SORTED_FOUR = [
    '0x35Cea9e57A393ac66Aaa7E25C391D52C74B5648f',
    '0x39A79EB449Fc05C92c39aA6f0e9BfaC03BE8dE5B',
    '0x5B42eC6D40f7B7965BE5308c70e2603c0281C1E9',
    '0xF1C849190Ecfae64d0Bd0a0708708E1De906aaB5',
  ];
  const UNSORTED_FOUR = [
    '0xC7B779AB638b7A59f490ac95199502343a81E006',
    '0xb7A32B67AAdB3866cC5c2FaBc6C6aB8a9027c3c1',
    '0x0d05Aac44aC7Dd3c7ba5d50Be93EB884A057d234',
    '0xBA12222222228d8Ba445958a75a0704d566BF2C8',
  ];
  const CORRECTED_FOUR = [
    '0x0d05Aac44aC7Dd3c7ba5d50Be93EB884A057d234',
    '0xb7A32B67AAdB3866cC5c2FaBc6C6aB8a9027c3c1',
    '0xBA12222222228d8Ba445958a75a0704d566BF2C8',
    '0xC7B779AB638b7A59f490ac95199502343a81E006',
  ];

  let lib: Contract;

  sharedBeforeEach(async function () {
    lib = await deploy('InputHelpersMock');
  });

  it('ensures tokens are sorted', async () => {
    expect(await lib.ensureSortedTokens(SORTED_TWO)).to.not.be.reverted;
    expect(await lib.ensureSortedTokens(SORTED_THREE)).to.not.be.reverted;
    expect(await lib.ensureSortedTokens(SORTED_FOUR)).to.not.be.reverted;

    await expect(lib.ensureSortedTokens(UNSORTED_TWO)).to.be.revertedWithCustomError(lib, 'TokensNotSorted');
    await expect(lib.ensureSortedTokens(UNSORTED_THREE)).to.be.revertedWithCustomError(lib, 'TokensNotSorted');
    await expect(lib.ensureSortedTokens(UNSORTED_FOUR)).to.be.revertedWithCustomError(lib, 'TokensNotSorted');
  });

  it('sorts tokens', async () => {
    const sortedTwo = await lib.sortTokens(UNSORTED_TWO);
    expect(sortedTwo).to.deep.equal(CORRECTED_TWO);

    const sortedThree = await lib.sortTokens(UNSORTED_THREE);
    expect(sortedThree).to.deep.equal(CORRECTED_THREE);

    const sortedFour = await lib.sortTokens(UNSORTED_FOUR);
    expect(sortedFour).to.deep.equal(CORRECTED_FOUR);
  });

  it('does not mutate already sorted tokens', async () => {
    const sortedTwo = await lib.sortTokens(SORTED_TWO);
    expect(sortedTwo).to.deep.equal(SORTED_TWO);

    const sortedThree = await lib.sortTokens(SORTED_THREE);
    expect(sortedThree).to.deep.equal(SORTED_THREE);

    const sortedFour = await lib.sortTokens(SORTED_FOUR);
    expect(sortedFour).to.deep.equal(SORTED_FOUR);
  });
});
