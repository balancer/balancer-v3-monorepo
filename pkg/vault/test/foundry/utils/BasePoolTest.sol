// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";
import { IBasePoolFactory } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePoolFactory.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { IVaultAdmin } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultAdmin.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { Vault } from "@balancer-labs/v3-vault/contracts/Vault.sol";

import { InputHelpersMock } from "../../../contracts/test/InputHelpersMock.sol";

import { BaseVaultTest } from "vault/test/foundry/utils/BaseVaultTest.sol";

abstract contract BasePoolTest is BaseVaultTest {
    using FixedPoint for uint256;

    uint256 public constant DELTA = 1e9;

    IERC20[] internal poolTokens;
    uint256[] internal tokenAmounts;

    uint256 internal tokenIndexIn = 0;
    uint256 internal tokenIndexOut = 1;
    uint256 internal tokenAmountIn = 1e18;
    uint256 internal tokenAmountOut = 1e18;

    uint256 internal expectedAddLiquidityBptAmountOut = 1e3 * 1e18;
    bool internal isTestSwapFeeEnabled = true;

    uint256 internal bptAmountOut;

    uint256 internal poolMinSwapFeePercentage;
    uint256 internal poolMaxSwapFeePercentage;

    InputHelpersMock public immutable inputHelpersMock = new InputHelpersMock();

    function setUp() public virtual override {
        BaseVaultTest.setUp();

        require(poolTokens.length >= 2, "Minimum 2 tokens required (poolTokens)");
        require(poolTokens.length == tokenAmounts.length, "poolTokens and tokenAmounts length mismatch");

        poolMinSwapFeePercentage = 0;
        poolMaxSwapFeePercentage = 1e18;
    }

    function testPoolAddress() public view {
        address calculatedPoolAddress = IBasePoolFactory(poolFactory).getDeploymentAddress(poolArguments, ZERO_BYTES32);
        assertEq(pool, calculatedPoolAddress, "Pool address mismatch");
    }

    function testPoolPausedState() public view {
        (bool paused, uint256 pauseWindow, uint256 bufferPeriod, address pauseManager) = vault.getPoolPausedState(pool);

        assertFalse(paused, "Vault should not be paused initially");
        assertApproxEqAbs(pauseWindow, START_TIMESTAMP + 365 days, 1, "Pause window period mismatch");
        assertApproxEqAbs(bufferPeriod, START_TIMESTAMP + 365 days + 30 days, 1, "Pause buffer period mismatch");
        assertEq(pauseManager, address(0), "Pause manager should be 0");
    }

    function testInitialize() public view {
        (, , uint256[] memory balances, ) = vault.getPoolTokenInfo(address(pool));

        for (uint256 i = 0; i < poolTokens.length; ++i) {
            // Tokens are transferred from lp.
            assertEq(
                defaultAccountBalance() - poolTokens[i].balanceOf(lp),
                tokenAmounts[i],
                string.concat("LP: Wrong balance for ", Strings.toString(i))
            );

            // Tokens are stored in the Vault.
            assertEq(
                poolTokens[i].balanceOf(address(vault)),
                tokenAmounts[i],
                string.concat("LP: Vault balance for ", Strings.toString(i))
            );

            // Tokens are deposited to the pool.
            assertEq(
                balances[i],
                tokenAmounts[i],
                string.concat("Pool: Wrong token balance for ", Strings.toString(i))
            );
        }

        // Should mint the correct amount of BPT poolTokens, within a maximum error of DELTA due to precision loss.
        assertApproxEqAbs(IERC20(pool).balanceOf(lp), bptAmountOut, DELTA, "LP: Wrong bptAmountOut");
        assertApproxEqAbs(bptAmountOut, expectedAddLiquidityBptAmountOut, DELTA, "Wrong bptAmountOut");
    }

    function testAddLiquidity() public {
        vm.prank(bob);
        bptAmountOut = router.addLiquidityUnbalanced(pool, tokenAmounts, tokenAmountIn - DELTA, false, bytes(""));

        (, , uint256[] memory balances, ) = vault.getPoolTokenInfo(address(pool));

        for (uint256 i = 0; i < poolTokens.length; ++i) {
            // Tokens are transferred from Bob.
            assertEq(
                defaultAccountBalance() - poolTokens[i].balanceOf(bob),
                tokenAmounts[i],
                string.concat("LP: Wrong token balance for ", Strings.toString(i))
            );

            // Tokens are stored in the Vault.
            assertEq(
                poolTokens[i].balanceOf(address(vault)),
                tokenAmounts[i] * 2,
                string.concat("Vault: Wrong token balance for ", Strings.toString(i))
            );

            assertEq(
                balances[i],
                tokenAmounts[i] * 2,
                string.concat("Pool: Wrong token balance for ", Strings.toString(i))
            );
        }

        // Should mint the correct amount of BPT poolTokens, within a maximum error of DELTA due to precision loss.
        assertApproxEqAbs(IERC20(pool).balanceOf(bob), bptAmountOut, DELTA, "LP: Wrong bptAmountOut");
        assertApproxEqAbs(bptAmountOut, expectedAddLiquidityBptAmountOut, DELTA, "Wrong bptAmountOut");
    }

    function testRemoveLiquidity() public {
        vm.startPrank(bob);
        router.addLiquidityUnbalanced(pool, tokenAmounts, tokenAmountIn - DELTA, false, bytes(""));

        IERC20(pool).approve(address(vault), MAX_UINT256);

        uint256 bobBptBalance = IERC20(pool).balanceOf(bob);
        uint256 bptAmountIn = bobBptBalance;

        uint256[] memory minAmountsOut = new uint256[](poolTokens.length);
        for (uint256 i = 0; i < poolTokens.length; ++i) {
            minAmountsOut[i] = _less(tokenAmounts[i], 1e4);
        }

        uint256[] memory amountsOut = router.removeLiquidityProportional(
            pool,
            bptAmountIn,
            minAmountsOut,
            false,
            bytes("")
        );

        vm.stopPrank();

        (, , uint256[] memory balances, ) = vault.getPoolTokenInfo(address(pool));

        for (uint256 i = 0; i < poolTokens.length; ++i) {
            // Tokens are transferred to Bob.
            assertApproxEqAbs(
                poolTokens[i].balanceOf(bob),
                defaultAccountBalance(),
                DELTA,
                string.concat("LP: Wrong token balance for ", Strings.toString(i))
            );

            // Tokens are stored in the Vault.
            assertApproxEqAbs(
                poolTokens[i].balanceOf(address(vault)),
                tokenAmounts[i],
                DELTA,
                string.concat("Vault: Wrong token balance for ", Strings.toString(i))
            );

            // Tokens are deposited to the pool.
            assertApproxEqAbs(
                balances[i],
                tokenAmounts[i],
                DELTA,
                string.concat("Pool: Wrong token balance for ", Strings.toString(i))
            );

            // `amountsOut` are correct.
            assertApproxEqAbs(
                amountsOut[i],
                tokenAmounts[i],
                DELTA,
                string.concat("Wrong token amountOut for ", Strings.toString(i))
            );
        }

        // Should burn the correct amount of BPT poolTokens.
        assertEq(IERC20(pool).balanceOf(bob), 0, "LP: Wrong BPT balance");
        assertEq(bobBptBalance, bptAmountIn, "LP: Wrong bptAmountIn");
    }

    function testSwap() public {
        if (!isTestSwapFeeEnabled) {
            vault.manuallySetSwapFee(pool, 0);
        }

        IERC20 tokenIn = poolTokens[tokenIndexIn];
        IERC20 tokenOut = poolTokens[tokenIndexOut];

        vm.prank(bob);
        uint256 amountCalculated = router.swapSingleTokenExactIn(
            pool,
            tokenIn,
            tokenOut,
            tokenAmountIn,
            _less(tokenAmountOut, 1e3),
            MAX_UINT256,
            false,
            bytes("")
        );

        // Tokens are transferred from Bob.
        assertEq(tokenOut.balanceOf(bob), defaultAccountBalance() + amountCalculated, "LP: Wrong tokenOut balance");
        assertEq(tokenIn.balanceOf(bob), defaultAccountBalance() - tokenAmountIn, "LP: Wrong tokenIn balance");

        // Tokens are stored in the Vault.
        assertEq(
            tokenOut.balanceOf(address(vault)),
            tokenAmounts[tokenIndexOut] - amountCalculated,
            "Vault: Wrong tokenOut balance"
        );
        assertEq(
            tokenIn.balanceOf(address(vault)),
            tokenAmounts[tokenIndexIn] + tokenAmountIn,
            "Vault: Wrong tokenIn balance"
        );

        (, , uint256[] memory balances, ) = vault.getPoolTokenInfo(pool);

        assertEq(balances[tokenIndexIn], tokenAmounts[tokenIndexIn] + tokenAmountIn, "Pool: Wrong tokenIn balance");
        assertEq(
            balances[tokenIndexOut],
            tokenAmounts[tokenIndexOut] - amountCalculated,
            "Pool: Wrong tokenOut balance"
        );
    }

    function testMinimumSwapFee() public view {
        assertEq(IBasePool(pool).getMinimumSwapFeePercentage(), poolMinSwapFeePercentage, "Minimum swap fee mismatch");
    }

    function testMaximumSwapFee() public view {
        assertEq(IBasePool(pool).getMaximumSwapFeePercentage(), poolMaxSwapFeePercentage, "Maximum swap fee mismatch");
    }

    function testSetSwapFeeTooLow() public {
        authorizer.grantRole(vault.getActionId(IVaultAdmin.setStaticSwapFeePercentage.selector), alice);
        vm.prank(alice);

        vm.expectRevert(IVaultErrors.SwapFeePercentageTooLow.selector);
        vault.setStaticSwapFeePercentage(pool, poolMinSwapFeePercentage - 1);
    }

    function testSetSwapFeeTooHigh() public {
        authorizer.grantRole(vault.getActionId(IVaultAdmin.setStaticSwapFeePercentage.selector), alice);
        vm.prank(alice);

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.SwapFeePercentageTooHigh.selector));
        vault.setStaticSwapFeePercentage(pool, poolMaxSwapFeePercentage + 1);
    }

    function testAddLiquidityUnbalanced() public {
        authorizer.grantRole(vault.getActionId(IVaultAdmin.setStaticSwapFeePercentage.selector), alice);
        vm.prank(alice);
        vault.setStaticSwapFeePercentage(pool, 10e16);

        uint256[] memory amountsIn = tokenAmounts;
        amountsIn[0] = amountsIn[0].mulDown(IBasePool(pool).getMaximumInvariantRatio());
        vm.prank(bob);

        router.addLiquidityUnbalanced(pool, amountsIn, 0, false, bytes(""));
    }

    function _testGetBptRate(uint256 invariantBefore, uint256 invariantAfter, uint256[] memory amountsIn) internal {
        uint256 totalSupply = bptAmountOut + POOL_MINIMUM_TOTAL_SUPPLY;
        uint256 expectedRate = invariantBefore.divDown(totalSupply);
        uint256 actualRate = IRateProvider(pool).getRate();
        assertEq(actualRate, expectedRate, "Wrong rate");

        vm.prank(bob);
        uint256 addLiquidityBptAmountOut = router.addLiquidityUnbalanced(pool, amountsIn, 0, false, bytes(""));

        totalSupply += addLiquidityBptAmountOut;

        expectedRate = invariantAfter.divDown(totalSupply);
        actualRate = IRateProvider(pool).getRate();
        assertEq(actualRate, expectedRate, "Wrong rate after addLiquidity");
    }

    // Decreases the amount value by base value. Example: base = 100, decrease by 1% / base = 1e4, 0.01% and etc.
    function _less(uint256 amount, uint256 base) private pure returns (uint256) {
        return (amount * (base - 1)) / base;
    }
}
