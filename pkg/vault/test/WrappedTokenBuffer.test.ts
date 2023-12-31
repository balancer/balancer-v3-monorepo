import { ethers } from 'hardhat';
import { expect } from 'chai';
import { deploy } from '@balancer-labs/v3-helpers/src/contract';
import { MONTH } from '@balancer-labs/v3-helpers/src/time';
import { VaultMock } from '../typechain-types/contracts/test/VaultMock';
import { ERC20TestToken } from '@balancer-labs/v3-solidity-utils/typechain-types/contracts/test/ERC20TestToken';
import { BasicAuthorizerMock } from '@balancer-labs/v3-solidity-utils/typechain-types/contracts/test/BasicAuthorizerMock';
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/dist/src/signer-with-address';
import { sharedBeforeEach } from '@balancer-labs/v3-common/sharedBeforeEach';
import { actionId } from '@balancer-labs/v3-helpers/src/models/misc/actions';
import { WrappedTokenMock } from '../typechain-types/contracts/test/WrappedTokenMock';
import { FP_ONE, bn } from '@balancer-labs/v3-helpers/src/numbers';
import { ANY_ADDRESS, ZERO_ADDRESS } from '@balancer-labs/v3-helpers/src/constants';
import { PoolCallbacksStruct, TokenConfigStruct, LiquidityManagementStruct } from '../typechain-types/contracts/Vault';

