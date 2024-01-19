import { ethers } from 'hardhat';
import { expect } from 'chai';
import { Contract } from 'ethers';
import { deploy, deployedAt } from '@balancer-labs/v3-helpers/src/contract';
import { MONTH } from '@balancer-labs/v3-helpers/src/time';
import { ERC20TestToken } from '@balancer-labs/v3-solidity-utils/typechain-types/contracts/test/ERC20TestToken';
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/dist/src/signer-with-address';
import { sharedBeforeEach } from '@balancer-labs/v3-common/sharedBeforeEach';
import { actionId } from '@balancer-labs/v3-helpers/src/models/misc/actions';
import { WrappedTokenMock } from '../typechain-types/contracts/test/WrappedTokenMock';
import { FP_ONE, bn, fp } from '@balancer-labs/v3-helpers/src/numbers';
import { ANY_ADDRESS, ZERO_ADDRESS } from '@balancer-labs/v3-helpers/src/constants';
import { PoolCallbacksStruct, TokenConfigStruct, LiquidityManagementStruct } from '../typechain-types/contracts/Vault';
import * as VaultDeployer from '@balancer-labs/v3-helpers/src/models/vault/VaultDeployer';
import TypesConverter from '@balancer-labs/v3-helpers/src/models/types/TypesConverter';
import { VaultExtensionMock } from '../typechain-types';
import { IVaultMock } from '@balancer-labs/v3-interfaces/typechain-types';

