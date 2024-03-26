// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

contract PoolDevFees is BaseVaultTest {
    using FixedPoint for uint256;

    function setUp() public override {
        BaseVaultTest.setUp();
    }

    function testPoolDevWasSet() public {
        assertEq(vault.getPoolDev(pool), address(lp));
    }

    function testSwapWithoutDevFee() public {
        assertEq(vault.getPoolDevFee(address(pool), usdc), 0);
        assertEq(vault.getPoolDevFee(address(pool), dai), 0);
        swapSingleTokenExactIn(usdc, dai, defaultAmount / 10);
        assertEq(vault.getPoolDevFee(address(pool), usdc), 0);
        assertEq(vault.getPoolDevFee(address(pool), dai), 0);
    }

    function testSwapWithDevFee() public {
        uint256 amountToSwap = defaultAmount / 10;
        uint256 swapFeePercentage = 1e17; //10%
        uint256 poolDevFeePercentage = 1e17; //10%
        uint256 poolDevFeeDai = amountToSwap.mulDown(swapFeePercentage).mulDown(poolDevFeePercentage);

        setSwapFeePercentage(swapFeePercentage);
        vm.prank(lp);
        vault.setPoolDevFeePercentage(address(pool), poolDevFeePercentage);

        assertEq(vault.getPoolDevFee(address(pool), usdc), 0);
        assertEq(vault.getPoolDevFee(address(pool), dai), 0);
        swapSingleTokenExactIn(usdc, dai, amountToSwap);
        assertEq(vault.getPoolDevFee(address(pool), usdc), 0);
        assertEq(vault.getPoolDevFee(address(pool), dai), poolDevFeeDai);
    }

    function testCollectPoolDevFee() public {
        uint256 amountToSwap = defaultAmount / 10;
        uint256 swapFeePercentage = 1e17; //10%
        uint256 poolDevFeePercentage = 1e17; //10%
        uint256 poolDevFeeDai = amountToSwap.mulDown(swapFeePercentage).mulDown(poolDevFeePercentage);

        uint256 lpBalanceDaiBefore = dai.balanceOf(address(lp));

        setSwapFeePercentage(swapFeePercentage);
        vm.prank(lp);
        vault.setPoolDevFeePercentage(address(pool), poolDevFeePercentage);

        assertEq(vault.getPoolDevFee(address(pool), usdc), 0);
        assertEq(vault.getPoolDevFee(address(pool), dai), 0);
        swapSingleTokenExactIn(usdc, dai, amountToSwap);
        assertEq(vault.getPoolDevFee(address(pool), usdc), 0);
        assertEq(vault.getPoolDevFee(address(pool), dai), poolDevFeeDai);

        vm.prank(lp);
        vault.collectPoolDevFees(address(pool));
        assertEq(vault.getPoolDevFee(address(pool), dai), 0);

        uint256 lpBalanceDaiAfter = dai.balanceOf(address(lp));
        assertEq(lpBalanceDaiAfter - lpBalanceDaiBefore, poolDevFeeDai);
    }

    function testCannotCollectIfNotPoolDev() public {
        uint256 amountToSwap = defaultAmount / 10;
        uint256 swapFeePercentage = 1e17; //10%
        uint256 poolDevFeePercentage = 1e17; //10%

        setSwapFeePercentage(swapFeePercentage);
        vm.prank(lp);
        vault.setPoolDevFeePercentage(address(pool), poolDevFeePercentage);

        swapSingleTokenExactIn(usdc, dai, amountToSwap);

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.SenderIsNotPoolDev.selector, address(pool)));
        vault.collectPoolDevFees(address(pool));
    }

    function swapSingleTokenExactIn(IERC20 tokenIn, IERC20 tokenOut, uint256 amountIn) public {
        vm.prank(alice);
        router.swapSingleTokenExactIn(
            address(pool),
            tokenIn,
            tokenOut,
            amountIn,
            0,
            MAX_UINT256,
            false,
            bytes("")
        );
    }
}
