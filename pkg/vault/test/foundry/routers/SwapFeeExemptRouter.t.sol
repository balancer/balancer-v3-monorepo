// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IPermit2 } from "permit2/src/interfaces/IPermit2.sol";

import { ISwapFeeExemptRouter } from "@balancer-labs/v3-interfaces/contracts/vault/ISwapFeeExemptRouter.sol";
import { IWETH } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/misc/IWETH.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { SwapKind } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { SwapFeeExemptRouter } from "../../../contracts/routers/SwapFeeExemptRouter.sol";
import { PoolMock } from "../../../contracts/test/PoolMock.sol";
import { PoolFactoryMock, BaseVaultTest } from "../utils/BaseVaultTest.sol";

contract SwapFeeExemptRouterTest is BaseVaultTest {
    using CastingHelpers for address[];
    using ArrayHelpers for *;
    using FixedPoint for *;

    SwapFeeExemptRouter internal swapRouter;
    address internal testPool;

    uint256 internal usdcAmountIn = 1e3 * 1e6; // USDC has 6 decimals  
    uint256 internal daiAmountOut = 1e6; // Request very small amount to ensure sufficient balance

    address internal testUser;

    function setUp() public virtual override {
        super.setUp();

        testUser = makeAddr("testUser");

        // Create router
        swapRouter = new SwapFeeExemptRouter(vault, weth, permit2, "SwapFeeExemptRouter v1.0.0");

        // Use the existing pool created by BaseVaultTest instead of creating our own
        testPool = pool;

        // Give test user some tokens
        dai.mint(testUser, 10000e18);
        usdc.mint(testUser, 10000e6);
    }

    /*//////////////////////////////////////////////////////////////
                            BASIC SWAP TESTS
    //////////////////////////////////////////////////////////////*/

    function testSwapExactInBasic() public {
        uint256 exactAmountIn = usdcAmountIn;

        // Test user approves router to spend USDC
        vm.startPrank(testUser);
        usdc.approve(address(permit2), type(uint256).max);
        permit2.approve(address(usdc), address(swapRouter), type(uint160).max, type(uint48).max);

        uint256 userUsdcBefore = usdc.balanceOf(testUser);
        uint256 userDaiBefore = dai.balanceOf(testUser);

        // Execute swap: USDC -> DAI
        uint256 actualAmountOut = swapRouter.swapSingleTokenExactIn(
            testPool,
            usdc,
            dai, 
            exactAmountIn,
            0, // minAmountOut
            block.timestamp + 3600, // deadline
            false, // wethIsEth
            ""  // userData
        );

        // Check balances changed correctly  
        assertEq(usdc.balanceOf(testUser), userUsdcBefore - exactAmountIn, "User USDC balance");
        assertEq(dai.balanceOf(testUser), userDaiBefore + actualAmountOut, "User DAI balance");
        assertGt(actualAmountOut, 0, "Should receive DAI output");

        vm.stopPrank();
    }

    function testSwapExactOutBasic() public {
        uint256 exactAmountOut = daiAmountOut;

        // Test user approves router to spend USDC
        vm.startPrank(testUser);
        usdc.approve(address(permit2), type(uint256).max);
        permit2.approve(address(usdc), address(swapRouter), type(uint160).max, type(uint48).max);

        uint256 userUsdcBefore = usdc.balanceOf(testUser);
        uint256 userDaiBefore = dai.balanceOf(testUser);

        // Execute swap: USDC -> DAI (exact out)
        uint256 actualAmountIn = swapRouter.swapSingleTokenExactOut(
            testPool,
            usdc,
            dai,
            exactAmountOut,
            type(uint256).max, // maxAmountIn
            block.timestamp + 3600, // deadline
            false, // wethIsEth
            ""  // userData
        );

        // Check balances changed correctly
        assertEq(usdc.balanceOf(testUser), userUsdcBefore - actualAmountIn, "User USDC balance");
        assertEq(dai.balanceOf(testUser), userDaiBefore + exactAmountOut, "User DAI balance");
        assertGt(actualAmountIn, 0, "Should spend USDC input");

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            MULTIPLE USERS TEST
    //////////////////////////////////////////////////////////////*/

    function testMultipleUsersCanSwap() public {
        uint256 exactAmountIn = 500e6; // 500 USDC

        address secondUser = makeAddr("secondUser");
        dai.mint(secondUser, 10000e18);
        usdc.mint(secondUser, 10000e6);

        // Both users approve router
        vm.startPrank(testUser);
        usdc.approve(address(permit2), type(uint256).max);
        permit2.approve(address(usdc), address(swapRouter), type(uint160).max, type(uint48).max);
        vm.stopPrank();

        vm.startPrank(secondUser);
        usdc.approve(address(permit2), type(uint256).max);
        permit2.approve(address(usdc), address(swapRouter), type(uint160).max, type(uint48).max);
        vm.stopPrank();

        // First user swaps
        vm.startPrank(testUser);
        uint256 firstAmountOut = swapRouter.swapSingleTokenExactIn(
            testPool,
            usdc,
            dai,
            exactAmountIn,
            0,
            block.timestamp + 3600,
            false,
            ""
        );
        vm.stopPrank();

        // Second user swaps  
        vm.startPrank(secondUser);
        uint256 secondAmountOut = swapRouter.swapSingleTokenExactIn(
            testPool,
            usdc,
            dai,
            exactAmountIn,
            0,
            block.timestamp + 3600,
            false,
            ""
        );
        vm.stopPrank();

        // Both should have received DAI
        assertGt(firstAmountOut, 0, "First user should receive DAI");
        assertGt(secondAmountOut, 0, "Second user should receive DAI");
    }
}