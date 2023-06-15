import { expect } from 'chai';
import { isBn } from '../numbers';
import { ContractTransactionReceipt } from 'ethers';

// Ported from @openzeppelin/test-helpers to use with Ethers. The Test Helpers don't
// yet have Typescript typings, so we're being lax about them here.
// See https://github.com/OpenZeppelin/openzeppelin-test-helpers/issues/122

/* eslint-disable @typescript-eslint/no-explicit-any */

export function inReceipt(receipt: ContractTransactionReceipt, eventName: string, eventArgs = {}): any {
  if (receipt.logs == undefined) {
    throw new Error('No events found in receipt');
  }

  const events = receipt.logs.filter((e) => e.eventName === eventName);
  expect(events.length > 0).to.equal(true, `No '${eventName}' events found`);

  const exceptions: Array<string> = [];
  const event = events.find(function (e) {
    if (e.args == undefined) {
      throw new Error('Event has no arguments');
    }

    // Construct the event arguments (keys are in the fragment inputs; values are in the args)
    let actualEventArgs = {};
    e.fragment.inputs.forEach((key, i) => actualEventArgs[key.name] = e.args[i]);

    for (const [k, v] of Object.entries(eventArgs)) {
      try {
        contains(actualEventArgs, k, v);
      } catch (error) {
        exceptions.push(String(error));
        return false;
      }
    }
    return true;
  });

  if (event === undefined) {
    // Each event entry may have failed to match for different reasons,
    // throw the first one
    throw exceptions[0];
  }

  return event;
}

export function notEmitted(receipt: ContractTransactionReceipt, eventName: string): void {
  if (receipt.logs != undefined) {
    const events = receipt.logs.filter((e) => e.eventName === eventName);
    expect(events.length > 0).to.equal(false, `'${eventName}' event found`);
  }
}

function contains(args: { [key: string]: any | undefined }, key: string, value: any) {
  expect(key in args).to.equal(true, `Event argument '${key}' not found`);

  if (value === null) {
    expect(args[key]).to.equal(null, `expected event argument '${key}' to be null but got ${args[key]}`);
  } else if (isBn(args[key]) || isBn(value)) {
    const actual = isBn(args[key]) ? args[key].toString() : args[key];
    const expected = isBn(value) ? value.toString() : value;

    expect(args[key]).to.equal(value, `expected event argument '${key}' to have value ${expected} but got ${actual}`);
  } else {
    expect(args[key]).to.be.deep.equal(
      value,
      `expected event argument '${key}' to have value ${value} but got ${args[key]}`
    );
  }
}
