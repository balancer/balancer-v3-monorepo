// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract PoolDevFees is BaseVaultTest {
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
        vm.prank(lp);
        vault.setPoolDevFeePercentage(address(pool), 1e17); // 10%

        assertEq(vault.getPoolDevFee(address(pool), usdc), 0);
        assertEq(vault.getPoolDevFee(address(pool), dai), 0);
        swapSingleTokenExactIn(usdc, dai, defaultAmount / 10);
        assertEq(vault.getPoolDevFee(address(pool), usdc), 0);
        assertEq(vault.getPoolDevFee(address(pool), dai), 0);
    }

    function testCollectPoolDevFee() public {}

    function testCannotCollectIfNotPoolDev() public {}

    function swapSingleTokenExactIn(IERC20 tokenIn, IERC20 tokenOut, uint256 amountIn) public {
        vm.prank(alice);
        router.swapSingleTokenExactIn(
            address(pool),
            tokenIn,
            tokenOut,
            amountIn,
            amountIn,
            MAX_UINT256,
            false,
            bytes("")
        );
    }
}
