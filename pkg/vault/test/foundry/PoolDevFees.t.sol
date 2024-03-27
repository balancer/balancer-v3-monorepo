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

    function testPoolCreatorWasSet() public {
        assertEq(vault.getPoolCreator(pool), address(lp));
    }

    function testSwapWithoutFees() public {
        uint256 amountToSwap = defaultAmount / 10;
        _swapExactInWithFees(usdc, dai, amountToSwap, 0, 0, 0);
    }

    function testSwapWithCreatorFee() public {
        uint256 amountToSwap = defaultAmount / 10;
        uint256 swapFeePercentage = 1e17; //10%
        uint64 protocolFeePercentage = 5e17; //50%
        uint256 poolCreatorFeePercentage = 1e17; //10%

        _swapExactInWithFees(
            usdc,
            dai,
            amountToSwap,
            swapFeePercentage,
            protocolFeePercentage,
            poolCreatorFeePercentage
        );
    }

    function testCollectPoolCreatorFee() public {
        uint256 amountToSwap = defaultAmount / 10;
        uint256 swapFeePercentage = 1e17; //10%
        uint64 protocolFeePercentage = 5e17; //50%
        uint256 poolCreatorFeePercentage = 1e17; //10%

        uint256 lpBalanceDaiBefore = dai.balanceOf(address(lp));

        uint256 chargedCreatorFees = _swapExactInWithFees(
            usdc,
            dai,
            amountToSwap,
            swapFeePercentage,
            protocolFeePercentage,
            poolCreatorFeePercentage
        );

        vault.collectPoolCreatorFees(address(pool));
        assertEq(
            vault.getPoolCreatorFee(address(pool), dai),
            0,
            "creatorFees in the vault should be 0 after fee collected"
        );

        uint256 lpBalanceDaiAfter = dai.balanceOf(address(lp));
        assertEq(
            lpBalanceDaiAfter - lpBalanceDaiBefore,
            chargedCreatorFees,
            "LP (poolCreator) tokenOut balance should increase by chargedCreatorFees after fee collected"
        );
    }

    /// @dev Avoid "stack too deep"
    struct SwapTestLocals {
        uint256 totalFees;
        uint256 protocolFees;
        uint256 aliceTokenInBalanceBefore;
        uint256 aliceTokenOutBalanceBefore;
        uint256 protocolTokenInFeesBefore;
        uint256 protocolTokenOutFeesBefore;
        uint256 creatorTokenInFeesBefore;
        uint256 creatorTokenOutFeesBefore;
    }

    function _swapExactInWithFees(
        IERC20 tokenIn,
        IERC20 tokenOut,
        uint256 amountIn,
        uint256 swapFeePercentage,
        uint64 protocolFeePercentage,
        uint256 creatorFeePercentage
    ) private returns (uint256 chargedCreatorFee) {
        SwapTestLocals memory vars;

        setProtocolSwapFeePercentage(protocolFeePercentage);
        setSwapFeePercentage(swapFeePercentage);
        vm.prank(lp);
        vault.setPoolCreatorFeePercentage(address(pool), creatorFeePercentage);

        // totalFees = amountIn * swapFee%
        vars.totalFees = amountIn.mulDown(swapFeePercentage);

        // protocolFees = totalFees * protocolFee%
        vars.protocolFees = vars.totalFees.mulDown(protocolFeePercentage);

        // creatorAndLPFees = totalFees - protocolFees
        // creatorFees = creatorAndLPFees * creatorFee%
        chargedCreatorFee = (vars.totalFees - vars.protocolFees).mulDown(creatorFeePercentage);

        // Get swap user (alice) balances before transfer
        vars.aliceTokenInBalanceBefore = tokenIn.balanceOf(address(alice));
        vars.aliceTokenOutBalanceBefore = tokenOut.balanceOf(address(alice));

        // Get protocol fees before transfer
        vars.protocolTokenInFeesBefore = vault.getProtocolFees(address(tokenIn));
        vars.protocolTokenOutFeesBefore = vault.getProtocolFees(address(tokenOut));

        // Get creator fees before transfer
        vars.creatorTokenInFeesBefore = vault.getPoolCreatorFee(address(pool), tokenIn);
        vars.creatorTokenOutFeesBefore = vault.getPoolCreatorFee(address(pool), tokenOut);

        vm.prank(alice);
        router.swapSingleTokenExactIn(address(pool), tokenIn, tokenOut, amountIn, 0, MAX_UINT256, false, bytes(""));

        // Check swap user (alice) after transfer
        assertEq(
            tokenIn.balanceOf(address(alice)),
            vars.aliceTokenInBalanceBefore - amountIn,
            "Alice should pay amountIn after swap"
        );
        // amountIn = amountOut, since the rate is 1 and test pool is linear.
        assertEq(
            tokenOut.balanceOf(address(alice)),
            vars.aliceTokenOutBalanceBefore + amountIn - vars.totalFees,
            "Alice should receive amountOut - fees after swap"
        );

        // Check protocol fees after transfer
        assertEq(
            vault.getProtocolFees(address(tokenIn)),
            vars.protocolTokenInFeesBefore,
            "tokenIn protocol fees should not change"
        );
        assertEq(
            vault.getProtocolFees(address(tokenOut)),
            vars.protocolTokenOutFeesBefore + vars.protocolFees,
            "tokenOut protocol fees should increase by vars.protocolFees after swap"
        );

        // Check creator fees after balance
        assertEq(
            vault.getPoolCreatorFee(address(pool), tokenIn),
            vars.creatorTokenInFeesBefore,
            "tokenIn creator fees should not change"
        );
        assertEq(
            vault.getPoolCreatorFee(address(pool), tokenOut),
            vars.creatorTokenOutFeesBefore + chargedCreatorFee,
            "tokenOut creator fees should increase by chargedCreatorFee after swap"
        );
    }
}
