// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";

import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { BasePoolMath } from "@balancer-labs/v3-solidity-utils/contracts/math/BasePoolMath.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";
import { RateProviderMock } from "../../contracts/test/RateProviderMock.sol";

contract RouterQueriesDiffRatesTest is BaseVaultTest {
    using CastingHelpers for address[];
    using FixedPoint for uint256;
    using ArrayHelpers for *;

    // Track the indices for the standard dai/usdc pool.
    uint256 internal daiIdx;
    uint256 internal usdcIdx;

    // A bigger pool init amount is needed, so we can manipulate the token rates safely, without breaking the linear
    // math of PoolMock (linear math can return amounts out outside of pool balances since it does not have protections
    // in the edge of the pricing curve).
    uint256 internal constant biggerPoolInitAmount = 1e6 * 1e18;

    IRateProvider[] internal rateProviders;

    function setUp() public override {
        BaseVaultTest.setUp();

        (daiIdx, usdcIdx) = getSortedIndexes(address(dai), address(usdc));
    }

    function _createPool(address[] memory tokens, string memory label) internal override returns (address) {
        address newPool = factoryMock.createPool("TestPool", "TEST");
        vm.label(newPool, label);

        rateProviders = new IRateProvider[](2);
        rateProviders[0] = IRateProvider(address(new RateProviderMock()));
        rateProviders[1] = IRateProvider(address(new RateProviderMock()));

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

        // 1% of biggerPoolInitAmount, so we have flexibility to handle rate variations. The mock pool math is linear,
        // so edges are not limited, and the pool math can return a bigger amountOut than the pool balance.
        uint256 exactAmountIn = biggerPoolInitAmount.mulUp(1e16);
        // Round down to favor vault.
        uint256 expectedAmountOut = exactAmountIn.mulDown(daiMockRate).divDown(usdcMockRate);

        uint256 snapshotId = vm.snapshot();
        _prankStaticCall();
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

        // 1% of biggerPoolInitAmount, so we have flexibility to handle rate variations. The mock pool math is linear,
        // so edges are not limited, and the pool math can return a bigger amountOut than the pool balance.
        uint256 exactAmountOut = biggerPoolInitAmount.mulUp(1e16);
        // Round up to favor vault.
        uint256 expectedAmountIn = exactAmountOut.mulUp(usdcMockRate).divUp(daiMockRate);

        uint256 snapshotId = vm.snapshot();
        _prankStaticCall();
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

        // 1% of biggerPoolInitAmount, arbitrarily.
        uint256 exactBptAmountOut = biggerPoolInitAmount.mulUp(1e16);
        // Proportional add is proportional to pool balance, in terms of raw values. So, since the pool has the same
        // balance for USDC and DAI, and the invariant of PoolMock is linear (the sum of both balances),
        // the expectedAmountsIn is `exactBptAmountOut / 2`.
        uint256[] memory expectedAmountsIn = [exactBptAmountOut.divUp(2e18), exactBptAmountOut.divUp(2e18)]
            .toMemoryArray();

        uint256 snapshotId = vm.snapshot();
        _prankStaticCall();
        uint256[] memory queryAmountsIn = router.queryAddLiquidityProportional(pool, exactBptAmountOut, bytes(""));

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

    function testQueryAddLiquidityUnbalancedDiffRates__Fuzz(uint256 daiMockRate, uint256 usdcMockRate) public {
        daiMockRate = bound(daiMockRate, 1e17, 1e19);
        usdcMockRate = bound(usdcMockRate, 1e17, 1e19);

        RateProviderMock(address(rateProviders[daiIdx])).mockRate(daiMockRate);
        RateProviderMock(address(rateProviders[usdcIdx])).mockRate(usdcMockRate);

        // DAI is 1% of biggerPoolInitAmount, USDC is 0.5% of biggerPoolInitAmount, arbitrarily.
        uint256[] memory exactAmountsInRaw = [biggerPoolInitAmount.mulUp(1e16), biggerPoolInitAmount.mulUp(0.005e18)]
            .toMemoryArray();
        uint256[] memory exactAmountsInScaled18 = new uint256[](2);
        exactAmountsInScaled18[daiIdx] = exactAmountsInRaw[daiIdx].mulUp(daiMockRate);
        exactAmountsInScaled18[usdcIdx] = exactAmountsInRaw[usdcIdx].mulUp(usdcMockRate);
        (uint256 expectedBptAmountOut, ) = BasePoolMath.computeAddLiquidityUnbalanced(
            vault.getCurrentLiveBalances(pool),
            exactAmountsInScaled18,
            IERC20(pool).totalSupply(),
            0,
            IBasePool(pool)
        );

        uint256 snapshotId = vm.snapshot();
        _prankStaticCall();
        uint256 queryBptAmountOut = router.queryAddLiquidityUnbalanced(pool, exactAmountsInRaw, bytes(""));

        vm.revertTo(snapshotId);

        vm.prank(bob);
        uint256 actualBptAmountOut = router.addLiquidityUnbalanced(
            pool,
            exactAmountsInRaw,
            expectedBptAmountOut,
            false,
            bytes("")
        );

        assertEq(queryBptAmountOut, actualBptAmountOut, "Query and Actual bpt amounts out are wrong");
        assertEq(expectedBptAmountOut, actualBptAmountOut, "BPT expected amount out is wrong");
    }

    function testQueryAddLiquiditySingleTokenExactOutDiffRates__Fuzz(uint256 daiMockRate, uint256 usdcMockRate) public {
        daiMockRate = bound(daiMockRate, 1e17, 1e19);
        usdcMockRate = bound(usdcMockRate, 1e17, 1e19);

        RateProviderMock(address(rateProviders[daiIdx])).mockRate(daiMockRate);
        RateProviderMock(address(rateProviders[usdcIdx])).mockRate(usdcMockRate);

        // 1% of biggerPoolInitAmount, arbitrarily.
        uint256 exactBptAmountOut = biggerPoolInitAmount.mulUp(1e16);
        (uint256 expectedAmountInScaled18, ) = BasePoolMath.computeAddLiquiditySingleTokenExactOut(
            vault.getCurrentLiveBalances(pool),
            daiIdx,
            exactBptAmountOut,
            IERC20(pool).totalSupply(),
            0,
            IBasePool(pool)
        );
        uint256 expectedAmountInRaw = expectedAmountInScaled18.divUp(daiMockRate);

        uint256 snapshotId = vm.snapshot();
        _prankStaticCall();
        uint256 queryAmountIn = router.queryAddLiquiditySingleTokenExactOut(pool, dai, exactBptAmountOut, bytes(""));

        vm.revertTo(snapshotId);

        vm.prank(bob);
        uint256 actualAmountIn = router.addLiquiditySingleTokenExactOut(
            pool,
            dai,
            MAX_UINT128,
            exactBptAmountOut,
            false,
            bytes("")
        );

        assertEq(queryAmountIn, actualAmountIn, "Query and Actual DAI amounts in are wrong");
        assertEq(expectedAmountInRaw, actualAmountIn, "DAI expected amount in is wrong");
    }

    function testQueryAddLiquidityCustomDiffRates__Fuzz(uint256 daiMockRate, uint256 usdcMockRate) public {
        daiMockRate = bound(daiMockRate, 1e17, 1e19);
        usdcMockRate = bound(usdcMockRate, 1e17, 1e19);

        RateProviderMock(address(rateProviders[daiIdx])).mockRate(daiMockRate);
        RateProviderMock(address(rateProviders[usdcIdx])).mockRate(usdcMockRate);

        // 1% of biggerPoolInitAmount, arbitrarily.
        uint256 expectedBptAmountOut = biggerPoolInitAmount.mulUp(1e16);
        // Arbitrary numbers.
        uint256[] memory maxAmountsIn = [expectedBptAmountOut.divUp(3e18), expectedBptAmountOut.divUp(5e18)]
            .toMemoryArray();
        // On addLiquidity, the amount in is scaled up first (round down), addLiquidityCustom returns the maxAmountsIn
        // as amountsIn, and finally it is scaled down (round up).
        uint256[] memory expectedAmountsIn = new uint256[](2);
        expectedAmountsIn[daiIdx] = (maxAmountsIn[0].mulDown(daiMockRate)).divUp(daiMockRate);
        expectedAmountsIn[usdcIdx] = (maxAmountsIn[1].mulDown(usdcMockRate)).divUp(usdcMockRate);

        uint256 snapshotId = vm.snapshot();
        _prankStaticCall();
        (uint256[] memory queryAmountsIn, uint256 queryBptOut, ) = router.queryAddLiquidityCustom(
            pool,
            maxAmountsIn,
            expectedBptAmountOut,
            bytes("")
        );

        vm.revertTo(snapshotId);

        vm.prank(bob);
        (uint256[] memory actualAmountsIn, uint256 actualBptOut, ) = router.addLiquidityCustom(
            pool,
            maxAmountsIn,
            expectedBptAmountOut,
            false,
            bytes("")
        );

        assertEq(queryAmountsIn[daiIdx], actualAmountsIn[daiIdx], "DAI Query and Actual amounts in are wrong");
        assertEq(expectedAmountsIn[daiIdx], actualAmountsIn[daiIdx], "DAI Expected amount in is wrong");

        assertEq(queryAmountsIn[usdcIdx], actualAmountsIn[usdcIdx], "USDC Query and Actual amounts in are wrong");
        assertEq(expectedAmountsIn[usdcIdx], actualAmountsIn[usdcIdx], "USDC Expected amount in is wrong");

        assertEq(queryBptOut, actualBptOut, "BPT Query and Actual amounts out are wrong");
        assertEq(expectedBptAmountOut, actualBptOut, "BPT Expected amount out is wrong");
    }

    function testQueryRemoveLiquidityProportionalDiffRates__Fuzz(uint256 daiMockRate, uint256 usdcMockRate) public {
        daiMockRate = bound(daiMockRate, 1e17, 1e19);
        usdcMockRate = bound(usdcMockRate, 1e17, 1e19);

        RateProviderMock(address(rateProviders[daiIdx])).mockRate(daiMockRate);
        RateProviderMock(address(rateProviders[usdcIdx])).mockRate(usdcMockRate);

        // 1% of biggerPoolInitAmount, arbitrarily.
        uint256 exactBptAmountIn = biggerPoolInitAmount.mulUp(1e16);
        // Proportional remove is proportional to pool balance, in terms of raw values. So, since the pool has the same
        // balance for USDC and DAI, and the invariant of PoolMock is linear (the sum of both balances),
        // the expectedAmountsOut is `exactBptAmountIn / 2`.
        uint256[] memory expectedAmountsOut = [exactBptAmountIn.divUp(2e18), exactBptAmountIn.divUp(2e18)]
            .toMemoryArray();

        uint256 snapshotId = vm.snapshot();
        _prankStaticCall();
        uint256[] memory queryAmountsOut = router.queryRemoveLiquidityProportional(pool, exactBptAmountIn, bytes(""));

        vm.revertTo(snapshotId);

        vm.prank(lp);
        uint256[] memory actualAmountsOut = router.removeLiquidityProportional(
            pool,
            exactBptAmountIn,
            expectedAmountsOut,
            false,
            bytes("")
        );

        assertEq(queryAmountsOut[daiIdx], actualAmountsOut[daiIdx], "DAI Query and Actual amounts out are wrong");
        assertEq(expectedAmountsOut[daiIdx], actualAmountsOut[daiIdx], "DAI Expected amount out is wrong");

        assertEq(queryAmountsOut[usdcIdx], actualAmountsOut[usdcIdx], "USDC Query and Actual amounts out are wrong");
        assertEq(expectedAmountsOut[usdcIdx], actualAmountsOut[usdcIdx], "USDC Expected amount out is wrong");
    }

    function testQueryRemoveLiquiditySingleTokenExactInDiffRates__Fuzz(
        uint256 daiMockRate,
        uint256 usdcMockRate
    ) public {
        daiMockRate = bound(daiMockRate, 1e17, 1e19);
        usdcMockRate = bound(usdcMockRate, 1e17, 1e19);

        RateProviderMock(address(rateProviders[daiIdx])).mockRate(daiMockRate);
        RateProviderMock(address(rateProviders[usdcIdx])).mockRate(usdcMockRate);

        // 1% of biggerPoolInitAmount, arbitrarily.
        uint256 exactBptAmountIn = biggerPoolInitAmount.mulUp(1e16);
        (uint256 expectedAmountOutScaled18, ) = BasePoolMath.computeRemoveLiquiditySingleTokenExactIn(
            vault.getCurrentLiveBalances(pool),
            daiIdx,
            exactBptAmountIn,
            IERC20(pool).totalSupply(),
            0,
            IBasePool(pool)
        );
        uint256 expectedAmountOutRaw = expectedAmountOutScaled18.divDown(daiMockRate);

        uint256 snapshotId = vm.snapshot();
        _prankStaticCall();
        uint256 queryAmountOut = router.queryRemoveLiquiditySingleTokenExactIn(pool, exactBptAmountIn, dai, bytes(""));

        vm.revertTo(snapshotId);

        vm.prank(lp);
        uint256 actualAmountOut = router.removeLiquiditySingleTokenExactIn(
            pool,
            exactBptAmountIn,
            dai,
            expectedAmountOutRaw,
            false,
            bytes("")
        );

        assertEq(queryAmountOut, actualAmountOut, "DAI Query and Actual amounts out are wrong");
        assertEq(expectedAmountOutRaw, actualAmountOut, "DAI Expected amount out is wrong");
    }

    function testQueryRemoveLiquiditySingleTokenExactOutDiffRates__Fuzz(
        uint256 daiMockRate,
        uint256 usdcMockRate
    ) public {
        daiMockRate = bound(daiMockRate, 1e17, 1e19);
        usdcMockRate = bound(usdcMockRate, 1e17, 1e19);

        RateProviderMock(address(rateProviders[daiIdx])).mockRate(daiMockRate);
        RateProviderMock(address(rateProviders[usdcIdx])).mockRate(usdcMockRate);

        // 1% of biggerPoolInitAmount, arbitrarily.
        uint256 exactAmountOut = biggerPoolInitAmount.mulUp(1e16);
        (uint256 expectedBptAmountIn, ) = BasePoolMath.computeRemoveLiquiditySingleTokenExactOut(
            vault.getCurrentLiveBalances(pool),
            daiIdx,
            // Amount out needs to be scaled18, so we multiply by the rate (considering DAI already has 18 decimals)
            exactAmountOut.mulUp(daiMockRate),
            IERC20(pool).totalSupply(),
            0,
            IBasePool(pool)
        );

        uint256 snapshotId = vm.snapshot();
        _prankStaticCall();
        uint256 queryBptAmountIn = router.queryRemoveLiquiditySingleTokenExactOut(pool, dai, exactAmountOut, bytes(""));

        vm.revertTo(snapshotId);

        vm.prank(lp);
        uint256 actualBptAmountIn = router.removeLiquiditySingleTokenExactOut(
            pool,
            expectedBptAmountIn,
            dai,
            exactAmountOut,
            false,
            bytes("")
        );

        assertEq(queryBptAmountIn, actualBptAmountIn, "BPT Query and Actual amounts out are wrong");
        assertEq(expectedBptAmountIn, actualBptAmountIn, "BPT Expected amount out is wrong");
    }

    function testQueryRemoveLiquidityCustomDiffRates__Fuzz(uint256 daiMockRate, uint256 usdcMockRate) public {
        daiMockRate = bound(daiMockRate, 1e17, 1e19);
        usdcMockRate = bound(usdcMockRate, 1e17, 1e19);

        RateProviderMock(address(rateProviders[daiIdx])).mockRate(daiMockRate);
        RateProviderMock(address(rateProviders[usdcIdx])).mockRate(usdcMockRate);

        // 1% of biggerPoolInitAmount, arbitrarily.
        uint256 expectedBptAmountIn = biggerPoolInitAmount.mulUp(1e16);
        // Arbitrary numbers.
        uint256[] memory minAmountsOut = [expectedBptAmountIn.divUp(3e18), expectedBptAmountIn.divUp(5e18)]
            .toMemoryArray();
        // On addLiquidity, the amount out is scaled up first (round up), addLiquidityCustom returns the minAmountsOut
        // as amountsOut, and finally it is scaled down (round down).
        uint256[] memory expectedAmountsOut = new uint256[](2);
        expectedAmountsOut[daiIdx] = (minAmountsOut[daiIdx].mulUp(daiMockRate)).divDown(daiMockRate);
        expectedAmountsOut[usdcIdx] = (minAmountsOut[usdcIdx].mulUp(usdcMockRate)).divDown(usdcMockRate);

        uint256 snapshotId = vm.snapshot();
        _prankStaticCall();
        (uint256 queryBptIn, uint256[] memory queryAmountsOut, ) = router.queryRemoveLiquidityCustom(
            pool,
            expectedBptAmountIn,
            minAmountsOut,
            bytes("")
        );

        vm.revertTo(snapshotId);

        vm.prank(lp);
        (uint256 actualBptIn, uint256[] memory actualAmountsOut, ) = router.removeLiquidityCustom(
            pool,
            expectedBptAmountIn,
            minAmountsOut,
            false,
            bytes("")
        );

        assertEq(queryAmountsOut[daiIdx], actualAmountsOut[daiIdx], "DAI Query and Actual amounts out are wrong");
        assertEq(expectedAmountsOut[daiIdx], actualAmountsOut[daiIdx], "DAI Expected amount out is wrong");

        assertEq(queryAmountsOut[usdcIdx], actualAmountsOut[usdcIdx], "USDC Query and Actual amounts out are wrong");
        assertEq(expectedAmountsOut[usdcIdx], actualAmountsOut[usdcIdx], "USDC Expected amount out is wrong");

        assertEq(queryBptIn, actualBptIn, "BPT Query and Actual amounts in are wrong");
        assertEq(expectedBptAmountIn, actualBptIn, "BPT Expected amount in is wrong");
    }

    function testQueryRemoveLiquidityRecoveryDiffRates__Fuzz(uint256 daiMockRate, uint256 usdcMockRate) public {
        daiMockRate = bound(daiMockRate, 1e17, 1e19);
        usdcMockRate = bound(usdcMockRate, 1e17, 1e19);

        RateProviderMock(address(rateProviders[daiIdx])).mockRate(daiMockRate);
        RateProviderMock(address(rateProviders[usdcIdx])).mockRate(usdcMockRate);

        // 1% of biggerPoolInitAmount, arbitrarily.
        uint256 exactBptAmountIn = biggerPoolInitAmount.mulUp(1e16);
        // Recovery remove is proportional to pool balance, in terms of raw values. So, since the pool has the same
        // balance for USDC and DAI, and the invariant of PoolMock is linear (the sum of both balances),
        // the expectedAmountsOut is `exactBptAmountIn / 2`.
        uint256[] memory expectedAmountsOut = [exactBptAmountIn.divUp(2e18), exactBptAmountIn.divUp(2e18)]
            .toMemoryArray();

        vault.manualEnableRecoveryMode(pool);

        uint256 snapshotId = vm.snapshot();
        _prankStaticCall();
        uint256[] memory queryAmountsOut = router.queryRemoveLiquidityRecovery(pool, exactBptAmountIn);

        vm.revertTo(snapshotId);

        vm.prank(lp);
        uint256[] memory actualAmountsOut = router.removeLiquidityRecovery(pool, exactBptAmountIn);

        assertEq(queryAmountsOut[daiIdx], actualAmountsOut[daiIdx], "DAI Query and Actual amounts out are wrong");
        assertEq(expectedAmountsOut[daiIdx], actualAmountsOut[daiIdx], "DAI Expected amount out is wrong");

        assertEq(queryAmountsOut[usdcIdx], actualAmountsOut[usdcIdx], "USDC Query and Actual amounts out are wrong");
        assertEq(expectedAmountsOut[usdcIdx], actualAmountsOut[usdcIdx], "USDC Expected amount out is wrong");
    }
}
