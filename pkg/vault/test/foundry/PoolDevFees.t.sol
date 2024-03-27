// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

contract poolCreatorFees is BaseVaultTest {
    using FixedPoint for uint256;

    function setUp() public override {
        BaseVaultTest.setUp();
    }

    function testpoolCreatorWasSet() public {
        assertEq(vault.getpoolCreator(pool), address(lp));
    }

    function testSwapWithoutDevFee() public {
        assertEq(vault.getpoolCreatorFee(address(pool), usdc), 0);
        assertEq(vault.getpoolCreatorFee(address(pool), dai), 0);
        swapSingleTokenExactIn(usdc, dai, defaultAmount / 10);
        assertEq(vault.getpoolCreatorFee(address(pool), usdc), 0);
        assertEq(vault.getpoolCreatorFee(address(pool), dai), 0);
    }

    function testSwapWithDevFee() public {
        uint256 amountToSwap = defaultAmount / 10;
        uint256 swapFeePercentage = 1e17; //10%
        uint256 poolCreatorFeePercentage = 1e17; //10%
        uint256 poolCreatorFeeDai = amountToSwap.mulDown(swapFeePercentage).mulDown(poolCreatorFeePercentage);

        setSwapFeePercentage(swapFeePercentage);
        vm.prank(lp);
        vault.setpoolCreatorFeePercentage(address(pool), poolCreatorFeePercentage);

        assertEq(vault.getpoolCreatorFee(address(pool), usdc), 0);
        assertEq(vault.getpoolCreatorFee(address(pool), dai), 0);
        swapSingleTokenExactIn(usdc, dai, amountToSwap);
        assertEq(vault.getpoolCreatorFee(address(pool), usdc), 0);
        assertEq(vault.getpoolCreatorFee(address(pool), dai), poolCreatorFeeDai);
    }

    function testCollectpoolCreatorFee() public {
        uint256 amountToSwap = defaultAmount / 10;
        uint256 swapFeePercentage = 1e17; //10%
        uint256 poolCreatorFeePercentage = 1e17; //10%
        uint256 poolCreatorFeeDai = amountToSwap.mulDown(swapFeePercentage).mulDown(poolCreatorFeePercentage);

        uint256 lpBalanceDaiBefore = dai.balanceOf(address(lp));

        setSwapFeePercentage(swapFeePercentage);
        vm.prank(lp);
        vault.setpoolCreatorFeePercentage(address(pool), poolCreatorFeePercentage);

        assertEq(vault.getpoolCreatorFee(address(pool), usdc), 0);
        assertEq(vault.getpoolCreatorFee(address(pool), dai), 0);
        swapSingleTokenExactIn(usdc, dai, amountToSwap);
        assertEq(vault.getpoolCreatorFee(address(pool), usdc), 0);
        assertEq(vault.getpoolCreatorFee(address(pool), dai), poolCreatorFeeDai);

        vm.prank(lp);
        vault.collectpoolCreatorFees(address(pool));
        assertEq(vault.getpoolCreatorFee(address(pool), dai), 0);

        uint256 lpBalanceDaiAfter = dai.balanceOf(address(lp));
        assertEq(lpBalanceDaiAfter - lpBalanceDaiBefore, poolCreatorFeeDai);
    }

    function testCannotCollectIfNotpoolCreator() public {
        uint256 amountToSwap = defaultAmount / 10;
        uint256 swapFeePercentage = 1e17; //10%
        uint256 poolCreatorFeePercentage = 1e17; //10%

        setSwapFeePercentage(swapFeePercentage);
        vm.prank(lp);
        vault.setpoolCreatorFeePercentage(address(pool), poolCreatorFeePercentage);

        swapSingleTokenExactIn(usdc, dai, amountToSwap);

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.SenderIsNotpoolCreator.selector, address(pool)));
        vault.collectpoolCreatorFees(address(pool));
    }

    function swapSingleTokenExactIn(IERC20 tokenIn, IERC20 tokenOut, uint256 amountIn) public {
        vm.prank(alice);
        router.swapSingleTokenExactIn(address(pool), tokenIn, tokenOut, amountIn, 0, MAX_UINT256, false, bytes(""));
    }
}
