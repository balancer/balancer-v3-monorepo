// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";
import { TokenConfig } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";
import { RateProviderMock } from "../../contracts/test/RateProviderMock.sol";

contract RouterQueriesDiffRatesTest is BaseVaultTest {
    using ArrayHelpers for *;
    using FixedPoint for uint256;

    // Track the indices for the standard dai/usdc pool.
    uint256 internal daiIdx;
    uint256 internal usdcIdx;

    // A bigger pool init amount is needed, so we can manipulate the token rates safely, without breaking the linear
    // math of PoolMock (Linear math can return amounts out outside of pool balances since it does not have protections
    // in the edge of the pricing curve).
    uint256 internal constant biggerPoolInitAmount = 1e6 * 1e18;

    IRateProvider[] internal rateProviders;

    function setUp() public override {
        (daiIdx, usdcIdx) = getSortedIndexes(address(dai), address(usdc));

        super.setUp();
    }

    function _createPool(address[] memory tokens, string memory label) internal override returns (address) {
        address newPool = factoryMock.createPool("TestPool", "TEST");
        vm.label(newPool, label);

        rateProviders = new IRateProvider[](2);
        rateProviders[daiIdx] = IRateProvider(address(new RateProviderMock()));
        rateProviders[usdcIdx] = IRateProvider(address(new RateProviderMock()));

        factoryMock.registerTestPool(newPool, vault.buildTokenConfig(tokens.asIERC20(), rateProviders));

        return newPool;
    }

    function initPool() internal override {
        vm.startPrank(lp);
        _initPool(pool, [biggerPoolInitAmount, biggerPoolInitAmount].toMemoryArray(), 0);
        vm.stopPrank();
    }

    function testQuerySwapSingleTokenExactInDiffRates__Fuzz(uint256 daiMockRate, uint256 usdcMockRate) public {
        daiMockRate = bound(daiMockRate, 1e17, 1e19);
        usdcMockRate = bound(usdcMockRate, 1e17, 1e19);

        RateProviderMock(address(rateProviders[daiIdx])).mockRate(daiMockRate);
        RateProviderMock(address(rateProviders[usdcIdx])).mockRate(usdcMockRate);

        // 1% of biggerPoolInitAmount, so we have flexibility to handle rate variations (Pool is linear, so edges are
        // not limited and pool math can return a bigger amountOut than the pool balance).
        uint256 exactAmountIn = biggerPoolInitAmount.mulUp(0.01e18);
        // Round down to favor vault.
        uint256 expectedAmountOut = exactAmountIn.mulDown(daiMockRate).divDown(usdcMockRate);

        uint256 snapshotId = vm.snapshot();
        vm.prank(address(0), address(0));
        uint256 queryAmountOut = router.querySwapSingleTokenExactIn(pool, dai, usdc, exactAmountIn, bytes(""));

        vm.revertTo(snapshotId);

        vm.prank(bob);
        uint256 actualAmountOut = router.swapSingleTokenExactIn(
            pool,
            dai,
            usdc,
            exactAmountIn,
            0,
            MAX_UINT256,
            false,
            bytes("")
        );

        assertEq(queryAmountOut, actualAmountOut, "Query and Actual amounts out are wrong");
        assertEq(expectedAmountOut, actualAmountOut, "Expected amount out is wrong");
    }

    function testQuerySwapSingleTokenExactOutDiffRates__Fuzz(uint256 daiMockRate, uint256 usdcMockRate) public {
        daiMockRate = bound(daiMockRate, 1e17, 1e19);
        usdcMockRate = bound(usdcMockRate, 1e17, 1e19);

        RateProviderMock(address(rateProviders[daiIdx])).mockRate(daiMockRate);
        RateProviderMock(address(rateProviders[usdcIdx])).mockRate(usdcMockRate);

        // 1% of biggerPoolInitAmount, so we have flexibility to handle rate variations (Pool is linear, so edges are
        // not limited and pool math can return a bigger amountOut than the pool balance).
        uint256 exactAmountOut = biggerPoolInitAmount.mulUp(0.01e18);
        // Round up to favor vault.
        uint256 expectedAmountIn = exactAmountOut.mulUp(usdcMockRate).divUp(daiMockRate);

        uint256 snapshotId = vm.snapshot();
        vm.prank(address(0), address(0));
        uint256 queryAmountIn = router.querySwapSingleTokenExactOut(pool, dai, usdc, exactAmountOut, bytes(""));

        vm.revertTo(snapshotId);

        vm.prank(bob);
        uint256 actualAmountIn = router.swapSingleTokenExactOut(
            pool,
            dai,
            usdc,
            exactAmountOut,
            MAX_UINT256,
            MAX_UINT256,
            false,
            bytes("")
        );

        assertEq(queryAmountIn, actualAmountIn, "Query and Actual amounts in are wrong");
        assertEq(expectedAmountIn, actualAmountIn, "Expected amount in is wrong");
    }

    function testQueryAddLiquidityProportionalDiffRates__Fuzz(uint256 daiMockRate, uint256 usdcMockRate) public {
        daiMockRate = bound(daiMockRate, 1e17, 1e19);
        usdcMockRate = bound(usdcMockRate, 1e17, 1e19);

        RateProviderMock(address(rateProviders[daiIdx])).mockRate(daiMockRate);
        RateProviderMock(address(rateProviders[usdcIdx])).mockRate(usdcMockRate);

        // 1% of biggerPoolInitAmount, arbitrarily
        uint256 exactBptAmountOut = biggerPoolInitAmount.mulUp(0.01e18);
        // Proportional join is proportional to pool balance, in terms of raw values. So, since the pool has the same
        // balance for USDC and DAI, and the invariant of PoolMock is linear (the sum of both balances),
        // the expectedAmountsIn is `exactBptAmountOut / 2`.
        uint256[] memory expectedAmountsIn = [exactBptAmountOut.divUp(2e18), exactBptAmountOut.divUp(2e18)]
            .toMemoryArray();

        uint256 snapshotId = vm.snapshot();
        vm.prank(address(0), address(0));
        uint256[] memory queryAmountsIn = router.queryAddLiquidityProportional(
            pool,
            expectedAmountsIn,
            exactBptAmountOut,
            bytes("")
        );

        vm.revertTo(snapshotId);

        vm.prank(bob);
        uint256[] memory actualAmountsIn = router.addLiquidityProportional(
            pool,
            expectedAmountsIn,
            exactBptAmountOut,
            false,
            bytes("")
        );

        assertEq(queryAmountsIn[daiIdx], actualAmountsIn[daiIdx], "DAI Query and Actual amounts in are wrong");
        assertEq(expectedAmountsIn[daiIdx], actualAmountsIn[daiIdx], "DAI Expected amount in is wrong");

        assertEq(queryAmountsIn[usdcIdx], actualAmountsIn[usdcIdx], "USDC Query and Actual amounts in are wrong");
        assertEq(expectedAmountsIn[usdcIdx], actualAmountsIn[usdcIdx], "USDC Expected amount in is wrong");
    }
}
