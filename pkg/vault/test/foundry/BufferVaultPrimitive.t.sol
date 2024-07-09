// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import { IVaultAdmin } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultAdmin.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IBatchRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IBatchRouter.sol";

import { ERC4626TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC4626TestToken.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract BufferVaultPrimitiveTest is BaseVaultTest {
    ERC4626TestToken internal waDAI;
    ERC4626TestToken internal waUSDC;

    uint256 private constant _userAmount = 10e6 * 1e18;
    uint256 private constant _wrapAmount = _userAmount / 100;

    uint256 private _ABOVE_CONVERT_ERROR;

    function setUp() public virtual override {
        BaseVaultTest.setUp();

        _ABOVE_CONVERT_ERROR = vault.getMaxConvertError() + 1;

        waDAI = new ERC4626TestToken(dai, "Wrapped aDAI", "waDAI", 18);
        vm.label(address(waDAI), "waDAI");

        // "USDC" is deliberately 18 decimals to test one thing at a time.
        waUSDC = new ERC4626TestToken(usdc, "Wrapped aUSDC", "waUSDC", 18);
        vm.label(address(waUSDC), "waUSDC");

        // Authorizes user "admin" to pause/unpause vault's buffer
        authorizer.grantRole(vault.getActionId(IVaultAdmin.pauseVaultBuffers.selector), admin);
        authorizer.grantRole(vault.getActionId(IVaultAdmin.unpauseVaultBuffers.selector), admin);
        // Authorizes router to call removeLiquidityFromBuffer (trusted router)
        authorizer.grantRole(vault.getActionId(IVaultAdmin.removeLiquidityFromBuffer.selector), address(router));

        initializeLp();
    }

    function initializeLp() private {
        // Create and fund buffer pools
        vm.startPrank(lp);

        dai.mint(lp, _userAmount);
        dai.approve(address(waDAI), _userAmount);
        waDAI.deposit(_userAmount, lp);

        usdc.mint(lp, _userAmount);
        usdc.approve(address(waUSDC), _userAmount);
        waUSDC.deposit(_userAmount, lp);

        // Minting wrong token to wrapped token contracts, to test changing the asset
        dai.mint(address(waUSDC), _userAmount);
        usdc.mint(address(waDAI), _userAmount);

        waDAI.approve(address(permit2), MAX_UINT256);
        permit2.approve(address(waDAI), address(router), type(uint160).max, type(uint48).max);
        permit2.approve(address(waDAI), address(batchRouter), type(uint160).max, type(uint48).max);
        waUSDC.approve(address(permit2), MAX_UINT256);
        permit2.approve(address(waUSDC), address(router), type(uint160).max, type(uint48).max);
        permit2.approve(address(waUSDC), address(batchRouter), type(uint160).max, type(uint48).max);
        vm.stopPrank();
    }

    /********************************************************************************
                                        Asset
    ********************************************************************************/
    function testChangeAssetOfWrappedToken() public {
        // Change Asset to wrong underlying
        waDAI.setAsset(usdc);

        // Wrap token should pass, since there's no liquidity in the buffer
        IBatchRouter.SwapPathExactAmountIn[] memory paths = _exactInWrapUnwrapPath(
            _wrapAmount,
            0,
            usdc,
            IERC20(address(waDAI)),
            IERC20(address(waDAI))
        );

        vm.prank(lp);
        batchRouter.swapExactIn(paths, MAX_UINT256, false, bytes(""));

        // Change Asset to correct asset
        waDAI.setAsset(dai);

        // Add Liquidity with the right asset
        vm.prank(lp);
        router.addLiquidityToBuffer(IERC4626(address(waDAI)), _wrapAmount, _wrapAmount, lp);

        // Change Asset to the wrong asset
        waDAI.setAsset(usdc);

        // Wrap token should fail, since buffer has liquidity
        vm.prank(lp);
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.WrongWrappedTokenAsset.selector, address(waDAI)));
        batchRouter.swapExactIn(paths, MAX_UINT256, false, bytes(""));
    }

    /********************************************************************************
                                        Deposit
    ********************************************************************************/
    function testDeposit() public {
        IBatchRouter.SwapPathExactAmountIn[] memory paths = _exactInWrapUnwrapPath(
            _wrapAmount,
            0,
            dai,
            IERC20(address(waDAI)),
            IERC20(address(waDAI))
        );

        uint256 lpUnderlyingBalanceBefore = dai.balanceOf(lp);
        uint256 lpWrappedBalanceBefore = IERC20(address(waDAI)).balanceOf(lp);

        vm.prank(lp);
        batchRouter.swapExactIn(paths, MAX_UINT256, false, bytes(""));

        uint256 lpUnderlyingBalanceAfter = dai.balanceOf(lp);
        uint256 lpWrappedBalanceAfter = IERC20(address(waDAI)).balanceOf(lp);

        assertEq(
            lpUnderlyingBalanceAfter,
            lpUnderlyingBalanceBefore - _wrapAmount,
            "LP balance of underlying token is wrong"
        );
        assertEq(
            lpWrappedBalanceAfter,
            lpWrappedBalanceBefore + waDAI.previewDeposit(_wrapAmount),
            "LP balance of wrapped token is wrong"
        );
    }

    function testDepositReturnsLessShares() public {
        IBatchRouter.SwapPathExactAmountIn[] memory paths = _exactInWrapUnwrapPath(
            _wrapAmount,
            0,
            dai,
            IERC20(address(waDAI)),
            IERC20(address(waDAI))
        );

        waDAI.setSharesToReturn(waDAI.previewDeposit(_wrapAmount) - _ABOVE_CONVERT_ERROR);

        vm.prank(lp);
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.WrongWrappedAmount.selector, address(waDAI)));
        batchRouter.swapExactIn(paths, MAX_UINT256, false, bytes(""));
    }

    function testDepositReturnsMoreShares() public {
        IBatchRouter.SwapPathExactAmountIn[] memory paths = _exactInWrapUnwrapPath(
            _wrapAmount,
            0,
            dai,
            IERC20(address(waDAI)),
            IERC20(address(waDAI))
        );

        waDAI.setSharesToReturn(waDAI.previewDeposit(_wrapAmount) + _ABOVE_CONVERT_ERROR);

        vm.prank(lp);
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.WrongWrappedAmount.selector, address(waDAI)));
        batchRouter.swapExactIn(paths, MAX_UINT256, false, bytes(""));
    }

    function testDepositConsumesLessAssets() public {
        IBatchRouter.SwapPathExactAmountIn[] memory paths = _exactInWrapUnwrapPath(
            _wrapAmount,
            0,
            dai,
            IERC20(address(waDAI)),
            IERC20(address(waDAI))
        );

        waDAI.setAssetsToConsume(_wrapAmount - _ABOVE_CONVERT_ERROR);

        vm.prank(lp);
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.WrongUnderlyingAmount.selector, address(waDAI)));
        batchRouter.swapExactIn(paths, MAX_UINT256, false, bytes(""));
    }

    function testDepositConsumesMoreAssets() public {
        uint256 changedWrapAmount = _wrapAmount + _ABOVE_CONVERT_ERROR;

        IBatchRouter.SwapPathExactAmountIn[] memory paths = _exactInWrapUnwrapPath(
            _wrapAmount,
            0,
            dai,
            IERC20(address(waDAI)),
            IERC20(address(waDAI))
        );

        waDAI.setAssetsToConsume(changedWrapAmount);

        // When the assets amount is higher than predicted, vault did not give allowance to make the transfer
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector,
                address(waDAI),
                _wrapAmount,
                changedWrapAmount
            )
        );
        vm.prank(lp);
        batchRouter.swapExactIn(paths, MAX_UINT256, false, bytes(""));
    }

    /********************************************************************************
                                        Mint
    ********************************************************************************/
    function testMint() public {
        IBatchRouter.SwapPathExactAmountOut[] memory paths = _exactOutWrapUnwrapPath(
            2 * _wrapAmount,
            _wrapAmount,
            dai,
            IERC20(address(waDAI)),
            IERC20(address(waDAI))
        );

        uint256 lpUnderlyingBalanceBefore = dai.balanceOf(lp);
        uint256 lpWrappedBalanceBefore = IERC20(address(waDAI)).balanceOf(lp);

        vm.prank(lp);
        batchRouter.swapExactOut(paths, MAX_UINT256, false, bytes(""));

        uint256 lpUnderlyingBalanceAfter = dai.balanceOf(lp);
        uint256 lpWrappedBalanceAfter = IERC20(address(waDAI)).balanceOf(lp);

        assertEq(
            lpUnderlyingBalanceAfter,
            lpUnderlyingBalanceBefore - waDAI.previewMint(_wrapAmount),
            "LP balance of underlying token is wrong"
        );
        assertEq(lpWrappedBalanceAfter, lpWrappedBalanceBefore + _wrapAmount, "LP balance of wrapped token is wrong");
    }

    function testMintReturnsLessShares() public {
        IBatchRouter.SwapPathExactAmountOut[] memory paths = _exactOutWrapUnwrapPath(
            2 * _wrapAmount,
            _wrapAmount,
            dai,
            IERC20(address(waDAI)),
            IERC20(address(waDAI))
        );

        waDAI.setSharesToReturn(_wrapAmount - _ABOVE_CONVERT_ERROR);

        vm.prank(lp);
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.WrongWrappedAmount.selector, address(waDAI)));
        batchRouter.swapExactOut(paths, MAX_UINT256, false, bytes(""));
    }

    function testMintReturnsMoreShares() public {
        IBatchRouter.SwapPathExactAmountOut[] memory paths = _exactOutWrapUnwrapPath(
            2 * _wrapAmount,
            _wrapAmount,
            dai,
            IERC20(address(waDAI)),
            IERC20(address(waDAI))
        );

        waDAI.setSharesToReturn(_wrapAmount + _ABOVE_CONVERT_ERROR);

        vm.prank(lp);
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.WrongWrappedAmount.selector, address(waDAI)));
        batchRouter.swapExactOut(paths, MAX_UINT256, false, bytes(""));
    }

    function testMintConsumesLessAssets() public {
        IBatchRouter.SwapPathExactAmountOut[] memory paths = _exactOutWrapUnwrapPath(
            2 * _wrapAmount,
            _wrapAmount,
            dai,
            IERC20(address(waDAI)),
            IERC20(address(waDAI))
        );

        waDAI.setAssetsToConsume(_wrapAmount - _ABOVE_CONVERT_ERROR);

        vm.prank(lp);
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.WrongUnderlyingAmount.selector, address(waDAI)));
        batchRouter.swapExactOut(paths, MAX_UINT256, false, bytes(""));
    }

    function testMintConsumesMoreAssets() public {
        uint256 changedWrapAmount = _wrapAmount + _ABOVE_CONVERT_ERROR;

        IBatchRouter.SwapPathExactAmountOut[] memory paths = _exactOutWrapUnwrapPath(
            2 * _wrapAmount,
            _wrapAmount,
            dai,
            IERC20(address(waDAI)),
            IERC20(address(waDAI))
        );

        waDAI.setAssetsToConsume(changedWrapAmount);

        // When the assets amount is higher than predicted, vault did not give allowance to make the transfer
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector,
                address(waDAI),
                _wrapAmount + vault.getMaxConvertError(),
                changedWrapAmount
            )
        );
        vm.prank(lp);
        batchRouter.swapExactOut(paths, MAX_UINT256, false, bytes(""));
    }

    /********************************************************************************
                                        Redeem
    ********************************************************************************/
    function testRedeem() public {
        IBatchRouter.SwapPathExactAmountIn[] memory paths = _exactInWrapUnwrapPath(
            _wrapAmount,
            0,
            IERC20(address(waDAI)),
            dai,
            IERC20(address(waDAI))
        );

        uint256 lpUnderlyingBalanceBefore = dai.balanceOf(lp);
        uint256 lpWrappedBalanceBefore = IERC20(address(waDAI)).balanceOf(lp);

        vm.prank(lp);
        batchRouter.swapExactIn(paths, MAX_UINT256, false, bytes(""));

        uint256 lpUnderlyingBalanceAfter = dai.balanceOf(lp);
        uint256 lpWrappedBalanceAfter = IERC20(address(waDAI)).balanceOf(lp);

        assertEq(
            lpUnderlyingBalanceAfter,
            lpUnderlyingBalanceBefore + _wrapAmount,
            "LP balance of underlying token is wrong"
        );
        assertEq(
            lpWrappedBalanceAfter,
            lpWrappedBalanceBefore - waDAI.previewRedeem(_wrapAmount),
            "LP balance of wrapped token is wrong"
        );
    }

    function testRedeemConsumesLessShares() public {
        IBatchRouter.SwapPathExactAmountIn[] memory paths = _exactInWrapUnwrapPath(
            _wrapAmount,
            0,
            IERC20(address(waDAI)),
            dai,
            IERC20(address(waDAI))
        );

        waDAI.setSharesToConsume(_wrapAmount - _ABOVE_CONVERT_ERROR);

        vm.prank(lp);
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.WrongWrappedAmount.selector, address(waDAI)));
        batchRouter.swapExactIn(paths, MAX_UINT256, false, bytes(""));
    }

    function testRedeemConsumesMoreShares() public {
        IBatchRouter.SwapPathExactAmountIn[] memory paths = _exactInWrapUnwrapPath(
            _wrapAmount,
            0,
            IERC20(address(waDAI)),
            dai,
            IERC20(address(waDAI))
        );

        waDAI.setSharesToConsume(_wrapAmount + _ABOVE_CONVERT_ERROR);

        vm.startPrank(lp);
        // Call addLiquidity so vault has enough liquidity to cover extra wrapped amount
        router.addLiquidityToBuffer(IERC4626(address(waDAI)), _wrapAmount, _wrapAmount, lp);
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.WrongWrappedAmount.selector, address(waDAI)));
        batchRouter.swapExactIn(paths, MAX_UINT256, false, bytes(""));
        vm.stopPrank();
    }

    function testRedeemReturnsMoreAssets() public {
        IBatchRouter.SwapPathExactAmountIn[] memory paths = _exactInWrapUnwrapPath(
            _wrapAmount,
            0,
            IERC20(address(waDAI)),
            dai,
            IERC20(address(waDAI))
        );

        waDAI.setAssetsToReturn(waDAI.previewRedeem(_wrapAmount) + _ABOVE_CONVERT_ERROR);

        vm.prank(lp);
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.WrongUnderlyingAmount.selector, address(waDAI)));
        batchRouter.swapExactIn(paths, MAX_UINT256, false, bytes(""));
    }

    function testRedeemReturnsLessAssets() public {
        IBatchRouter.SwapPathExactAmountIn[] memory paths = _exactInWrapUnwrapPath(
            _wrapAmount,
            0,
            IERC20(address(waDAI)),
            dai,
            IERC20(address(waDAI))
        );

        waDAI.setAssetsToReturn(waDAI.previewRedeem(_wrapAmount) - _ABOVE_CONVERT_ERROR);

        vm.prank(lp);
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.WrongUnderlyingAmount.selector, address(waDAI)));
        batchRouter.swapExactIn(paths, MAX_UINT256, false, bytes(""));
    }

    /********************************************************************************
                                        Withdraw
    ********************************************************************************/
    function testWithdraw() public {
        IBatchRouter.SwapPathExactAmountOut[] memory paths = _exactOutWrapUnwrapPath(
            2 * _wrapAmount,
            _wrapAmount,
            IERC20(address(waDAI)),
            dai,
            IERC20(address(waDAI))
        );

        uint256 lpUnderlyingBalanceBefore = dai.balanceOf(lp);
        uint256 lpWrappedBalanceBefore = IERC20(address(waDAI)).balanceOf(lp);

        vm.prank(lp);
        batchRouter.swapExactOut(paths, MAX_UINT256, false, bytes(""));

        uint256 lpUnderlyingBalanceAfter = dai.balanceOf(lp);
        uint256 lpWrappedBalanceAfter = IERC20(address(waDAI)).balanceOf(lp);

        assertEq(
            lpUnderlyingBalanceAfter,
            lpUnderlyingBalanceBefore + waDAI.previewWithdraw(_wrapAmount),
            "LP balance of underlying token is wrong"
        );
        assertEq(lpWrappedBalanceAfter, lpWrappedBalanceBefore - _wrapAmount, "LP balance of wrapped token is wrong");
    }

    function testWithdrawConsumesLessShares() public {
        IBatchRouter.SwapPathExactAmountOut[] memory paths = _exactOutWrapUnwrapPath(
            2 * _wrapAmount,
            _wrapAmount,
            IERC20(address(waDAI)),
            dai,
            IERC20(address(waDAI))
        );

        waDAI.setSharesToConsume(waDAI.previewWithdraw(_wrapAmount) - _ABOVE_CONVERT_ERROR);

        vm.prank(lp);
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.WrongWrappedAmount.selector, address(waDAI)));
        batchRouter.swapExactOut(paths, MAX_UINT256, false, bytes(""));
    }

    function testWithdrawConsumesMoreShares() public {
        IBatchRouter.SwapPathExactAmountOut[] memory paths = _exactOutWrapUnwrapPath(
            2 * _wrapAmount,
            _wrapAmount,
            IERC20(address(waDAI)),
            dai,
            IERC20(address(waDAI))
        );

        waDAI.setSharesToConsume(waDAI.previewWithdraw(_wrapAmount) + _ABOVE_CONVERT_ERROR);

        vm.startPrank(lp);
        // Call addLiquidity so vault has enough liquidity to cover extra wrapped amount
        router.addLiquidityToBuffer(IERC4626(address(waDAI)), _wrapAmount, _wrapAmount, lp);
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.WrongWrappedAmount.selector, address(waDAI)));
        batchRouter.swapExactOut(paths, MAX_UINT256, false, bytes(""));
        vm.stopPrank();
    }

    function testWithdrawReturnsMoreAssets() public {
        IBatchRouter.SwapPathExactAmountOut[] memory paths = _exactOutWrapUnwrapPath(
            2 * _wrapAmount,
            _wrapAmount,
            IERC20(address(waDAI)),
            dai,
            IERC20(address(waDAI))
        );

        waDAI.setAssetsToReturn(_wrapAmount + _ABOVE_CONVERT_ERROR);

        vm.prank(lp);
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.WrongUnderlyingAmount.selector, address(waDAI)));
        batchRouter.swapExactOut(paths, MAX_UINT256, false, bytes(""));
    }

    function testWithdrawReturnsLessAssets() public {
        IBatchRouter.SwapPathExactAmountOut[] memory paths = _exactOutWrapUnwrapPath(
            2 * _wrapAmount,
            _wrapAmount,
            IERC20(address(waDAI)),
            dai,
            IERC20(address(waDAI))
        );

        waDAI.setAssetsToReturn(_wrapAmount - _ABOVE_CONVERT_ERROR);

        vm.prank(lp);
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.WrongUnderlyingAmount.selector, address(waDAI)));
        batchRouter.swapExactOut(paths, MAX_UINT256, false, bytes(""));
    }

    /********************************************************************************
                                Disable Vault Buffers
    ********************************************************************************/
    // Make sure only authorized users can disable/enable vault buffers
    function testDisableVaultBufferAuthentication() public {
        vm.prank(alice);
        // Should revert, since alice has no rights to disable buffer
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        IVaultAdmin(address(vault)).pauseVaultBuffers();

        vm.prank(admin);
        // Should pass, since admin has access
        IVaultAdmin(address(vault)).pauseVaultBuffers();

        vm.prank(alice);
        // Should revert, since alice has no rights to enable buffer
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        IVaultAdmin(address(vault)).unpauseVaultBuffers();

        vm.prank(admin);
        // Should pass, since admin has access
        IVaultAdmin(address(vault)).unpauseVaultBuffers();
    }

    function testDisableVaultBuffer() public {
        vm.prank(lp);
        router.addLiquidityToBuffer(IERC4626(address(waDAI)), _wrapAmount, _wrapAmount, lp);

        vm.prank(admin);
        IVaultAdmin(address(vault)).pauseVaultBuffers();

        IBatchRouter.SwapPathExactAmountIn[] memory paths = _exactInWrapUnwrapPath(
            _wrapAmount,
            0,
            dai,
            IERC20(address(waDAI)),
            IERC20(address(waDAI))
        );

        // wrap/unwrap, add and remove liquidity should fail, since vault buffers are disabled
        vm.startPrank(lp);

        vm.expectRevert(IVaultErrors.VaultBuffersArePaused.selector);
        batchRouter.swapExactIn(paths, MAX_UINT256, false, bytes(""));

        vm.expectRevert(IVaultErrors.VaultBuffersArePaused.selector);
        router.addLiquidityToBuffer(IERC4626(address(waDAI)), _wrapAmount, _wrapAmount, lp);

        // remove liquidity is supposed to pass even with buffers paused, so revert is not expected
        router.removeLiquidityFromBuffer(IERC4626(address(waDAI)), _wrapAmount);

        vm.stopPrank();

        vm.prank(admin);
        IVaultAdmin(address(vault)).unpauseVaultBuffers();

        // deposit should pass, since vault buffers are enabled
        vm.prank(lp);
        batchRouter.swapExactIn(paths, MAX_UINT256, false, bytes(""));
    }

    /********************************************************************************
                          Add/Remove Liquidity from Buffers
    ********************************************************************************/

    function testAddLiquidityToBuffer() public {
        BufferAndLPBalances memory beforeBalances = _measureBuffer();

        vm.prank(lp);
        router.addLiquidityToBuffer(waDAI, _wrapAmount, _wrapAmount, lp);

        BufferAndLPBalances memory afterBalances = _measureBuffer();

        assertEq(afterBalances.buffer.dai, beforeBalances.buffer.dai + _wrapAmount, "Buffer DAI balance is wrong");
        assertEq(
            afterBalances.buffer.waDai,
            beforeBalances.buffer.waDai + _wrapAmount,
            "Buffer waDAI balance is wrong"
        );

        assertEq(afterBalances.vault.dai, beforeBalances.vault.dai + _wrapAmount, "Vault DAI balance is wrong");
        assertEq(afterBalances.vault.waDai, beforeBalances.vault.waDai + _wrapAmount, "Vault waDAI balance is wrong");

        assertEq(
            afterBalances.vaultReserves.dai,
            beforeBalances.vaultReserves.dai + _wrapAmount,
            "Vault Reserve DAI balance is wrong"
        );
        assertEq(
            afterBalances.vaultReserves.waDai,
            beforeBalances.vaultReserves.waDai + _wrapAmount,
            "Vault Reserve waDAI balance is wrong"
        );

        assertEq(afterBalances.lp.dai, beforeBalances.lp.dai - _wrapAmount, "LP DAI balance is wrong");
        assertEq(afterBalances.lp.waDai, beforeBalances.lp.waDai - _wrapAmount, "LP waDAI balance is wrong");
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

    function _measureBuffer() private returns (BufferAndLPBalances memory vars) {
        vars.lp.dai = dai.balanceOf(lp);
        vars.lp.waDai = waDAI.balanceOf(lp);

        (vars.buffer.dai, vars.buffer.waDai) = vault.getBufferBalance(IERC20(address(waDAI)));

        vars.vault.dai = dai.balanceOf(address(vault));
        vars.vault.waDai = waDAI.balanceOf(address(vault));

        vars.vaultReserves.dai = vault.getReservesOf(dai);
        vars.vaultReserves.waDai = vault.getReservesOf(IERC20(address(waDAI)));
    }

    function _exactInWrapUnwrapPath(
        uint256 exactAmountIn,
        uint256 minAmountOut,
        IERC20 tokenFrom,
        IERC20 tokenTo,
        IERC20 wrappedToken
    ) private pure returns (IBatchRouter.SwapPathExactAmountIn[] memory paths) {
        IBatchRouter.SwapPathStep[] memory steps = new IBatchRouter.SwapPathStep[](1);
        paths = new IBatchRouter.SwapPathExactAmountIn[](1);

        steps[0] = IBatchRouter.SwapPathStep({ pool: address(wrappedToken), tokenOut: tokenTo, isBuffer: true });

        paths[0] = IBatchRouter.SwapPathExactAmountIn({
            tokenIn: tokenFrom,
            steps: steps,
            exactAmountIn: exactAmountIn,
            minAmountOut: minAmountOut
        });
    }

    function _exactOutWrapUnwrapPath(
        uint256 maxAmountIn,
        uint256 exactAmountOut,
        IERC20 tokenFrom,
        IERC20 tokenTo,
        IERC20 wrappedToken
    ) private pure returns (IBatchRouter.SwapPathExactAmountOut[] memory paths) {
        IBatchRouter.SwapPathStep[] memory steps = new IBatchRouter.SwapPathStep[](1);
        paths = new IBatchRouter.SwapPathExactAmountOut[](1);

        steps[0] = IBatchRouter.SwapPathStep({ pool: address(wrappedToken), tokenOut: tokenTo, isBuffer: true });

        paths[0] = IBatchRouter.SwapPathExactAmountOut({
            tokenIn: tokenFrom,
            steps: steps,
            maxAmountIn: maxAmountIn,
            exactAmountOut: exactAmountOut
        });
    }
}