describe('Vault - Wrapped Token Buffers', function () {
  const PAUSE_WINDOW_DURATION = MONTH * 3;
  const BUFFER_PERIOD_DURATION = MONTH;

  enum TokenType {
    STANDARD = 0,
    WITH_RATE,
    ERC4626,
  }

  let vault: VaultMock;
  let authorizer: BasicAuthorizerMock;
  let baseToken: ERC20TestToken;
  let wrappedToken: WrappedTokenMock;

  let tokenA: ERC20TestToken;

  let alice: SignerWithAddress;

  before('setup signers', async () => {
    [, alice] = await ethers.getSigners();
  });

  sharedBeforeEach('deploy vault', async function () {
    authorizer = await deploy('v3-solidity-utils/BasicAuthorizerMock');
    vault = await deploy('VaultMock', {
      args: [authorizer.getAddress(), PAUSE_WINDOW_DURATION, BUFFER_PERIOD_DURATION],
    });

    baseToken = await deploy('v3-solidity-utils/ERC20TestToken', { args: ['Standard', 'BASE', 6] });
    wrappedToken = await deploy('WrappedTokenMock', { args: [baseToken, 'ERC4626', 'WRAPPED', 8] });

    tokenA = await deploy('v3-solidity-utils/ERC20TestToken', { args: ['Token A', 'TKNA', 18] });
  });

  describe('buffer registration', () => {
    context('without permission', () => {
      it('cannot register a buffer without permission', async () => {
        await expect(vault.registerBuffer(wrappedToken)).to.be.revertedWithCustomError(vault, 'SenderNotAllowed');
      });

      it('cannot get rate for unregistered buffer', async () => {
        await expect(vault.getWrappedTokenBufferRate(wrappedToken)).to.be.revertedWithCustomError(
          vault,
          'WrappedTokenBufferNotRegistered'
        );
      });
    });

    context('with permission', () => {
      sharedBeforeEach('grant permission', async () => {
        const registerBufferAction = await actionId(vault, 'registerBuffer');

        await authorizer.grantRole(registerBufferAction, alice.address);
      });

      it('can get the rate from a buffer', async () => {
        await vault.connect(alice).registerBuffer(wrappedToken);

        // With everything 0, it just returns 1 * 10^(decimal difference)
        const expectedRate = FP_ONE * bn(10 ** (8 - 6));

        const rate = await vault.getWrappedTokenBufferRate(wrappedToken);
        expect(rate).to.equal(expectedRate);
      });

      it('buffer registration emits an event', async () => {
        expect(await vault.connect(alice).registerBuffer(wrappedToken))
          .to.emit(vault, 'WrappedTokenBufferRegistered')
          .withArgs(baseToken, wrappedToken);
      });

      it('cannot register a buffer twice', async () => {
        vault.connect(alice).registerBuffer(wrappedToken);

        await expect(vault.connect(alice).registerBuffer(wrappedToken)).to.be.revertedWithCustomError(
          vault,
          'WrappedTokenBufferAlreadyRegistered'
        );
      });
    });
  });

  describe('pool registration', () => {
    sharedBeforeEach('grant permission', async () => {
      const registerBufferAction = await actionId(vault, 'registerBuffer');

      await authorizer.grantRole(registerBufferAction, alice.address);
    });

    const liquidityManagement: LiquidityManagementStruct = {
      supportsAddLiquidityCustom: false,
      supportsRemoveLiquidityCustom: false,
    };

    const poolCallbacks: PoolCallbacksStruct = {
      shouldCallBeforeSwap: false,
      shouldCallAfterSwap: false,
      shouldCallBeforeAddLiquidity: false,
      shouldCallAfterAddLiquidity: false,
      shouldCallBeforeRemoveLiquidity: false,
      shouldCallAfterRemoveLiquidity: false,
    };

    context('invalid configuration', () => {
      it('cannot register an ERC4626 without a buffer', async () => {
        const tokens: TokenConfigStruct[] = [
          { token: tokenA, tokenType: TokenType.STANDARD, rateProvider: ZERO_ADDRESS, yieldFeeExempt: false },
          { token: wrappedToken, tokenType: TokenType.ERC4626, rateProvider: ZERO_ADDRESS, yieldFeeExempt: false },
        ];

        await expect(
          vault.registerPool(ANY_ADDRESS, tokens, MONTH, ZERO_ADDRESS, poolCallbacks, liquidityManagement)
        ).to.be.revertedWithCustomError(vault, 'WrappedTokenBufferNotRegistered');
      });

      it('cannot register ERC4626 with an external rate provider', async () => {
        const tokens: TokenConfigStruct[] = [
          { token: tokenA, tokenType: TokenType.STANDARD, rateProvider: ZERO_ADDRESS, yieldFeeExempt: false },
          { token: wrappedToken, tokenType: TokenType.ERC4626, rateProvider: ANY_ADDRESS, yieldFeeExempt: false },
        ];
        vault.connect(alice).registerBuffer(wrappedToken);

        await expect(
          vault.registerPool(ANY_ADDRESS, tokens, MONTH, ZERO_ADDRESS, poolCallbacks, liquidityManagement)
        ).to.be.revertedWithCustomError(vault, 'InvalidTokenConfiguration');
      });

      it('cannot register ERC4626 yield exempt', async () => {
        const tokens: TokenConfigStruct[] = [
          { token: tokenA, tokenType: TokenType.STANDARD, rateProvider: ZERO_ADDRESS, yieldFeeExempt: false },
          { token: wrappedToken, tokenType: TokenType.ERC4626, rateProvider: ZERO_ADDRESS, yieldFeeExempt: true },
        ];
        vault.connect(alice).registerBuffer(wrappedToken);

        await expect(
          vault.registerPool(ANY_ADDRESS, tokens, MONTH, ZERO_ADDRESS, poolCallbacks, liquidityManagement)
        ).to.be.revertedWithCustomError(vault, 'InvalidTokenConfiguration');
      });

      it('cannot register a pool with duplicate Standard/ERC4626 base tokens', async () => {
        // This would look to the outside like base/base
        const tokens: TokenConfigStruct[] = [
          { token: baseToken, tokenType: TokenType.STANDARD, rateProvider: ZERO_ADDRESS, yieldFeeExempt: false },
          { token: wrappedToken, tokenType: TokenType.ERC4626, rateProvider: ZERO_ADDRESS, yieldFeeExempt: false },
        ];
        vault.connect(alice).registerBuffer(wrappedToken);

        await expect(vault.registerPool(ANY_ADDRESS, tokens, MONTH, ZERO_ADDRESS, poolCallbacks, liquidityManagement))
          .to.be.revertedWithCustomError(vault, 'AmbiguousPoolToken')
          .withArgs(await baseToken.getAddress());
      });
    });

    context('valid configuration', () => {
      let tokenAAddress: string;
      let baseAddress: string;
      let tokens: TokenConfigStruct[];

      sharedBeforeEach('set addresses', async () => {
        tokenAAddress = await tokenA.getAddress();
        baseAddress = await baseToken.getAddress();

        tokens = [
          { token: tokenA, tokenType: TokenType.STANDARD, rateProvider: ZERO_ADDRESS, yieldFeeExempt: false },
          { token: wrappedToken, tokenType: TokenType.ERC4626, rateProvider: ZERO_ADDRESS, yieldFeeExempt: false },
        ];
      });

      it('exposes base tokens for ERC4626', async () => {
        vault.connect(alice).registerBuffer(wrappedToken);
        await vault.registerPool(ANY_ADDRESS, tokens, MONTH, ZERO_ADDRESS, poolCallbacks, liquidityManagement);

        const poolTokens = await vault.getPoolTokens(ANY_ADDRESS);
        expect(poolTokens).to.deep.equal([tokenAAddress, baseAddress]);
      });

      it('registering a pool emits an event with resolved tokens', async () => {
        vault.connect(alice).registerBuffer(wrappedToken);

        expect(
          await vault
            .connect(alice)
            .registerPool(ANY_ADDRESS, tokens, MONTH, ZERO_ADDRESS, poolCallbacks, liquidityManagement)
        )
          .to.emit(vault, 'PoolRegistered')
          .withArgs(
            ANY_ADDRESS,
            await alice.getAddress(),
            [tokenAAddress, baseAddress],
            [TokenType.STANDARD, TokenType.ERC4626],
            [ZERO_ADDRESS, ZERO_ADDRESS],
            [false, false],
            MONTH,
            ZERO_ADDRESS,
            [false, false, false, false, false, false],
            [false, false]
          );
      });
    });
  });
});
