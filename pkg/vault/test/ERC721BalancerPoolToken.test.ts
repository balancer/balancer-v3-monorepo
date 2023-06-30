import { ethers } from 'hardhat';
import { expect } from 'chai';
import { deploy } from '@balancer-labs/v3-helpers/src/contract';
import { MONTH, fromNow } from '@balancer-labs/v3-helpers/src/time';
import { VaultMock } from '../typechain-types/contracts/test/VaultMock';
import { BalancerPoolToken } from '../typechain-types/contracts/BalancerPoolToken';
import { ERC721BalancerPoolToken } from '../typechain-types/contracts/ERC721BalancerPoolToken';
import { ERC721MultiToken } from '../typechain-types/contracts/ERC721MultiToken';
import { TestToken } from '@balancer-labs/v3-solidity-utils/typechain-types/contracts/test/TestToken';
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/dist/src/signer-with-address';
import { sharedBeforeEach } from '@balancer-labs/v3-common/sharedBeforeEach';
import { ANY_ADDRESS, MAX_UINT256, ZERO_ADDRESS } from '@balancer-labs/v3-helpers/src/constants';
import '@balancer-labs/v3-common/setupTests';
import { bn, fp } from '@balancer-labs/v3-helpers/src/numbers';
import { Typed, Interface } from 'ethers';

const INTERFACES = {
  ERC165: ['supportsInterface(bytes4)'],
  ERC721: [
    'balanceOf(address)',
    'ownerOf(uint256)',
    'approve(address,uint256)',
    'getApproved(uint256)',
    'setApprovalForAll(address,bool)',
    'isApprovedForAll(address,address)',
    'transferFrom(address,address,uint256)',
    'safeTransferFrom(address,address,uint256)',
    'safeTransferFrom(address,address,uint256,bytes)',
  ],
  ERC721Metadata: ['name()', 'symbol()', 'tokenURI(uint256)'],
};

export function getInterfaceID(contractInterface: Interface, functions: string[]) {
  let interfaceID = 0n;
  for (const func of functions) {
    interfaceID = interfaceID ^ contractInterface.getSighash(func);
  }

  return interfaceID;
}

describe.only('ERC721BalancerPoolToken', function () {
  const WETH = '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2';

  const PAUSE_WINDOW_DURATION = MONTH * 3;
  const BUFFER_PERIOD_DURATION = MONTH;

  let vault: VaultMock;
  let erc721Pool: BalancerPoolToken;
  let usdc: TestToken;
  let usdt: TestToken;

  let vaultAddress: string;

  let user: SignerWithAddress;
  let other: SignerWithAddress;
  let relayer: SignerWithAddress;
  let factory: SignerWithAddress;

  let usdcAddress: string;
  let usdtAddress: string;

  let erc721PoolAddress: string;

  let tokenAddresses: string[];

  before('setup signers', async () => {
    [, user, other, factory, relayer] = await ethers.getSigners();
  });

  sharedBeforeEach('deploy vault, tokens, and pools', async function () {
    vault = await deploy('VaultMock', { args: [WETH, PAUSE_WINDOW_DURATION, BUFFER_PERIOD_DURATION] });
    vaultAddress = await vault.getAddress();

    usdc = await deploy('v3-solidity-utils/TestToken', { args: ['USDC', 'USDC', 6] });
    usdt = await deploy('v3-solidity-utils/TestToken', { args: ['USDT', 'USDT', 18] });

    usdcAddress = await usdc.getAddress();
    usdtAddress = await usdt.getAddress();

    tokenAddresses = [usdcAddress, usdtAddress];

    erc721Pool = await deploy('ERC721BalancerPoolToken', {
      args: [vaultAddress, factory, tokenAddresses, 'USDC Pool', 'POOL-USDC'],
    });

    erc721PoolAddress = await erc721Pool.getAddress();
  });

  function shouldSupportInterfaces(interfaces = []) {
    describe('ERC165', () => {
      it('all interfaces are reported as supported', async function () {
        for (const k of interfaces) {
          const interfaceId = INTERFACE_IDS[k] ?? k;
          expect(await this.contractUnderTest.supportsInterface(interfaceId)).to.equal(true, `does not support ${k}`);
        }
      });

      it('all interface functions are in ABI', async function () {
        for (const k of interfaces) {
          // skip interfaces for which we don't have a function list
          if (INTERFACES[k] === undefined) continue;
          for (const fnName of INTERFACES[k]) {
            const fnSig = FN_SIGNATURES[fnName];
            expect(this.contractUnderTest.abi.filter((fn) => fn.signature === fnSig).length).to.equal(
              1,
              `did not find ${fnName}`
            );
          }
        }
      });
    });
  }

  shouldSupportInterfaces(['ERC165', 'ERC721', 'ERC721Metadata']);
});
