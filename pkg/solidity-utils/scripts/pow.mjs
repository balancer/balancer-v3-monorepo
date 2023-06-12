import { create, all } from 'mathjs';
import { AbiCoder } from 'ethers';

const config = {
  number: 'BigNumber',
  precision: 64,
};

const mathInstance = create(all, config);

function calculatePower(base, exponent) {
  const ONE_18 = mathInstance.bignumber('1e+18');
  let baseBig = mathInstance.divide(mathInstance.bignumber(base), ONE_18);
  let exponentBig = mathInstance.divide(mathInstance.bignumber(exponent), ONE_18);

  let result = mathInstance.round(mathInstance.multiply(mathInstance.pow(baseBig, exponentBig), ONE_18));
  return mathInstance.format(result, { notation: 'fixed' });
}

// Use process.argv to get command line arguments
let base = process.argv[2];
let exponent = process.argv[3];

let result = calculatePower(base, exponent);
console.log(AbiCoder.defaultAbiCoder().encode(['uint256'], [result]));
