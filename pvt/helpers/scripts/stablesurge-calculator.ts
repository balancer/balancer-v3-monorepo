import { Command } from 'commander';

interface ProgramOptions {
  staticFee: number;
  threshold: number;
  maxFee: number;
}

function main() {
  const program = new Command();

  program.name('stablesurge-calculator').description('Process stable surge internal parameters').version('0.1.0');

  const parseFloatOrThrow = (value: string): number => {
    const floatValue = parseFloat(value);
    if (isNaN(floatValue)) {
      throw new Error(`Invalid numeric argument: ${value}`);
    }
    return floatValue;
  };

  program
    .argument('[balances...]', 'Pool balances after swap')
    .option('--sf, --static-fee <fee-percentage>', 'static fee percentage', parseFloatOrThrow, 0.1)
    .option('--t, --threshold <imbalance-threshold-percentage>', 'imbalance threshold percentage', parseFloatOrThrow, 5)
    .option('--mf, --max-fee <max-fee-percentage>', 'max fee percentage', parseFloatOrThrow, 100);

  program.parse();

  const options = program.opts() as ProgramOptions;

  // Skip the first two elements to get just the user-provided arguments
  const args: string[] = program.args;

  // Convert string arguments to numbers
  const balances: number[] = args.map((arg) => Number(arg));

  if (balances.length < 2) {
    throw new Error(
      'Invalid input: Please provide at least two numbers. Usage example: stablesurge-calculator.ts 95 105'
    );
  }

  // Check if we have valid numbers
  if (balances.some(isNaN)) {
    throw new Error(
      'Invalid input: Please provide valid numbers. Usage example: stablesurge-calculator.ts 100 200 300'
    );
  }

  const median = getMedian(balances);
  const balanceSum = balances.reduce((acc, balance) => acc + balance, 0);
  const totalDiff = balances.reduce((acc, balance) => acc + Math.abs(balance - median), 0);

  const imbalancePercentage = (totalDiff / balanceSum) * 100;
  console.log('Imbalance percentage: ' + imbalancePercentage.toFixed(2) + '%');

  console.log('Static fee percentage: ' + options.staticFee.toFixed(2) + '%');
  console.log('Surge threshold percentage: ' + options.threshold.toFixed(2) + '%');
  console.log('Max fee percentage: ' + options.maxFee.toFixed(2) + '%');

  let surgeFeePercentage = options.staticFee;
  if (imbalancePercentage > options.threshold) {
    surgeFeePercentage +=
      ((options.maxFee - options.staticFee) * (imbalancePercentage - options.threshold)) / (100 - options.threshold);
  }

  console.log('Surge fee percentage: ', surgeFeePercentage.toFixed(2) + '%');
}

function getMedian(list: number[]): number {
  if (list.length === 0) {
    throw new Error('Empty array: Cannot calculate median');
  }

  const sortedList = [...list].sort((a, b) => a - b);
  const middleIndex = Math.floor(sortedList.length / 2);

  if (sortedList.length % 2 === 0) {
    // Even number of elements, average the two middle elements
    return (sortedList[middleIndex - 1] + sortedList[middleIndex]) / 2;
  } else {
    // Odd number of elements, return the middle element
    return sortedList[middleIndex];
  }
}

main();
