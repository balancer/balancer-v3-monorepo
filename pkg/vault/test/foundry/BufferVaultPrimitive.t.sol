// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IBatchRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IBatchRouter.sol";

import {
ERC4626TestToken
} from "@balancer-labs/v3-solidity-utils/contracts/test/ERC4626TestToken.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract BufferVaultPrimitiveTest is BaseVaultTest {
    ERC4626TestToken internal waDAI;
    ERC4626TestToken internal waUSDC;

    uint256 userAmount = 10e6 * 1e18;
    uint256 wrapAmount = userAmount / 100;

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
        dai.mint(address(lp), userAmount);
        // Minting wrong token to wrapped token contract, to test changing the asset
        dai.mint(address(waUSDC), userAmount);
        dai.approve(address(waDAI), userAmount);
        waDAI.deposit(userAmount, address(lp));

        usdc.mint(address(lp), userAmount);
        // Minting wrong token to wrapped token contract, to test changing the asset
        usdc.mint(address(waDAI), userAmount);
        usdc.approve(address(waUSDC), userAmount);
        waUSDC.deposit(userAmount, address(lp));

        waDAI.approve(address(permit2), MAX_UINT256);
        permit2.approve(address(waDAI), address(router), type(uint160).max, type(uint48).max);
        permit2.approve(address(waDAI), address(batchRouter), type(uint160).max, type(uint48).max);
        waUSDC.approve(address(permit2), MAX_UINT256);
        permit2.approve(address(waUSDC), address(router), type(uint160).max, type(uint48).max);
        permit2.approve(address(waUSDC), address(batchRouter), type(uint160).max, type(uint48).max);
        vm.stopPrank();
    }

    function testChangeAssetOfWrappedToken() public {
        // Change Asset to wrong underlying
        waDAI.setAsset(usdc);

        // Wrap token should pass, since there's no liquidity in the buffer
        IBatchRouter.SwapPathExactAmountIn[] memory paths = _exactInWrapPath(
            wrapAmount,
            0,
            usdc,
            IERC20(address(waDAI))
        );

        vm.prank(lp);
        batchRouter.swapExactIn(paths, MAX_UINT256, false, bytes(""));

        // Change Asset to correct asset
        waDAI.setAsset(dai);

        // Add Liquidity with the right asset
        vm.prank(lp);
        router.addLiquidityBuffer(IERC4626(address(waDAI)), wrapAmount, wrapAmount, address(lp));

        // Change Asset to the wrong asset
        waDAI.setAsset(usdc);

        // Wrap token should fail, since buffer has liquidity
        vm.prank(lp);
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.WrongWrappedTokenAsset.selector, address(waDAI)));
        batchRouter.swapExactIn(paths, MAX_UINT256, false, bytes(""));
    }

    // Deposit returns wrong shares
    function testDepositReturnsWrongShares() public {
        IBatchRouter.SwapPathExactAmountIn[] memory paths = _exactInWrapPath(
            wrapAmount,
            0,
            dai,
            IERC20(address(waDAI))
        );

        waDAI.setSharesToReturn(1);

        vm.prank(lp);
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.WrongWrappedAmountOnDeposit.selector, address(waDAI)));
        batchRouter.swapExactIn(paths, MAX_UINT256, false, bytes(""));
    }

    // Deposit consumes wrong assets

// Mint returns wrong shares or assets
// Redeem returns wrong shares or assets
// Withdraw returns wrong shares or assets
// Disable Vault Buffers

    function _exactInWrapPath(
        uint256 exactAmountIn,
        uint256 minAmountOut,
        IERC20 baseToken,
        IERC20 wrappedToken
    ) private view returns (IBatchRouter.SwapPathExactAmountIn[] memory paths) {
        IBatchRouter.SwapPathStep[] memory steps = new IBatchRouter.SwapPathStep[](1);
        paths = new IBatchRouter.SwapPathExactAmountIn[](1);

        steps[0] = IBatchRouter.SwapPathStep({ pool: address(wrappedToken), tokenOut: wrappedToken, isBuffer: true });

        paths[0] = IBatchRouter.SwapPathExactAmountIn({
            tokenIn: baseToken,
            steps: steps,
            exactAmountIn: exactAmountIn,
            minAmountOut: minAmountOut
        });
    }
}