describe('Vault - Wrapped Token Buffers', function () {
  const PAUSE_WINDOW_DURATION = MONTH * 3;
  const BUFFER_PERIOD_DURATION = MONTH;

  enum TokenType {
    STANDARD = 0,
    WITH_RATE,
    ERC4626,
  }

  let vault: IVaultMock;
  let vaultExtension: VaultExtensionMock;
  let authorizer: Contract;
  let baseToken: ERC20TestToken;
  let wrappedToken: WrappedTokenMock;

  let tokenA: ERC20TestToken;

  let alice: SignerWithAddress;

  before('setup signers', async () => {
    [, alice] = await ethers.getSigners();
  });

  sharedBeforeEach('deploy vault', async function () {
    const vaultMock = await VaultDeployer.deployMock({
      pauseWindowDuration: PAUSE_WINDOW_DURATION,
      bufferPeriodDuration: BUFFER_PERIOD_DURATION,
    });
    vault = await TypesConverter.toIVaultMock(vaultMock);

    vaultExtension = (await deployedAt(
      'VaultExtensionMock',
      await vault.getVaultExtension()
    )) as unknown as VaultExtensionMock;

    const authorizerAddress = await vault.getAuthorizer();
    authorizer = await deployedAt('v3-solidity-utils/BasicAuthorizerMock', authorizerAddress);
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
      shouldCallBeforeInitialize: false,
      shouldCallAfterInitialize: false,
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
          .to.be.revertedWithCustomError(vaultExtension, 'AmbiguousPoolToken')
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

  describe('buffer operations', () => {
    const AMOUNT = fp(1000);

    sharedBeforeEach('grant permission', async () => {
      const registerBufferAction = await actionId(vault, 'registerBuffer');

      await authorizer.grantRole(registerBufferAction, alice.address);
    });

    context('invalid input', () => {
      it('cannot deposit to unregistered buffer', async () => {
        await expect(vault.depositToBuffer(wrappedToken, AMOUNT, AMOUNT)).to.be.revertedWithCustomError(
          vault,
          'WrappedTokenBufferNotRegistered'
        );
      });

      it('cannot deposit without permission', async () => {
        await vault.connect(alice).registerBuffer(wrappedToken);

        await expect(vault.depositToBuffer(wrappedToken, AMOUNT, AMOUNT)).to.be.revertedWithCustomError(
          vault,
          'SenderNotAllowed'
        );
      });

      it('cannot check shares in non-existent buffer', async () => {
        await expect(vault.getBufferShares(wrappedToken)).to.be.revertedWithCustomError(
          vault,
          'WrappedTokenBufferNotRegistered'
        );
      });

      it('cannot check total supply of a non-existent buffer', async () => {
        await expect(vault.getTotalSupplyOfBuffer(wrappedToken)).to.be.revertedWithCustomError(
          vault,
          'WrappedTokenBufferNotRegistered'
        );
      });

      it('cannot withdraw from non-existent buffer', async () => {
        await expect(vault.withdrawFromBuffer(wrappedToken, AMOUNT, AMOUNT)).to.be.revertedWithCustomError(
          vault,
          'WrappedTokenBufferNotRegistered'
        );
      });

      it('cannot withdraw without shares', async () => {
        await vault.connect(alice).registerBuffer(wrappedToken);

        await expect(vault.withdrawFromBuffer(wrappedToken, AMOUNT, AMOUNT)).to.be.revertedWithCustomError(
          vault,
          'InsufficientSharesForBufferWithdrawal'
        );
      });
    });

    context('buffer deposits', async () => {
      sharedBeforeEach('register buffer and grant permission', async () => {
        await vault.connect(alice).registerBuffer(wrappedToken);
        const depositAction = await actionId(vault, 'depositToBuffer');

        await authorizer.grantRole(depositAction, alice.address);

        await baseToken.mint(alice, AMOUNT);
        await baseToken.connect(alice).approve(vault, AMOUNT);

        await wrappedToken.mint(AMOUNT, alice);
        await wrappedToken.connect(alice).approve(vault, AMOUNT);
      });

      it('initial shares are 0', async () => {
        expect(await vault.getBufferShares(wrappedToken)).to.be.zero;
      });

      it('initial supply is 0', async () => {
        expect(await vault.getTotalSupplyOfBuffer(wrappedToken)).to.be.zero;
      });

      it('can deposit to a buffer', async () => {
        // Tokens should be there
        expect(await baseToken.balanceOf(alice)).to.eq(AMOUNT);
        expect(await wrappedToken.balanceOf(alice)).to.eq(AMOUNT);

        await vault.connect(alice).depositToBuffer(wrappedToken, AMOUNT, AMOUNT);

        // total supply should be non-zero after depositing
        expect(await vault.getTotalSupplyOfBuffer(wrappedToken)).to.eq(AMOUNT * 2n);

        // alice should have shares after depositing
        expect(await vault.connect(alice).getBufferShares(wrappedToken)).to.eq(AMOUNT * 2n);

        // Tokens should be gone
        expect(await baseToken.balanceOf(alice)).to.be.zero;
        expect(await wrappedToken.balanceOf(alice)).to.be.zero;
      });

      it('depositing emits an event', async () => {
        expect(await vault.connect(alice).depositToBuffer(wrappedToken, AMOUNT, AMOUNT))
          .to.emit(vault, 'TokensDepositedToBuffer')
          .withArgs(baseToken, wrappedToken, AMOUNT, AMOUNT);
      });

      it('can withdraw from a buffer', async () => {
        await vault.connect(alice).depositToBuffer(wrappedToken, AMOUNT, AMOUNT);

        // alice should have shares after depositing
        expect(await vault.connect(alice).getBufferShares(wrappedToken)).to.eq(AMOUNT * 2n);

        await vault.connect(alice).withdrawFromBuffer(wrappedToken, AMOUNT, AMOUNT);

        // shares should now be zero
        expect(await vault.connect(alice).getBufferShares(wrappedToken)).to.be.zero;

        // total supply should now be zero
        expect(await vault.getTotalSupplyOfBuffer(wrappedToken)).to.be.zero;

        // Tokens should be restored
        expect(await baseToken.balanceOf(alice)).to.eq(AMOUNT);
        expect(await wrappedToken.balanceOf(alice)).to.eq(AMOUNT);
      });

      it('withdrawing emits an event', async () => {
        await vault.connect(alice).depositToBuffer(wrappedToken, AMOUNT, AMOUNT);

        expect(await vault.connect(alice).withdrawFromBuffer(wrappedToken, AMOUNT, AMOUNT))
          .to.emit(vault, 'TokensWithdrawnFromBuffer')
          .withArgs(baseToken, wrappedToken, AMOUNT, AMOUNT);
      });
    });
  });
});
