// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import { IVaultEvents } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultEvents.sol";
import { IVaultAdmin } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultAdmin.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IBatchRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IBatchRouter.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { ERC4626TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC4626TestToken.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract BufferVaultPrimitiveTest is BaseVaultTest {
    using FixedPoint for uint256;

    uint256 private constant _userAmount = 10e6 * 1e18;
    uint256 private constant _wrapAmount = _userAmount / 100;

    function setUp() public virtual override {
        BaseVaultTest.setUp();

        // Authorizes user "admin" to pause/unpause vault's buffer.
        authorizer.grantRole(vault.getActionId(IVaultAdmin.pauseVaultBuffers.selector), admin);
        authorizer.grantRole(vault.getActionId(IVaultAdmin.unpauseVaultBuffers.selector), admin);
        // Authorizes router to call removeLiquidityFromBuffer (trusted router).
        authorizer.grantRole(vault.getActionId(IVaultAdmin.removeLiquidityFromBuffer.selector), address(router));

        initializeLp();
    }

    function initializeLp() private {
        // Create and fund buffer pools.
        vm.startPrank(lp);

        // Minting wrong token to wrapped token contracts, to test changing the asset.
        dai.mint(address(waUSDC), _userAmount);
        usdc.mint(address(waDAI), _userAmount);

        vm.stopPrank();
    }

    /********************************************************************************
                                        Asset
    ********************************************************************************/

    function testChangeAssetOfWrappedTokenAddLiquidityToBuffer() public {
        // Change Asset to the correct asset.
        waDAI.setAsset(dai);

        vm.prank(lp);
        bufferRouter.initializeBuffer(IERC4626(address(waDAI)), _wrapAmount, _wrapAmount, 0);

        // Change Asset to the wrong asset.
        waDAI.setAsset(usdc);

        vm.prank(lp);
        vm.expectRevert(
            abi.encodeWithSelector(IVaultErrors.WrongUnderlyingToken.selector, address(waDAI), address(usdc))
        );
        bufferRouter.addLiquidityToBuffer(IERC4626(address(waDAI)), MAX_UINT128, MAX_UINT128, 2 * _wrapAmount);
    }

    function testChangeAssetOfWrappedTokenRemoveLiquidityFromBuffer() public {
        // Change Asset to the correct asset.
        waDAI.setAsset(dai);

        vm.prank(lp);
        uint256 lpShares = bufferRouter.initializeBuffer(IERC4626(address(waDAI)), _wrapAmount, _wrapAmount, 0);

        // Change Asset to the wrong asset.
        waDAI.setAsset(usdc);

        // Does not revert: remove liquidity doesn't check whether the asset matches the registered one in order to
        // avoid external calls. You can always exit the buffer, even if the wrapper is corrupt and updated its asset.
        vm.prank(lp);
        vault.removeLiquidityFromBuffer(IERC4626(address(waDAI)), lpShares, 0, 0);
    }

    function testChangeAssetOfWrappedTokenWrapUnwrap() public {
        // Change Asset to the correct asset.
        waDAI.setAsset(dai);

        // Wrap token should pass, since there's no liquidity in the buffer.
        IBatchRouter.SwapPathExactAmountIn[] memory paths = _wrapExactInPath(_wrapAmount, 0, IERC20(address(waDAI)));

        vm.prank(lp);
        bufferRouter.initializeBuffer(IERC4626(address(waDAI)), _wrapAmount, _wrapAmount, 0);

        // Change Asset to the wrong asset.
        waDAI.setAsset(usdc);

        // Wrap token should fail, since buffer has liquidity.
        vm.prank(lp);
        vm.expectRevert(
            abi.encodeWithSelector(IVaultErrors.WrongUnderlyingToken.selector, address(waDAI), address(usdc))
        );
        batchRouter.swapExactIn(paths, MAX_UINT256, false, bytes(""));
    }

    function testExactInOverflow() public {
        // Above permit2 limit of uint160.
        uint256 overflowAmount = type(uint168).max;

        IBatchRouter.SwapPathExactAmountIn[] memory paths = _wrapExactInPath(overflowAmount, 0, IERC20(address(waDAI)));

        vm.prank(lp);
        vm.expectRevert(abi.encodeWithSelector(SafeCast.SafeCastOverflowedUintDowncast.selector, 160, overflowAmount));
        batchRouter.swapExactIn(paths, MAX_UINT256, false, bytes(""));
    }

    /********************************************************************************
                                    Initialization
    ********************************************************************************/
    function testIsERC4626BufferInitialized() public {
        assertFalse(vault.isERC4626BufferInitialized(waDAI), "waDAI buffer is initialized");
        vm.prank(lp);
        bufferRouter.initializeBuffer(IERC4626(address(waDAI)), _wrapAmount, _wrapAmount, 0);

        assertTrue(vault.isERC4626BufferInitialized(waDAI), "waDAI buffer is not initialized");
    }

    /********************************************************************************
                                        Deposit
    ********************************************************************************/
    function testDepositBufferBalancedNotEnoughLiquidity() public {
        // Initializes the buffer with an amount that's not enough to fulfill the deposit operation, so the Vault has
        // to interact with the ERC4626 protocol.
        vm.startPrank(lp);
        bufferRouter.initializeBuffer(
            IERC4626(address(waDAI)),
            _wrapAmount / 10,
            waDAI.previewDeposit(_wrapAmount / 10),
            0
        );
        vm.stopPrank();

        IBatchRouter.SwapPathExactAmountIn[] memory paths = _wrapExactInPath(_wrapAmount, 0, IERC20(address(waDAI)));

        (, , IERC20[] memory tokens) = _getTokenArrayAndIndexesOfWaDaiBuffer();
        BaseVaultTest.Balances memory balancesBefore = getBalances(lp, tokens);
        BufferBalance memory bufferBalanceBefore = _getBufferBalance();

        vm.prank(lp);
        (uint256[] memory pathAmountsOut, , ) = batchRouter.swapExactIn(paths, MAX_UINT256, false, bytes(""));

        _checkWrapResults(balancesBefore, _wrapAmount, pathAmountsOut[0], bufferBalanceBefore, false);
    }

    function testDepositBufferMoreWrappedNotEnoughLiquidity() public {
        // Initializes the buffer with an amount that's not enough to fulfill the deposit operation, so the Vault has
        // to interact with the ERC4626 protocol.

        uint256 totalUnderlyingInBuffer = _wrapAmount / 2;
        vm.startPrank(lp);
        bufferRouter.initializeBuffer(
            IERC4626(address(waDAI)),
            totalUnderlyingInBuffer / 3,
            waDAI.previewDeposit((2 * totalUnderlyingInBuffer) / 3),
            0
        );
        vm.stopPrank();

        IBatchRouter.SwapPathExactAmountIn[] memory paths = _wrapExactInPath(_wrapAmount, 0, IERC20(address(waDAI)));

        (, , IERC20[] memory tokens) = _getTokenArrayAndIndexesOfWaDaiBuffer();
        BaseVaultTest.Balances memory balancesBefore = getBalances(lp, tokens);
        BufferBalance memory bufferBalanceBefore = _getBufferBalance();

        vm.prank(lp);
        (uint256[] memory pathAmountsOut, , ) = batchRouter.swapExactIn(paths, MAX_UINT256, false, bytes(""));

        _checkWrapResults(balancesBefore, _wrapAmount, pathAmountsOut[0], bufferBalanceBefore, false);
    }

    function testDepositBufferMoreUnderlyingNotEnoughLiquidity() public {
        // Initializes the buffer with an amount that's not enough to fulfill the deposit operation, so the Vault has
        // to interact with the ERC4626 protocol.

        uint256 totalUnderlyingInBuffer = _wrapAmount / 2;
        vm.startPrank(lp);
        bufferRouter.initializeBuffer(
            IERC4626(address(waDAI)),
            (2 * totalUnderlyingInBuffer) / 3,
            waDAI.previewDeposit(totalUnderlyingInBuffer / 3),
            0
        );
        vm.stopPrank();

        IBatchRouter.SwapPathExactAmountIn[] memory paths = _wrapExactInPath(_wrapAmount, 0, IERC20(address(waDAI)));

        (, , IERC20[] memory tokens) = _getTokenArrayAndIndexesOfWaDaiBuffer();
        BaseVaultTest.Balances memory balancesBefore = getBalances(lp, tokens);
        BufferBalance memory bufferBalanceBefore = _getBufferBalance();

        vm.prank(lp);
        (uint256[] memory pathAmountsOut, , ) = batchRouter.swapExactIn(paths, MAX_UINT256, false, bytes(""));

        _checkWrapResults(balancesBefore, _wrapAmount, pathAmountsOut[0], bufferBalanceBefore, false);
    }

    function testDepositUsingBufferLiquidity() public {
        // Initializes the buffer with an amount that's enough to fulfill the deposit operation without interacting
        // with the ERC4626 protocol.
        vm.startPrank(lp);
        bufferRouter.initializeBuffer(
            IERC4626(address(waDAI)),
            2 * _wrapAmount,
            waDAI.previewDeposit(2 * _wrapAmount),
            0
        );
        vm.stopPrank();

        IBatchRouter.SwapPathExactAmountIn[] memory paths = _wrapExactInPath(_wrapAmount, 0, IERC20(address(waDAI)));

        (, , IERC20[] memory tokens) = _getTokenArrayAndIndexesOfWaDaiBuffer();
        BaseVaultTest.Balances memory balancesBefore = getBalances(lp, tokens);
        BufferBalance memory bufferBalanceBefore = _getBufferBalance();

        vm.prank(lp);
        (uint256[] memory pathAmountsOut, , ) = batchRouter.swapExactIn(paths, MAX_UINT256, false, bytes(""));

        _checkWrapResults(balancesBefore, _wrapAmount, pathAmountsOut[0], bufferBalanceBefore, true);
    }

    function testDepositMaliciousRouter() public {
        vm.startPrank(lp);
        bufferRouter.initializeBuffer(IERC4626(address(waDAI)), _wrapAmount, waDAI.previewDeposit(_wrapAmount), 0);
        vm.stopPrank();

        // Deposit will not take the underlying tokens, keeping the approval, so the wrapper can use vault approval to
        // drain the whole vault.
        waDAI.setMaliciousWrapper(true);

        uint256 vaultBalance = dai.balanceOf(address(vault));

        // The malicious erc4626 consumes 0 underlying when the deposit is called, so the Vault leaves an approval
        // unused. This approval is then used to transfer underlying tokens from the Vault to the wrapper.
        vault.unlock(
            abi.encodeCall(
                BufferVaultPrimitiveTest.erc4626MaliciousHook,
                BufferWrapOrUnwrapParams({
                    kind: SwapKind.EXACT_IN,
                    direction: WrappingDirection.WRAP,
                    wrappedToken: IERC4626(address(waDAI)),
                    amountGivenRaw: vaultBalance,
                    limitRaw: 0
                })
            )
        );

        assertEq(dai.allowance(address(vault), address(waDAI)), 0, "Leftover allowance between vault and wrapper");
    }

    /********************************************************************************
                                        Mint
    ********************************************************************************/

    function testMintBufferBalancedNotEnoughLiquidity() public {
        // Initializes the buffer with an amount that's not enough to fulfill the mint operation, so the Vault has
        // to interact with the ERC4626 protocol.
        vm.startPrank(lp);
        bufferRouter.initializeBuffer(
            IERC4626(address(waDAI)),
            _wrapAmount / 10,
            waDAI.previewDeposit(_wrapAmount / 10),
            0
        );
        vm.stopPrank();

        IBatchRouter.SwapPathExactAmountOut[] memory paths = _wrapExactOutPath(
            2 * _wrapAmount,
            waDAI.previewDeposit(_wrapAmount),
            IERC20(address(waDAI))
        );

        (, , IERC20[] memory tokens) = _getTokenArrayAndIndexesOfWaDaiBuffer();
        BaseVaultTest.Balances memory balancesBefore = getBalances(lp, tokens);
        BufferBalance memory bufferBalanceBefore = _getBufferBalance();

        vm.prank(lp);
        (uint256[] memory pathAmountsIn, , ) = batchRouter.swapExactOut(paths, MAX_UINT256, false, bytes(""));

        _checkWrapResults(
            balancesBefore,
            pathAmountsIn[0],
            waDAI.previewDeposit(_wrapAmount),
            bufferBalanceBefore,
            false
        );
    }

    function testMintBufferMoreWrappedNotEnoughLiquidity() public {
        // Initializes the buffer with an amount that's not enough to fulfill the mint operation, so the Vault has
        // to interact with the ERC4626 protocol.

        uint256 totalUnderlyingInBuffer = _wrapAmount / 2;
        vm.startPrank(lp);
        bufferRouter.initializeBuffer(
            IERC4626(address(waDAI)),
            (totalUnderlyingInBuffer) / 3,
            waDAI.previewDeposit((2 * totalUnderlyingInBuffer) / 3),
            0
        );
        vm.stopPrank();

        IBatchRouter.SwapPathExactAmountOut[] memory paths = _wrapExactOutPath(
            2 * _wrapAmount,
            waDAI.previewDeposit(_wrapAmount),
            IERC20(address(waDAI))
        );

        (, , IERC20[] memory tokens) = _getTokenArrayAndIndexesOfWaDaiBuffer();
        BaseVaultTest.Balances memory balancesBefore = getBalances(lp, tokens);
        BufferBalance memory bufferBalanceBefore = _getBufferBalance();

        vm.prank(lp);
        (uint256[] memory pathAmountsIn, , ) = batchRouter.swapExactOut(paths, MAX_UINT256, false, bytes(""));

        _checkWrapResults(
            balancesBefore,
            pathAmountsIn[0],
            waDAI.previewDeposit(_wrapAmount),
            bufferBalanceBefore,
            false
        );
    }

    function testMintBufferMoreUnderlyingNotEnoughLiquidity() public {
        // Initializes the buffer with an amount that's not enough to fulfill the mint operation, so the Vault has
        // to interact with the ERC4626 protocol.

        uint256 totalUnderlyingInBuffer = _wrapAmount / 2;
        vm.startPrank(lp);
        bufferRouter.initializeBuffer(
            IERC4626(address(waDAI)),
            (2 * totalUnderlyingInBuffer) / 3,
            waDAI.previewDeposit(totalUnderlyingInBuffer / 3),
            0
        );
        vm.stopPrank();

        IBatchRouter.SwapPathExactAmountOut[] memory paths = _wrapExactOutPath(
            2 * _wrapAmount,
            waDAI.previewDeposit(_wrapAmount),
            IERC20(address(waDAI))
        );

        (, , IERC20[] memory tokens) = _getTokenArrayAndIndexesOfWaDaiBuffer();
        BaseVaultTest.Balances memory balancesBefore = getBalances(lp, tokens);
        BufferBalance memory bufferBalanceBefore = _getBufferBalance();

        vm.prank(lp);
        (uint256[] memory pathAmountsIn, , ) = batchRouter.swapExactOut(paths, MAX_UINT256, false, bytes(""));

        _checkWrapResults(
            balancesBefore,
            pathAmountsIn[0],
            waDAI.previewDeposit(_wrapAmount),
            bufferBalanceBefore,
            false
        );
    }

    function testMintWithBufferLiquidity() public {
        // Initializes the buffer with an amount that's enough to fulfill the mint operation without interacting
        // with the ERC4626 protocol.
        vm.startPrank(lp);
        bufferRouter.initializeBuffer(
            IERC4626(address(waDAI)),
            2 * _wrapAmount,
            waDAI.previewDeposit(2 * _wrapAmount),
            0
        );
        vm.stopPrank();

        IBatchRouter.SwapPathExactAmountOut[] memory paths = _wrapExactOutPath(
            2 * _wrapAmount,
            waDAI.previewDeposit(_wrapAmount),
            IERC20(address(waDAI))
        );

        (, , IERC20[] memory tokens) = _getTokenArrayAndIndexesOfWaDaiBuffer();
        BaseVaultTest.Balances memory balancesBefore = getBalances(lp, tokens);
        BufferBalance memory bufferBalanceBefore = _getBufferBalance();

        vm.prank(lp);
        (uint256[] memory pathAmountsIn, , ) = batchRouter.swapExactOut(paths, MAX_UINT256, false, bytes(""));

        _checkWrapResults(
            balancesBefore,
            pathAmountsIn[0],
            waDAI.previewDeposit(_wrapAmount),
            bufferBalanceBefore,
            true
        );
    }

    function testMintMaliciousRouter() public {
        vm.startPrank(lp);
        bufferRouter.initializeBuffer(IERC4626(address(waDAI)), _wrapAmount, waDAI.previewDeposit(_wrapAmount), 0);
        vm.stopPrank();

        // Deposit will not take the underlying tokens, keeping the approval, so the wrapper can use vault approval to
        // drain the whole vault.
        waDAI.setMaliciousWrapper(true);

        vault.unlock(
            abi.encodeCall(
                BufferVaultPrimitiveTest.erc4626MaliciousHook,
                BufferWrapOrUnwrapParams({
                    kind: SwapKind.EXACT_OUT,
                    direction: WrappingDirection.WRAP,
                    wrappedToken: IERC4626(address(waDAI)),
                    amountGivenRaw: PRODUCTION_MIN_WRAP_AMOUNT,
                    limitRaw: MAX_UINT128
                })
            )
        );

        // After a wrap operation, even if the erc4626 token didn't take all the assets it was supposed to deposit,
        // the allowance should be 0 to avoid a malicious wrapper from draining the underlying balance of the Vault.
        assertTrue(dai.allowance(address(vault), address(waDAI)) == 0, "Wrong allowance");
    }

    /********************************************************************************
                                        Redeem
    ********************************************************************************/

    function testRedeemBufferBalancedNotEnoughLiquidity() public {
        // Initializes the buffer with an amount that's not enough to fulfill the redeem operation, so the Vault has
        // to interact with the ERC4626 protocol.
        vm.startPrank(lp);
        bufferRouter.initializeBuffer(
            IERC4626(address(waDAI)),
            _wrapAmount / 10,
            waDAI.previewDeposit(_wrapAmount / 10),
            0
        );
        vm.stopPrank();

        uint256 wrappedAmountIn = waDAI.previewWithdraw(_wrapAmount);
        IERC20 wDai = IERC20(address(waDAI));

        IBatchRouter.SwapPathExactAmountIn[] memory paths = _unwrapExactInPath(wrappedAmountIn, 0, wDai);

        (, , IERC20[] memory tokens) = _getTokenArrayAndIndexesOfWaDaiBuffer();
        BaseVaultTest.Balances memory balancesBefore = getBalances(lp, tokens);
        BufferBalance memory bufferBalanceBefore = _getBufferBalance();

        vm.prank(lp);
        (uint256[] memory pathAmountsOut, , ) = batchRouter.swapExactIn(paths, MAX_UINT256, false, bytes(""));

        _checkUnwrapResults(balancesBefore, wrappedAmountIn, pathAmountsOut[0], bufferBalanceBefore, false);
    }

    function testRedeemBufferMoreWrappedNotEnoughLiquidity() public {
        // Initializes the buffer with an amount that's not enough to fulfill the redeem operation, so the Vault has
        // to interact with the ERC4626 protocol.
        uint256 totalUnderlyingInBuffer = _wrapAmount / 2;
        vm.startPrank(lp);
        bufferRouter.initializeBuffer(
            IERC4626(address(waDAI)),
            (totalUnderlyingInBuffer) / 3,
            waDAI.previewDeposit((2 * totalUnderlyingInBuffer) / 3),
            0
        );
        vm.stopPrank();

        uint256 wrappedAmountIn = waDAI.previewWithdraw(_wrapAmount);
        IERC20 wDai = IERC20(address(waDAI));

        IBatchRouter.SwapPathExactAmountIn[] memory paths = _unwrapExactInPath(wrappedAmountIn, 0, wDai);

        (, , IERC20[] memory tokens) = _getTokenArrayAndIndexesOfWaDaiBuffer();
        BaseVaultTest.Balances memory balancesBefore = getBalances(lp, tokens);
        BufferBalance memory bufferBalanceBefore = _getBufferBalance();

        vm.prank(lp);
        (uint256[] memory pathAmountsOut, , ) = batchRouter.swapExactIn(paths, MAX_UINT256, false, bytes(""));

        _checkUnwrapResults(balancesBefore, wrappedAmountIn, pathAmountsOut[0], bufferBalanceBefore, false);
    }

    function testRedeemBufferMoreUnderlyingNotEnoughLiquidity() public {
        // Initializes the buffer with an amount that's not enough to fulfill the redeem operation, so the Vault has
        // to interact with the ERC4626 protocol.
        uint256 totalUnderlyingInBuffer = _wrapAmount / 2;
        vm.startPrank(lp);
        bufferRouter.initializeBuffer(
            IERC4626(address(waDAI)),
            (2 * totalUnderlyingInBuffer) / 3,
            waDAI.previewDeposit(totalUnderlyingInBuffer / 3),
            0
        );
        vm.stopPrank();

        uint256 wrappedAmountIn = waDAI.previewWithdraw(_wrapAmount);
        IERC20 wDai = IERC20(address(waDAI));

        IBatchRouter.SwapPathExactAmountIn[] memory paths = _unwrapExactInPath(wrappedAmountIn, 0, wDai);

        (, , IERC20[] memory tokens) = _getTokenArrayAndIndexesOfWaDaiBuffer();
        BaseVaultTest.Balances memory balancesBefore = getBalances(lp, tokens);
        BufferBalance memory bufferBalanceBefore = _getBufferBalance();

        vm.prank(lp);
        (uint256[] memory pathAmountsOut, , ) = batchRouter.swapExactIn(paths, MAX_UINT256, false, bytes(""));

        _checkUnwrapResults(balancesBefore, wrappedAmountIn, pathAmountsOut[0], bufferBalanceBefore, false);
    }

    function testRedeemWithBufferLiquidity() public {
        // Initializes the buffer with an amount that's enough to fulfill the mint operation without interacting
        // with the ERC4626 protocol.
        vm.startPrank(lp);
        bufferRouter.initializeBuffer(
            IERC4626(address(waDAI)),
            2 * _wrapAmount,
            waDAI.previewDeposit(2 * _wrapAmount),
            0
        );
        vm.stopPrank();

        uint256 wrappedAmountIn = waDAI.previewWithdraw(_wrapAmount);
        IERC20 wDai = IERC20(address(waDAI));

        IBatchRouter.SwapPathExactAmountIn[] memory paths = _unwrapExactInPath(wrappedAmountIn, 0, wDai);

        (, , IERC20[] memory tokens) = _getTokenArrayAndIndexesOfWaDaiBuffer();
        BaseVaultTest.Balances memory balancesBefore = getBalances(lp, tokens);
        BufferBalance memory bufferBalanceBefore = _getBufferBalance();

        vm.prank(lp);
        (uint256[] memory pathAmountsOut, , ) = batchRouter.swapExactIn(paths, MAX_UINT256, false, bytes(""));

        _checkUnwrapResults(balancesBefore, wrappedAmountIn, pathAmountsOut[0], bufferBalanceBefore, true);
    }

    /********************************************************************************
                                        Withdraw
    ********************************************************************************/

    function testWithdrawBufferBalancedNotEnoughLiquidity() public {
        // Initializes the buffer with an amount that's not enough to fulfill the withdraw operation, so the Vault has
        // to interact with the ERC4626 protocol.
        vm.startPrank(lp);
        bufferRouter.initializeBuffer(
            IERC4626(address(waDAI)),
            _wrapAmount / 10,
            waDAI.previewDeposit(_wrapAmount / 10),
            0
        );
        vm.stopPrank();

        IBatchRouter.SwapPathExactAmountOut[] memory paths = _unwrapExactOutPath(
            2 * waDAI.previewDeposit(_wrapAmount),
            _wrapAmount,
            IERC20(address(waDAI))
        );

        (, , IERC20[] memory tokens) = _getTokenArrayAndIndexesOfWaDaiBuffer();
        BaseVaultTest.Balances memory balancesBefore = getBalances(lp, tokens);
        BufferBalance memory bufferBalanceBefore = _getBufferBalance();

        vm.prank(lp);
        (uint256[] memory pathAmountsIn, , ) = batchRouter.swapExactOut(paths, MAX_UINT256, false, bytes(""));

        _checkUnwrapResults(balancesBefore, pathAmountsIn[0], _wrapAmount, bufferBalanceBefore, false);
    }

    function testWithdrawBufferMoreWrappedNotEnoughLiquidity() public {
        // Initializes the buffer with an amount that's not enough to fulfill the withdraw operation, so the Vault has
        // to interact with the ERC4626 protocol.
        uint256 totalUnderlyingInBuffer = _wrapAmount / 2;
        vm.startPrank(lp);
        bufferRouter.initializeBuffer(
            IERC4626(address(waDAI)),
            (totalUnderlyingInBuffer) / 3,
            waDAI.previewDeposit((2 * totalUnderlyingInBuffer) / 3),
            0
        );
        vm.stopPrank();

        IBatchRouter.SwapPathExactAmountOut[] memory paths = _unwrapExactOutPath(
            2 * waDAI.previewDeposit(_wrapAmount),
            _wrapAmount,
            IERC20(address(waDAI))
        );

        (, , IERC20[] memory tokens) = _getTokenArrayAndIndexesOfWaDaiBuffer();
        BaseVaultTest.Balances memory balancesBefore = getBalances(lp, tokens);
        BufferBalance memory bufferBalanceBefore = _getBufferBalance();

        vm.prank(lp);
        (uint256[] memory pathAmountsIn, , ) = batchRouter.swapExactOut(paths, MAX_UINT256, false, bytes(""));

        _checkUnwrapResults(balancesBefore, pathAmountsIn[0], _wrapAmount, bufferBalanceBefore, false);
    }

    function testWithdrawBufferMoreUnderlyingNotEnoughLiquidity() public {
        // Initializes the buffer with an amount that's not enough to fulfill the withdraw operation, so the Vault has
        // to interact with the ERC4626 protocol.
        uint256 totalUnderlyingInBuffer = _wrapAmount / 2;
        vm.startPrank(lp);
        bufferRouter.initializeBuffer(
            IERC4626(address(waDAI)),
            (2 * totalUnderlyingInBuffer) / 3,
            waDAI.previewDeposit(totalUnderlyingInBuffer / 3),
            0
        );
        vm.stopPrank();

        IBatchRouter.SwapPathExactAmountOut[] memory paths = _unwrapExactOutPath(
            waDAI.previewWithdraw(_wrapAmount),
            _wrapAmount,
            IERC20(address(waDAI))
        );

        (, , IERC20[] memory tokens) = _getTokenArrayAndIndexesOfWaDaiBuffer();
        BaseVaultTest.Balances memory balancesBefore = getBalances(lp, tokens);
        BufferBalance memory bufferBalanceBefore = _getBufferBalance();

        vm.prank(lp);
        (uint256[] memory pathAmountsIn, , ) = batchRouter.swapExactOut(paths, MAX_UINT256, false, bytes(""));

        _checkUnwrapResults(balancesBefore, pathAmountsIn[0], _wrapAmount, bufferBalanceBefore, false);
    }

    function testWithdrawWithBufferLiquidity() public {
        // Initializes the buffer with an amount that's enough to fulfill the mint operation without interacting
        // with the ERC4626 protocol.
        vm.startPrank(lp);
        bufferRouter.initializeBuffer(
            IERC4626(address(waDAI)),
            2 * _wrapAmount,
            waDAI.previewDeposit(2 * _wrapAmount),
            0
        );
        vm.stopPrank();

        IBatchRouter.SwapPathExactAmountOut[] memory paths = _unwrapExactOutPath(
            2 * waDAI.previewDeposit(_wrapAmount),
            _wrapAmount,
            IERC20(address(waDAI))
        );

        (, , IERC20[] memory tokens) = _getTokenArrayAndIndexesOfWaDaiBuffer();
        BaseVaultTest.Balances memory balancesBefore = getBalances(lp, tokens);
        BufferBalance memory bufferBalanceBefore = _getBufferBalance();

        vm.prank(lp);
        (uint256[] memory pathAmountsIn, , ) = batchRouter.swapExactOut(paths, MAX_UINT256, false, bytes(""));

        _checkUnwrapResults(balancesBefore, pathAmountsIn[0], _wrapAmount, bufferBalanceBefore, true);
    }

    /********************************************************************************
                                Disable Vault Buffers
    ********************************************************************************/

    // Make sure only authorized users can disable/enable vault buffers.
    function testDisableVaultBufferAuthentication() public {
        vm.prank(alice);
        // Should revert, since alice has no rights to disable buffer.
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        IVaultAdmin(address(vault)).pauseVaultBuffers();

        vm.prank(admin);
        // Should pass, since admin has access.
        IVaultAdmin(address(vault)).pauseVaultBuffers();

        vm.prank(alice);
        // Should revert, since alice has no rights to enable buffer.
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        IVaultAdmin(address(vault)).unpauseVaultBuffers();

        vm.prank(admin);
        // Should pass, since admin has access.
        IVaultAdmin(address(vault)).unpauseVaultBuffers();
    }

    function testDisableVaultBuffer() public {
        vm.prank(lp);
        bufferRouter.initializeBuffer(IERC4626(address(waDAI)), _wrapAmount, _wrapAmount, 0);

        vm.prank(admin);
        IVaultAdmin(address(vault)).pauseVaultBuffers();

        IBatchRouter.SwapPathExactAmountIn[] memory paths = _wrapExactInPath(_wrapAmount, 0, IERC20(address(waDAI)));

        // Wrap/unwrap, add and remove liquidity should fail, since vault buffers are disabled.
        vm.startPrank(lp);

        vm.expectRevert(IVaultErrors.VaultBuffersArePaused.selector);
        batchRouter.swapExactIn(paths, MAX_UINT256, false, bytes(""));

        vm.expectRevert(IVaultErrors.VaultBuffersArePaused.selector);
        bufferRouter.addLiquidityToBuffer(IERC4626(address(waDAI)), MAX_UINT128, MAX_UINT128, 2 * _wrapAmount);

        // Remove liquidity is supposed to pass even with buffers paused, so revert is not expected.
        vault.removeLiquidityFromBuffer(IERC4626(address(waDAI)), _wrapAmount, 0, 0);

        vm.stopPrank();

        vm.prank(admin);
        IVaultAdmin(address(vault)).unpauseVaultBuffers();

        // Deposit should pass, since vault buffers are enabled.
        vm.prank(lp);
        batchRouter.swapExactIn(paths, MAX_UINT256, false, bytes(""));
    }

    /********************************************************************************
                          Add/Remove Liquidity from Buffers
    ********************************************************************************/

    function testAddLiquidityToBuffer() public {
        vm.startPrank(lp);
        bufferRouter.initializeBuffer(waDAI, 1e18, waDAI.previewDeposit(1e18), 0);
        vm.stopPrank();

        BufferAndLPBalances memory beforeBalances = _measureBuffer();

        uint256 lpSharesBeforeAdd = vault.getBufferOwnerShares(waDAI, lp);
        uint256 lpSharesToAdd = 2 * _wrapAmount;

        uint256 totalShares = vault.getBufferTotalShares(waDAI);
        // Multiply the current buffer balance by the invariant ratio (new shares / total shares) to calculate the
        // amount of underlying and wrapped tokens added, keeping the proportion of the buffer.
        uint256 expectedUnderlyingAmountIn = beforeBalances.buffer.dai.mulDivUp(lpSharesToAdd, totalShares);
        uint256 expectedWrappedAmountIn = beforeBalances.buffer.waDai.mulDivUp(lpSharesToAdd, totalShares);

        vm.prank(lp);
        bufferRouter.addLiquidityToBuffer(waDAI, MAX_UINT128, MAX_UINT128, lpSharesToAdd);

        BufferAndLPBalances memory afterBalances = _measureBuffer();

        assertEq(
            afterBalances.buffer.dai,
            beforeBalances.buffer.dai + expectedUnderlyingAmountIn,
            "Buffer DAI balance is wrong"
        );
        assertEq(
            afterBalances.buffer.waDai,
            beforeBalances.buffer.waDai + expectedWrappedAmountIn,
            "Buffer waDAI balance is wrong"
        );

        assertEq(
            afterBalances.vault.dai,
            beforeBalances.vault.dai + expectedUnderlyingAmountIn,
            "Vault DAI balance is wrong"
        );
        assertEq(
            afterBalances.vault.waDai,
            beforeBalances.vault.waDai + expectedWrappedAmountIn,
            "Vault waDAI balance is wrong"
        );

        assertEq(
            afterBalances.vaultReserves.dai,
            beforeBalances.vaultReserves.dai + expectedUnderlyingAmountIn,
            "Vault Reserve DAI balance is wrong"
        );
        assertEq(
            afterBalances.vaultReserves.waDai,
            beforeBalances.vaultReserves.waDai + expectedWrappedAmountIn,
            "Vault Reserve waDAI balance is wrong"
        );

        assertEq(afterBalances.lp.dai, beforeBalances.lp.dai - expectedUnderlyingAmountIn, "LP DAI balance is wrong");
        assertEq(
            afterBalances.lp.waDai,
            beforeBalances.lp.waDai - expectedWrappedAmountIn,
            "LP waDAI balance is wrong"
        );

        assertEq(
            lpSharesBeforeAdd + lpSharesToAdd,
            vault.getBufferOwnerShares(IERC4626(address(waDAI)), lp),
            "LP Buffer shares is wrong"
        );

        // Since underlying and wrapped amount in are rounded up, it can introduced rounding issues in favor of the
        // vault (`bufferInvariantDelta - 2e6 < sharesToAdd < bufferInvariantDelta`).
        uint256 bufferInvariantDelta = expectedUnderlyingAmountIn + waDAI.previewRedeem(expectedWrappedAmountIn);
        assertApproxEqAbs(lpSharesToAdd, bufferInvariantDelta - 1e6, 1e6, "Issued shares is wrong");
    }

    function testAddLiquidityToBufferWithRateChange() public {
        vm.prank(lp);
        {
            uint256 firstAddLpShares = bufferRouter.initializeBuffer(waDAI, _wrapAmount, _wrapAmount, 0);
            // After the first add liquidity operation, ending balances are (using 1000 for _wrapAmount for simplicity):
            // [1000 underlying, 1000 wrapped]; total supply is ~2000 (not counting the initialization).

            assertEq(
                firstAddLpShares,
                _wrapAmount + waDAI.previewRedeem(_wrapAmount) - BUFFER_MINIMUM_TOTAL_SUPPLY,
                "Wrong first lpShares added"
            );
        }

        uint256 rate = 2e18;

        waDAI.mockRate(rate);

        (uint256 bufferUnderlyingBalance, uint256 bufferWrappedBalance) = vault.getBufferBalance(waDAI);

        uint256 secondAddShares = _wrapAmount * 2;
        uint256 secondAddUnderlying;
        uint256 secondAddWrapped;

        uint256 totalShares = vault.getBufferTotalShares(waDAI);
        {
            // Multiply the current buffer balance by the invariant ratio (new shares / total shares) to calculate the
            // amount of underlying and wrapped tokens added, keeping the proportion of the buffer.
            uint256 expectedSecondAddUnderlying = bufferUnderlyingBalance.mulDivUp(secondAddShares, totalShares);
            uint256 expectedSecondAddWrapped = bufferWrappedBalance.mulDivUp(secondAddShares, totalShares);

            vm.prank(lp);
            (secondAddUnderlying, secondAddWrapped) = bufferRouter.addLiquidityToBuffer(
                waDAI,
                MAX_UINT128,
                MAX_UINT128,
                secondAddShares
            );
            assertEq(secondAddUnderlying, expectedSecondAddUnderlying, "Wrong second underlying added");
            assertEq(secondAddWrapped, expectedSecondAddWrapped, "Wrong second wrapped added");
        }

        (bufferUnderlyingBalance, bufferWrappedBalance) = vault.getBufferBalance(waDAI);

        totalShares = vault.getBufferTotalShares(waDAI);
        uint256 expectedUnderlyingOut = bufferUnderlyingBalance.mulDivUp(secondAddShares, totalShares);
        uint256 expectedWrappedOut = bufferWrappedBalance.mulDivUp(secondAddShares, totalShares);
        // Will get 1333.333/3333.333 = 40% of value:
        // [0.4 * 3000, 0.4 * 1000] = [1200 underlying, 400 wrapped] - worth 2000 = amount in.
        vm.prank(lp);
        (uint256 removedUnderlying, uint256 removedWrapped) = vault.removeLiquidityFromBuffer(
            waDAI,
            secondAddShares,
            0,
            0
        );

        assertApproxEqAbs(removedUnderlying, expectedUnderlyingOut, 1e6, "Wrong underlying amount removed");
        assertApproxEqAbs(removedWrapped, expectedWrappedOut, 1e6, "Wrong wrapped amount removed");

        uint256 underlyingValueAdded = secondAddUnderlying + waDAI.previewRedeem(secondAddWrapped);
        uint256 underlyingValueRemoved = removedUnderlying + waDAI.previewRedeem(removedWrapped);
        assertLe(underlyingValueRemoved, underlyingValueAdded, "Value removed > value added");
        // `underlyingValueAdded - 2e6 < underlyingValueRemoved < underlyingValueAdded`.
        assertApproxEqAbs(underlyingValueRemoved, underlyingValueAdded - 1e6, 1e6, "Value removed !~ value added");
    }

    // Trying to increase the coverage by splitting into two rate regimes, and limiting the range.
    function testAddLiquidityToBufferWithIncreasedRate_Fuzz(
        uint128 firstDepositUnderlying,
        uint128 firstDepositWrapped,
        uint128 secondDepositShares,
        uint64 rate
    ) public {
        _addLiquidityToBufferWithRate(
            bound(firstDepositUnderlying, 0, _wrapAmount),
            bound(firstDepositWrapped, 0, _wrapAmount),
            bound(secondDepositShares, 0, 2 * _wrapAmount),
            bound(rate, 1e18, 10_000e18)
        );
    }

    function testAddLiquidityToBufferWithDecreasedRate_Fuzz(
        uint128 firstDepositUnderlying,
        uint128 firstDepositWrapped,
        uint128 secondDepositShares,
        uint64 rate
    ) public {
        _addLiquidityToBufferWithRate(
            bound(firstDepositUnderlying, 0, _wrapAmount),
            bound(firstDepositWrapped, 0, _wrapAmount),
            bound(secondDepositShares, 0, 2 * _wrapAmount),
            bound(rate, 0.0001e18, 1e18)
        );
    }

    function _addLiquidityToBufferWithRate(
        uint256 firstDepositUnderlying,
        uint256 firstDepositWrapped,
        uint256 secondDepositShares,
        uint256 rate
    ) internal {
        // Ensure we're adding more than the minimum, or it will revert.
        vm.assume(firstDepositUnderlying + waDAI.previewRedeem(firstDepositWrapped) >= BUFFER_MINIMUM_TOTAL_SUPPLY);

        vm.prank(lp);
        uint256 firstAddLpShares = bufferRouter.initializeBuffer(waDAI, firstDepositUnderlying, firstDepositWrapped, 0);
        assertEq(
            firstAddLpShares,
            firstDepositUnderlying + waDAI.previewRedeem(firstDepositWrapped) - BUFFER_MINIMUM_TOTAL_SUPPLY,
            "Wrong first lpShares added"
        );

        // Change the rate after initialization.
        waDAI.mockRate(rate);

        // Compute the invariant after initialization, and before the second add operation.
        (uint256 bufferUnderlyingBalance, uint256 bufferWrappedBalance) = vault.getBufferBalance(waDAI);
        uint256 invariantBefore = bufferUnderlyingBalance + waDAI.previewRedeem(bufferWrappedBalance);

        // Make the second deposit, at the modified rate.
        vm.prank(lp);
        bufferRouter.addLiquidityToBuffer(waDAI, MAX_UINT128, MAX_UINT128, secondDepositShares);

        // Burn the shares from the second deposit
        vm.prank(lp);
        vault.removeLiquidityFromBuffer(waDAI, secondDepositShares, 0, 0);

        // Compute the invariant after the add/remove. Should be >= `invariantBefore`.
        (bufferUnderlyingBalance, bufferWrappedBalance) = vault.getBufferBalance(waDAI);
        uint256 invariantAfter = bufferUnderlyingBalance + waDAI.previewRedeem(bufferWrappedBalance);

        assertGe(invariantAfter, invariantBefore, "Invariant went down after add/remove");
    }

    function testRemoveLiquidityFromBuffer() public {
        uint256 underlyingAmountIn = _wrapAmount;
        uint256 wrappedAmountIn = _wrapAmount.mulDown(2e18);

        vm.prank(lp);
        uint256 lpShares = bufferRouter.initializeBuffer(waDAI, underlyingAmountIn, wrappedAmountIn, 0);

        BufferAndLPBalances memory beforeBalances = _measureBuffer();

        vm.expectEmit();
        emit IVaultEvents.BufferSharesBurned(IERC4626(waDAI), lp, lpShares);

        vm.prank(lp);
        (uint256 underlyingRemoved, uint256 wrappedRemoved) = vault.removeLiquidityFromBuffer(waDAI, lpShares, 0, 0);

        // The underlying and wrapped removed are not exactly the same as amountsIn, because part of the first deposit
        // is kept to not deplete the buffer and these shares (POOL_MINIMUM_TOTAL_SUPPLY) are "burned". The remove
        // liquidity operation is proportional to buffer balances, so the amount of burned shares must be discounted
        // proportionally from underlying and wrapped.
        uint256 bufferInvariant = underlyingAmountIn + waDAI.previewRedeem(wrappedAmountIn);
        assertEq(
            underlyingRemoved,
            underlyingAmountIn - BUFFER_MINIMUM_TOTAL_SUPPLY.mulUp(underlyingAmountIn).divUp(bufferInvariant),
            "Underlying removed is wrong"
        );
        assertEq(
            wrappedRemoved,
            wrappedAmountIn - BUFFER_MINIMUM_TOTAL_SUPPLY.mulUp(wrappedAmountIn).divUp(bufferInvariant),
            "Wrapped removed is wrong"
        );

        BufferAndLPBalances memory afterBalances = _measureBuffer();

        assertEq(
            afterBalances.buffer.dai,
            beforeBalances.buffer.dai - underlyingRemoved,
            "Buffer DAI balance is wrong"
        );
        assertEq(
            afterBalances.buffer.waDai,
            beforeBalances.buffer.waDai - wrappedRemoved,
            "Buffer waDAI balance is wrong"
        );

        assertEq(afterBalances.vault.dai, beforeBalances.vault.dai - underlyingRemoved, "Vault DAI balance is wrong");
        assertEq(
            afterBalances.vault.waDai,
            beforeBalances.vault.waDai - wrappedRemoved,
            "Vault waDAI balance is wrong"
        );

        assertEq(
            afterBalances.vaultReserves.dai,
            beforeBalances.vaultReserves.dai - underlyingRemoved,
            "Vault Reserve DAI balance is wrong"
        );
        assertEq(
            afterBalances.vaultReserves.waDai,
            beforeBalances.vaultReserves.waDai - wrappedRemoved,
            "Vault Reserve waDAI balance is wrong"
        );

        assertEq(afterBalances.lp.dai, beforeBalances.lp.dai + underlyingRemoved, "LP DAI balance is wrong");
        assertEq(afterBalances.lp.waDai, beforeBalances.lp.waDai + wrappedRemoved, "LP waDAI balance is wrong");

        assertEq(vault.getBufferOwnerShares(IERC4626(address(waDAI)), lp), 0, "LP Buffer shares is wrong");
        // If math has rounding issues, the rounding occurs in favor of the Vault
        // (invariantDelta <= lpShares <= invariantDelta + 2).
        uint256 bufferInvariantDelta = underlyingRemoved + waDAI.previewRedeem(wrappedRemoved);
        assertApproxEqAbs(lpShares, bufferInvariantDelta + 1, 1, "Removed assets are wrong");
    }

    struct BufferTokenBalances {
        uint256 waDai;
        uint256 dai;
    }

    struct BufferAndLPBalances {
        BufferTokenBalances lp;
        BufferTokenBalances buffer;
        BufferTokenBalances vault;
        BufferTokenBalances vaultReserves;
    }

    function _measureBuffer() private view returns (BufferAndLPBalances memory vars) {
        vars.lp.dai = dai.balanceOf(lp);
        vars.lp.waDai = waDAI.balanceOf(lp);

        (vars.buffer.dai, vars.buffer.waDai) = vault.getBufferBalance(IERC4626(address(waDAI)));

        vars.vault.dai = dai.balanceOf(address(vault));
        vars.vault.waDai = waDAI.balanceOf(address(vault));

        vars.vaultReserves.dai = vault.getReservesOf(dai);
        vars.vaultReserves.waDai = vault.getReservesOf(IERC20(address(waDAI)));
    }

    function _wrapExactInPath(
        uint256 exactAmountIn,
        uint256 minAmountOut,
        IERC20 wrappedToken
    ) private view returns (IBatchRouter.SwapPathExactAmountIn[] memory paths) {
        IBatchRouter.SwapPathStep[] memory steps = new IBatchRouter.SwapPathStep[](1);
        paths = new IBatchRouter.SwapPathExactAmountIn[](1);

        IERC20 tokenIn = IERC20(IERC4626(address(wrappedToken)).asset());
        IERC20 tokenOut = wrappedToken;

        steps[0] = IBatchRouter.SwapPathStep({ pool: address(wrappedToken), tokenOut: tokenOut, isBuffer: true });

        paths[0] = IBatchRouter.SwapPathExactAmountIn({
            tokenIn: tokenIn,
            steps: steps,
            exactAmountIn: exactAmountIn,
            minAmountOut: minAmountOut
        });
    }

    function _unwrapExactInPath(
        uint256 exactAmountIn,
        uint256 minAmountOut,
        IERC20 wrappedToken
    ) private view returns (IBatchRouter.SwapPathExactAmountIn[] memory paths) {
        IBatchRouter.SwapPathStep[] memory steps = new IBatchRouter.SwapPathStep[](1);
        paths = new IBatchRouter.SwapPathExactAmountIn[](1);

        IERC20 tokenIn = wrappedToken;
        IERC20 tokenOut = IERC20(IERC4626(address(wrappedToken)).asset());

        steps[0] = IBatchRouter.SwapPathStep({ pool: address(wrappedToken), tokenOut: tokenOut, isBuffer: true });

        paths[0] = IBatchRouter.SwapPathExactAmountIn({
            tokenIn: tokenIn,
            steps: steps,
            exactAmountIn: exactAmountIn,
            minAmountOut: minAmountOut
        });
    }

    function _wrapExactOutPath(
        uint256 maxAmountIn,
        uint256 exactAmountOut,
        IERC20 wrappedToken
    ) private view returns (IBatchRouter.SwapPathExactAmountOut[] memory paths) {
        IBatchRouter.SwapPathStep[] memory steps = new IBatchRouter.SwapPathStep[](1);
        paths = new IBatchRouter.SwapPathExactAmountOut[](1);

        IERC20 tokenIn = IERC20(IERC4626(address(wrappedToken)).asset());
        IERC20 tokenOut = wrappedToken;

        steps[0] = IBatchRouter.SwapPathStep({ pool: address(wrappedToken), tokenOut: tokenOut, isBuffer: true });

        paths[0] = IBatchRouter.SwapPathExactAmountOut({
            tokenIn: tokenIn,
            steps: steps,
            maxAmountIn: maxAmountIn,
            exactAmountOut: exactAmountOut
        });
    }

    function _unwrapExactOutPath(
        uint256 maxAmountIn,
        uint256 exactAmountOut,
        IERC20 wrappedToken
    ) private view returns (IBatchRouter.SwapPathExactAmountOut[] memory paths) {
        IBatchRouter.SwapPathStep[] memory steps = new IBatchRouter.SwapPathStep[](1);
        paths = new IBatchRouter.SwapPathExactAmountOut[](1);

        IERC20 tokenIn = wrappedToken;
        IERC20 tokenOut = IERC20(IERC4626(address(wrappedToken)).asset());

        steps[0] = IBatchRouter.SwapPathStep({ pool: address(wrappedToken), tokenOut: tokenOut, isBuffer: true });

        paths[0] = IBatchRouter.SwapPathExactAmountOut({
            tokenIn: tokenIn,
            steps: steps,
            maxAmountIn: maxAmountIn,
            exactAmountOut: exactAmountOut
        });
    }

    function _checkWrapResults(
        BaseVaultTest.Balances memory balancesBefore,
        uint256 underlyingAmountIn,
        uint256 wrappedAmountOut,
        BufferBalance memory bufferBalanceBefore,
        bool withBufferLiquidity
    ) private view {
        (uint256 daiIdx, uint256 waDaiIdx, IERC20[] memory tokens) = _getTokenArrayAndIndexesOfWaDaiBuffer();
        BaseVaultTest.Balances memory balancesAfter = getBalances(lp, tokens);

        // Check wrap results.
        assertEq(underlyingAmountIn, _wrapAmount, "AmountIn (underlying deposited) is wrong");
        assertEq(
            balancesAfter.lpTokens[daiIdx],
            balancesBefore.lpTokens[daiIdx] - _wrapAmount,
            "LP balance of underlying token is wrong"
        );
        uint256 expectedAmountOut = waDAI.previewDeposit(_wrapAmount);
        assertEq(wrappedAmountOut, expectedAmountOut, "AmountOut (wrapped minted) is wrong");
        assertEq(
            balancesAfter.lpTokens[waDaiIdx],
            balancesBefore.lpTokens[waDaiIdx] + expectedAmountOut,
            "LP balance of wrapped token is wrong"
        );

        // Check if buffer is balanced.
        BufferBalance memory bufferBalanceAfter = _getBufferBalance();
        if (withBufferLiquidity == false) {
            assertApproxEqAbs(
                bufferBalanceAfter.underlying,
                waDAI.previewRedeem(bufferBalanceAfter.wrapped),
                1,
                "Buffer is not balanced"
            );
        }
        int256 bufferUnderlyingImbalance = int256(bufferBalanceAfter.underlying) -
            int256(bufferBalanceBefore.underlying);
        int256 bufferWrappedImbalance = int256(bufferBalanceAfter.wrapped) - int256(bufferBalanceBefore.wrapped);

        if (withBufferLiquidity) {
            assertEq(underlyingAmountIn, uint256(bufferUnderlyingImbalance), "Wrong underlying buffer imbalance");
            assertEq(wrappedAmountOut, uint256(-bufferWrappedImbalance), "Wrong wrapped buffer imbalance");
        }

        // Check Vault reserves.
        assertEq(
            balancesAfter.vaultReserves[daiIdx],
            uint256(int256(balancesBefore.vaultReserves[daiIdx]) + bufferUnderlyingImbalance),
            "Vault reserves of underlying token is wrong"
        );
        assertEq(
            balancesAfter.vaultReserves[waDaiIdx],
            uint256(int256(balancesBefore.vaultReserves[waDaiIdx]) + bufferWrappedImbalance),
            "Vault reserves of wrapped token is wrong"
        );

        // Check that Vault balances match vault reserves.
        assertEq(
            balancesAfter.vaultReserves[daiIdx],
            balancesAfter.vaultTokens[daiIdx],
            "Vault balance of underlying token is wrong"
        );
        assertEq(
            balancesAfter.vaultReserves[waDaiIdx],
            balancesAfter.vaultTokens[waDaiIdx],
            "Vault balance of wrapped token is wrong"
        );
    }

    function _checkUnwrapResults(
        BaseVaultTest.Balances memory balancesBefore,
        uint256 wrappedAmountIn,
        uint256 underlyingAmountOut,
        BufferBalance memory bufferBalanceBefore,
        bool withBufferLiquidity
    ) private view {
        (uint256 daiIdx, uint256 waDaiIdx, IERC20[] memory tokens) = _getTokenArrayAndIndexesOfWaDaiBuffer();
        BaseVaultTest.Balances memory balancesAfter = getBalances(lp, tokens);

        // Check unwrap results.
        uint256 expectedWrappedAmountIn = waDAI.previewWithdraw(_wrapAmount);
        assertEq(wrappedAmountIn, expectedWrappedAmountIn, "WrappedAmountIn is wrong");
        assertEq(
            balancesAfter.lpTokens[waDaiIdx],
            balancesBefore.lpTokens[waDaiIdx] - expectedWrappedAmountIn,
            "LP balance of wrapped token is wrong"
        );
        // For unwrap exact in, when the buffer has enough liquidity to fulfill the operation, amountOut decreases by
        // conversion factor. Depending on the token rate, the value may change a bit, but it's important that
        // amountOut is smaller than _wrapAmount to make sure the buffer is not drained.
        uint256 expectedAmountOut = _wrapAmount;
        assertEq(underlyingAmountOut, expectedAmountOut, "AmountOut (underlying withdrawn) is wrong");
        assertEq(
            balancesAfter.lpTokens[daiIdx],
            balancesBefore.lpTokens[daiIdx] + expectedAmountOut,
            "LP balance of underlying token is wrong"
        );

        int256 bufferUnderlyingImbalance;
        int256 bufferWrappedImbalance;

        {
            // Check if buffer is balanced (tolerance of 1 wei to compensate previewMint rounding).
            BufferBalance memory bufferBalanceAfter = _getBufferBalance();
            if (withBufferLiquidity == false) {
                assertApproxEqAbs(
                    bufferBalanceAfter.underlying,
                    waDAI.previewMint(bufferBalanceAfter.wrapped),
                    1,
                    "Buffer is not balanced"
                );
            }
            bufferUnderlyingImbalance = int256(bufferBalanceAfter.underlying) - int256(bufferBalanceBefore.underlying);
            bufferWrappedImbalance = int256(bufferBalanceAfter.wrapped) - int256(bufferBalanceBefore.wrapped);

            if (withBufferLiquidity) {
                assertEq(underlyingAmountOut, uint256(-bufferUnderlyingImbalance), "Wrong underlying buffer imbalance");
                assertEq(wrappedAmountIn, uint256(bufferWrappedImbalance), "Wrong wrapped buffer imbalance");
            }
        }

        // Check Vault reserves.
        assertEq(
            balancesAfter.vaultReserves[daiIdx],
            uint256(int256(balancesBefore.vaultReserves[daiIdx]) + bufferUnderlyingImbalance),
            "Vault reserves of underlying token is wrong"
        );
        assertEq(
            balancesAfter.vaultReserves[waDaiIdx],
            uint256(int256(balancesBefore.vaultReserves[waDaiIdx]) + bufferWrappedImbalance),
            "Vault reserves of wrapped token is wrong"
        );

        // Check that Vault balances match vault reserves.
        assertEq(
            balancesAfter.vaultReserves[daiIdx],
            balancesAfter.vaultTokens[daiIdx],
            "Vault balance of underlying token is wrong"
        );
        assertEq(
            balancesAfter.vaultReserves[waDaiIdx],
            balancesAfter.vaultTokens[waDaiIdx],
            "Vault balance of wrapped token is wrong"
        );
    }

    function _getTokenArrayAndIndexesOfWaDaiBuffer()
        private
        view
        returns (uint256 daiIdx, uint256 waDaiIdx, IERC20[] memory tokens)
    {
        (daiIdx, waDaiIdx) = getSortedIndexes(address(dai), address(waDAI));
        tokens = new IERC20[](2);
        tokens[daiIdx] = dai;
        tokens[waDaiIdx] = IERC20(address(waDAI));
    }

    /// @notice Hook used to create a vault approval using a malicious erc4626 and drain the Vault.
    function erc4626MaliciousHook(BufferWrapOrUnwrapParams memory params) external {
        (, uint256 amountIn, uint256 amountOut) = vault.erc4626BufferWrapOrUnwrap(params);

        if (params.kind == SwapKind.EXACT_IN) {
            dai.mint(address(this), amountIn);
            dai.transfer(address(vault), amountIn);
            vault.settle(dai, amountIn);
            vault.sendTo(IERC20(address(waDAI)), address(this), amountOut);
        }

        if (params.kind == SwapKind.EXACT_OUT) {
            // When the wrap is EXACT_OUT, a minimum amount of tokens must be wrapped. so, balances need to be settled
            // at the end to not revert the transaction and keep an approval to remove underlying tokens from the
            // Vault.
            dai.mint(address(this), amountIn);
            dai.transfer(address(vault), amountIn);
            vault.settle(dai, amountIn);
            vault.sendTo(IERC20(address(waDAI)), address(this), amountOut);
        }
    }

    struct BufferBalance {
        uint256 underlying;
        uint256 wrapped;
    }

    function _getBufferBalance() private view returns (BufferBalance memory bufferBalance) {
        (uint256 bufferUnderlyingBalance, uint256 bufferWrappedBalance) = vault.getBufferBalance(
            IERC4626(address(waDAI))
        );
        bufferBalance.underlying = bufferUnderlyingBalance;
        bufferBalance.wrapped = bufferWrappedBalance;
    }
}
