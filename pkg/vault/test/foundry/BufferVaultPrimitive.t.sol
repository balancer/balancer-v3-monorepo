// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IBatchRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IBatchRouter.sol";

import { ERC4626TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC4626TestToken.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract BufferVaultPrimitiveTest is BaseVaultTest {
    ERC4626TestToken internal waDAI;
    ERC4626TestToken internal waUSDC;

    uint256 private _userAmount = 10e6 * 1e18;
    uint256 private _wrapAmount = _userAmount / 100;

    function setUp() public virtual override {
        BaseVaultTest.setUp();

        waDAI = new ERC4626TestToken(dai, "Wrapped aDAI", "waDAI", 18);
        vm.label(address(waDAI), "waDAI");

        // "USDC" is deliberately 18 decimals to test one thing at a time.
        waUSDC = new ERC4626TestToken(usdc, "Wrapped aUSDC", "waUSDC", 18);
        vm.label(address(waUSDC), "waUSDC");

        initializeLp();
    }

    function initializeLp() private {
        // Create and fund buffer pools
        vm.startPrank(lp);

        dai.mint(address(lp), _userAmount);
        dai.approve(address(waDAI), _userAmount);
        waDAI.deposit(_userAmount, address(lp));

        usdc.mint(address(lp), _userAmount);
        usdc.approve(address(waUSDC), _userAmount);
        waUSDC.deposit(_userAmount, address(lp));

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
        router.addLiquidityBuffer(IERC4626(address(waDAI)), _wrapAmount, _wrapAmount, address(lp));

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

    function testDepositReturnsWrongShares() public {
        IBatchRouter.SwapPathExactAmountIn[] memory paths = _exactInWrapUnwrapPath(
            _wrapAmount,
            0,
            dai,
            IERC20(address(waDAI)),
            IERC20(address(waDAI))
        );

        waDAI.setSharesToReturn(1);

        vm.prank(lp);
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.WrongWrappedAmountOnDeposit.selector, address(waDAI)));
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

        waDAI.setAssetsToConsume(_wrapAmount - 1);

        vm.prank(lp);
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.WrongBaseAmountOnDeposit.selector, address(waDAI)));
        batchRouter.swapExactIn(paths, MAX_UINT256, false, bytes(""));
    }

    function testDepositConsumesMoreAssets() public {
        uint256 changedWrapAmount = _wrapAmount + 1;

        IBatchRouter.SwapPathExactAmountIn[] memory paths = _exactInWrapUnwrapPath(
            _wrapAmount,
            0,
            dai,
            IERC20(address(waDAI)),
            IERC20(address(waDAI))
        );

        waDAI.setAssetsToConsume(changedWrapAmount);

        vm.prank(lp);
        // When the assets amount is higher than predicted, vault did not give allowance to make the transfer
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector,
                address(waDAI),
                _wrapAmount,
                changedWrapAmount
            )
        );
        batchRouter.swapExactIn(paths, MAX_UINT256, false, bytes(""));
    }

    /********************************************************************************
                                        Mint
    ********************************************************************************/

    function testMintReturnsLessShares() public {
        IBatchRouter.SwapPathExactAmountOut[] memory paths = _exactOutWrapUnwrapPath(
            2 * _wrapAmount,
            _wrapAmount,
            dai,
            IERC20(address(waDAI)),
            IERC20(address(waDAI))
        );

        waDAI.setSharesToReturn(_wrapAmount - 1);

        vm.prank(lp);
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.WrongWrappedAmountOnDeposit.selector, address(waDAI)));
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

        waDAI.setSharesToReturn(_wrapAmount + 1);

        vm.prank(lp);
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.WrongWrappedAmountOnDeposit.selector, address(waDAI)));
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

        waDAI.setAssetsToConsume(_wrapAmount - 1);

        vm.prank(lp);
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.WrongBaseAmountOnDeposit.selector, address(waDAI)));
        batchRouter.swapExactOut(paths, MAX_UINT256, false, bytes(""));
    }

    function testMintConsumesMoreAssets() public {
        uint256 changedWrapAmount = _wrapAmount + 1;

        IBatchRouter.SwapPathExactAmountOut[] memory paths = _exactOutWrapUnwrapPath(
            2 * _wrapAmount,
            _wrapAmount,
            dai,
            IERC20(address(waDAI)),
            IERC20(address(waDAI))
        );

        waDAI.setAssetsToConsume(changedWrapAmount);

        vm.prank(lp);
        // When the assets amount is higher than predicted, vault did not give allowance to make the transfer
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector,
                address(waDAI),
                _wrapAmount,
                changedWrapAmount
            )
        );
        batchRouter.swapExactOut(paths, MAX_UINT256, false, bytes(""));
    }

    /********************************************************************************
                                        Redeem
    ********************************************************************************/
    function testRedeemConsumesLessShares() public {
        IBatchRouter.SwapPathExactAmountIn[] memory paths = _exactInWrapUnwrapPath(
            _wrapAmount,
            0,
            IERC20(address(waDAI)),
            dai,
            IERC20(address(waDAI))
        );

        waDAI.setSharesToConsume(_wrapAmount - 1);

        vm.prank(lp);
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.WrongWrappedAmountOnWithdraw.selector, address(waDAI)));
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

        waDAI.setSharesToConsume(_wrapAmount + 1);

        vm.startPrank(lp);
        // Call addLiquidity so vault has enough liquidity to cover extra wrapped amount
        router.addLiquidityBuffer(IERC4626(address(waDAI)), _wrapAmount, _wrapAmount, address(lp));
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.WrongWrappedAmountOnWithdraw.selector, address(waDAI)));
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

        waDAI.setAssetsToReturn(waDAI.previewRedeem(_wrapAmount) + 1);

        vm.prank(lp);
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.WrongBaseAmountOnWithdraw.selector, address(waDAI)));
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

        waDAI.setAssetsToReturn(waDAI.previewRedeem(_wrapAmount) - 1);

        vm.prank(lp);
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.WrongBaseAmountOnWithdraw.selector, address(waDAI)));
        batchRouter.swapExactIn(paths, MAX_UINT256, false, bytes(""));
    }

    /********************************************************************************
                                        Withdraw
    ********************************************************************************/

    function testWithdrawConsumesLessShares() public {
        IBatchRouter.SwapPathExactAmountOut[] memory paths = _exactOutWrapUnwrapPath(
            2 * _wrapAmount,
            _wrapAmount,
            IERC20(address(waDAI)),
            dai,
            IERC20(address(waDAI))
        );

        waDAI.setSharesToConsume(waDAI.previewWithdraw(_wrapAmount) - 1);

        vm.prank(lp);
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.WrongWrappedAmountOnWithdraw.selector, address(waDAI)));
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

        waDAI.setSharesToConsume(waDAI.previewWithdraw(_wrapAmount) + 1);

        vm.prank(lp);
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.WrongWrappedAmountOnWithdraw.selector, address(waDAI)));
        batchRouter.swapExactOut(paths, MAX_UINT256, false, bytes(""));
    }

    function testWithdrawReturnsMoreAssets() public {
        IBatchRouter.SwapPathExactAmountOut[] memory paths = _exactOutWrapUnwrapPath(
            2 * _wrapAmount,
            _wrapAmount,
            IERC20(address(waDAI)),
            dai,
            IERC20(address(waDAI))
        );

        waDAI.setAssetsToReturn(_wrapAmount + 1);

        vm.prank(lp);
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.WrongBaseAmountOnWithdraw.selector, address(waDAI)));
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

        waDAI.setAssetsToReturn(_wrapAmount - 1);

        vm.prank(lp);
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.WrongBaseAmountOnWithdraw.selector, address(waDAI)));
        batchRouter.swapExactOut(paths, MAX_UINT256, false, bytes(""));
    }

    // Disable Vault Buffers

    function _exactInWrapUnwrapPath(
        uint256 exactAmountIn,
        uint256 minAmountOut,
        IERC20 tokenFrom,
        IERC20 tokenTo,
        IERC20 wrappedToken
    ) private view returns (IBatchRouter.SwapPathExactAmountIn[] memory paths) {
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
    ) private view returns (IBatchRouter.SwapPathExactAmountOut[] memory paths) {
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
