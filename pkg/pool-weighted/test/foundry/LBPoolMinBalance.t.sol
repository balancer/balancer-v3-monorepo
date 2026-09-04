// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IWeightedPool } from "@balancer-labs/v3-interfaces/contracts/pool-weighted/IWeightedPool.sol";
import { ILBPCommon } from "@balancer-labs/v3-interfaces/contracts/pool-weighted/ILBPCommon.sol";
import { ILBPool } from "@balancer-labs/v3-interfaces/contracts/pool-weighted/ILBPool.sol";

import { WeightedMath } from "@balancer-labs/v3-solidity-utils/contracts/math/WeightedMath.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { LBPCommon } from "../../contracts/lbp/LBPCommon.sol";
import { WeightedLBPTest } from "./utils/WeightedLBPTest.sol";

contract LBPoolMinBalanceTest is WeightedLBPTest {
    using FixedPoint for uint256;

    uint256 internal constant LOW_PROJECT_WEIGHT = 10e16;
    uint256 internal constant MIN_WEIGHTED_SWAP_FEE = 0.001e16;

    uint256 internal minRedeemableBalance;
    uint256 internal minimumTradeAmount;

    uint256 internal saleStart;
    uint256 internal saleEnd;

    function setUp() public virtual override {
        vaultMockMinTradeAmount = PRODUCTION_MIN_TRADE_AMOUNT;
        super.setUp();

        minimumTradeAmount = vault.getMinimumTradeAmount();
        minRedeemableBalance = vault.getPoolMinimumTotalSupply() + minimumTradeAmount;

        saleStart = block.timestamp + DEFAULT_START_OFFSET;
        saleEnd = block.timestamp + DEFAULT_END_OFFSET;
    }

    function createPool() internal virtual override returns (address newPool, bytes memory poolArgs) {
        return
            _createLBPool(
                address(0),
                uint32(block.timestamp + DEFAULT_START_OFFSET),
                uint32(block.timestamp + DEFAULT_END_OFFSET),
                DEFAULT_PROJECT_TOKENS_SWAP_IN
            );
    }

    function testInheritedMinimumIsNotTheLimitASwapEnforces() public view {
        uint256 redeemableFloor = ILBPCommon(pool).getMinRedeemableBalance();
        uint256[] memory inherited = IWeightedPool(pool).getMinTokenBalances();

        assertEq(redeemableFloor, minRedeemableBalance, "The pool reports an unexpected redeemable floor");
        assertLt(inherited[projectIdx], redeemableFloor, "The inherited project minimum is not below the floor");
        assertLt(inherited[reserveIdx], redeemableFloor, "The inherited reserve minimum is not below the floor");
    }

    function testSeedlessReserveBelowMinimumTradeAmountIsRejected() public {
        address lbp = _buildSeedless(false);
        uint256 realReserve = _accrueReserve(lbp, 100e18);

        uint256 residual = minimumTradeAmount - 1;

        uint256 snapshotId = vm.snapshotState();
        _forceBalance(lbp, reserveIdx, residual);
        assertFalse(_ownerCanExit(lbp), "A real reserve below the minimum trade amount is not fully redeemable");
        vm.revertToState(snapshotId);

        _expectBlocksRedemption(reserveIdx, residual);
        _sellProjectExactOut(lbp, realReserve - residual);
    }

    function testInheritedChecksPassOnTheAugmentedReserve() public {
        address lbp = _buildSeedless(false);
        uint256 realReserve = _accrueReserve(lbp, 100e18);

        (, uint256 virtualReserve) = ILBPool(lbp).getReserveTokenVirtualBalance();
        uint256 augmented = realReserve + virtualReserve;

        uint256 residual = minimumTradeAmount - 1;
        uint256 amountOut = realReserve - residual;

        uint256 inheritedFloor = IWeightedPool(lbp).getMinTokenBalances()[reserveIdx];

        assertGt(augmented - amountOut, inheritedFloor, "The inherited floor would have caught this swap");
        assertLt(residual, inheritedFloor, "The real balance is not below the inherited floor");
        assertGt(augmented.mulDown(30e16), amountOut, "The maximum-out ratio would have caught this swap");
        assertLt(realReserve.mulDown(30e16), amountOut, "The maximum-out ratio on the real balance would allow it");

        _expectBlocksRedemption(reserveIdx, residual);
        _sellProjectExactOut(lbp, amountOut);
    }

    function testSeedlessRealReserveAtTheMinimumTradeAmountIsRejected() public {
        address lbp = _buildSeedless(false);
        uint256 realReserve = _accrueReserve(lbp, 100e18);

        uint256 snapshotId = vm.snapshotState();
        _forceBalance(lbp, reserveIdx, minimumTradeAmount);
        assertFalse(_ownerCanExit(lbp), "A real reserve at the minimum trade amount is not fully redeemable");
        vm.revertToState(snapshotId);

        _expectBlocksRedemption(reserveIdx, minimumTradeAmount);
        _sellProjectExactOut(lbp, realReserve - minimumTradeAmount);
    }

    function testSeedlessRealReserveZeroIsAccepted() public {
        address lbp = _buildSeedless(false);
        uint256 realReserve = _accrueReserve(lbp, 100e18);

        _sellProjectExactOut(lbp, realReserve);

        assertEq(vault.getCurrentLiveBalances(lbp)[reserveIdx], 0, "Real reserve is not zero");
        assertTrue(_ownerCanExit(lbp), "Owner cannot exit with the real reserve fully swept");
    }

    function testSeedlessRealReserveFloorBoundary() public {
        address lbp = _buildSeedless(false);
        uint256 realReserve = _accrueReserve(lbp, 100e18);

        uint256 snapshotId = vm.snapshotState();

        uint256 amountJustBelow = realReserve - (minRedeemableBalance - 1);
        _expectBlocksRedemption(reserveIdx, minRedeemableBalance - 1);
        _sellProjectExactOut(lbp, amountJustBelow);

        vm.revertToState(snapshotId);

        _sellProjectExactOut(lbp, realReserve - minRedeemableBalance);
        assertEq(
            vault.getCurrentLiveBalances(lbp)[reserveIdx],
            minRedeemableBalance,
            "The floor was not placed exactly"
        );
        assertTrue(_ownerCanExit(lbp), "Owner cannot exit with the real reserve sitting on the floor");
    }

    function testSeededProjectSideExactInBottomsOutAtTheFloor() public {
        address lbp = _buildSeeded(LOW_PROJECT_WEIGHT, true);
        _fundBuyer();

        _warpIntoSale();

        uint256 swaps;
        while (swaps < 100) {
            uint256[] memory balances = vault.getCurrentLiveBalances(lbp);
            if (balances[projectIdx] <= 8e6) {
                break;
            }

            uint256 amountIn = balances[reserveIdx].mulDown(30e16);

            vm.prank(alice);
            try
                router.swapSingleTokenExactIn(lbp, reserveToken, projectToken, amountIn, 0, MAX_UINT256, false, "")
            returns (uint256) {
                ++swaps;
            } catch {
                break;
            }
        }

        assertGt(swaps, 0, "The walk made no progress");

        uint256 lowest = _lowestReachableProjectBalance(lbp);

        assertEq(lowest, minRedeemableBalance, "Exact-in can still reach a balance below the floor");
        assertTrue(_ownerCanExit(lbp), "Owner cannot exit at the lowest reachable balance");
    }

    function testSeededProjectSideAtMinimumWeightBottomsOutAtTheFloor() public {
        address lbp = _buildSeeded(1e16, true);
        _fundBuyer();

        _warpIntoSale();

        uint256[] memory balances = vault.getCurrentLiveBalances(lbp);
        uint256 amountIn = balances[reserveIdx].mulDown(30e16);

        vm.prank(alice);
        router.swapSingleTokenExactIn(lbp, reserveToken, projectToken, amountIn, 0, MAX_UINT256, false, "");

        uint256 lowest = _lowestReachableProjectBalance(lbp);

        assertEq(lowest, minRedeemableBalance, "Exact-in can still reach a balance below the floor at 1 percent");
        assertTrue(_ownerCanExit(lbp), "Owner cannot exit at the lowest reachable balance");
    }

    function testSeededProjectSideAtAnExpensiveWeightStillStopsAtTheFloor() public {
        address lbp = _buildSeeded(30e16, true);
        _fundBuyer();

        _warpIntoSale();

        uint256 swaps;
        while (swaps < 100) {
            uint256[] memory balances = vault.getCurrentLiveBalances(lbp);
            if (balances[projectIdx] <= 8e6) {
                break;
            }

            uint256 amountIn = balances[reserveIdx].mulDown(30e16);

            vm.prank(alice);
            try
                router.swapSingleTokenExactIn(lbp, reserveToken, projectToken, amountIn, 0, MAX_UINT256, false, "")
            returns (uint256) {
                ++swaps;
            } catch {
                break;
            }
        }

        uint256 lowest = _lowestReachableProjectBalance(lbp);

        assertGe(lowest, minRedeemableBalance, "Exact-in reached a balance below the floor at 30 percent");
        assertTrue(_ownerCanExit(lbp), "Owner cannot exit at the lowest reachable balance");
    }

    function testSeededBidirectionalReserveSideExactInStopsAtTheFloor() public {
        address lbp = _buildSeeded(99e16, false);
        _fundSeller();

        _warpIntoSale();

        uint256 swaps;
        while (swaps < 100) {
            uint256[] memory balances = vault.getCurrentLiveBalances(lbp);
            if (balances[reserveIdx] <= 8e6) {
                break;
            }

            uint256 amountIn = balances[projectIdx].mulDown(30e16);

            vm.prank(lp);
            try
                router.swapSingleTokenExactIn(lbp, projectToken, reserveToken, amountIn, 0, MAX_UINT256, false, "")
            returns (uint256) {
                ++swaps;
            } catch {
                break;
            }
        }

        assertGt(swaps, 0, "The reserve-side walk made no progress");

        uint256 lowest = _lowestReachableReserveBalance(lbp);

        assertEq(lowest, minRedeemableBalance, "Exact-in can still reach a real reserve below the floor");
        assertTrue(_ownerCanExit(lbp), "Owner cannot exit at the lowest reachable real reserve");
    }

    function testSeedlessFirstPurchaseIsHeldToTheFloor() public {
        address lbp = _buildSeedless(false);
        vault.manualSetStaticSwapFeePercentage(lbp, MIN_WEIGHTED_SWAP_FEE);

        _warpIntoSale();

        uint256 smallest = _smallestFirstPurchase(lbp);
        assertGe(smallest, minRedeemableBalance, "The smallest admitted first purchase is below the floor");

        vm.prank(alice);
        router.swapSingleTokenExactIn(lbp, reserveToken, projectToken, smallest, 0, MAX_UINT256, false, "");

        uint256 storedReserve = vault.getCurrentLiveBalances(lbp)[reserveIdx];
        assertGe(storedReserve, minRedeemableBalance, "The stored real reserve is below the floor");
        assertTrue(_ownerCanExit(lbp), "Owner cannot exit after the smallest admitted first purchase");
    }

    function testSeedlessFirstPurchaseInsideTheBandIsRejected() public {
        address lbp = _buildSeedlessWithWeights(LOW_PROJECT_WEIGHT);
        vault.manualSetStaticSwapFeePercentage(lbp, MIN_WEIGHTED_SWAP_FEE);

        _warpIntoSale();

        uint256 purchase = 1_223_014;
        uint256 storedIfAdmitted = purchase - purchase.mulUp(MIN_WEIGHTED_SWAP_FEE);

        assertLt(storedIfAdmitted, minRedeemableBalance, "The test purchase is not below the floor");

        _expectBlocksRedemption(reserveIdx, storedIfAdmitted);
        vm.prank(alice);
        router.swapSingleTokenExactIn(lbp, reserveToken, projectToken, purchase, 0, MAX_UINT256, false, "");
    }

    function testSeedlessFirstPurchaseWithAMaximalAggregateFee() public {
        address lbp = _buildSeedlessWithWeights(LOW_PROJECT_WEIGHT);
        vault.manualSetStaticSwapFeePercentage(lbp, MIN_WEIGHTED_SWAP_FEE);
        vault.manualSetAggregateSwapFeePercentage(lbp, 99.9e16);

        _warpIntoSale();

        uint256 smallest = _smallestFirstPurchase(lbp);

        vm.prank(alice);
        router.swapSingleTokenExactIn(lbp, reserveToken, projectToken, smallest, 0, MAX_UINT256, false, "");

        assertGe(
            vault.getCurrentLiveBalances(lbp)[reserveIdx],
            minRedeemableBalance,
            "The aggregate fee took the stored real reserve below the floor"
        );
        assertTrue(_ownerCanExit(lbp), "Owner cannot exit with the aggregate fee near its maximum");
    }

    function testSeededPoolStillRefusesTheDrawdownWithMaxOutRatio() public {
        address lbp = _buildSeeded(HIGH_WEIGHT, false);

        _warpIntoSale();

        uint256 realReserve = vault.getCurrentLiveBalances(lbp)[reserveIdx];
        uint256 amountOut = realReserve - (minimumTradeAmount - 1);

        vm.prank(lp);
        vm.expectRevert(WeightedMath.MaxOutRatio.selector);
        router.swapSingleTokenExactOut(lbp, projectToken, reserveToken, amountOut, MAX_UINT256, MAX_UINT256, false, "");
    }

    function testUnidirectionalSeedlessStillBlocksReserveOut() public {
        address lbp = _buildSeedless(true);
        uint256 realReserve = _accrueReserve(lbp, 100e18);

        uint256 amountOut = realReserve - (minimumTradeAmount - 1);

        vm.prank(lp);
        vm.expectRevert(LBPCommon.SwapOfProjectTokenIn.selector);
        router.swapSingleTokenExactOut(lbp, projectToken, reserveToken, amountOut, MAX_UINT256, MAX_UINT256, false, "");
    }

    function testExactOutMinimumIsUnchanged() public {
        address lbp = _buildSeeded(HIGH_WEIGHT, false);

        _warpIntoSale();

        uint256 exactOutFloor = (7 * minimumTradeAmount) / 3;
        assertGt(exactOutFloor, minRedeemableBalance, "The exact-out floor is not above the redeemable floor");

        uint256 balance = vault.getCurrentLiveBalances(lbp)[reserveIdx];
        uint256 steps;

        while (steps < 200) {
            uint256 amountOut = balance.mulDown(30e16);
            if (amountOut < minimumTradeAmount) {
                break;
            }

            vm.prank(lp);
            try
                router.swapSingleTokenExactOut(
                    lbp,
                    projectToken,
                    reserveToken,
                    amountOut,
                    MAX_UINT256,
                    MAX_UINT256,
                    false,
                    ""
                )
            returns (uint256) {
                balance = vault.getCurrentLiveBalances(lbp)[reserveIdx];
            } catch {
                break;
            }
            ++steps;
        }

        assertGt(steps, 0, "The exact-out walk made no progress");
        assertGt(balance, exactOutFloor, "Exact-out reached below its own minimum");
        assertTrue(_ownerCanExit(lbp), "Owner cannot exit after an exact-out walk");
    }

    function testBalanceBelowFloorHasNoAvailableSwap() public {
        address lbp = _buildSeeded(HIGH_WEIGHT, true);

        _warpIntoSale();
        _forceBalance(lbp, projectIdx, minimumTradeAmount);

        vm.prank(alice);
        vm.expectRevert(WeightedMath.MaxOutRatio.selector);
        router.swapSingleTokenExactOut(
            lbp,
            reserveToken,
            projectToken,
            minimumTradeAmount,
            MAX_UINT256,
            MAX_UINT256,
            false,
            ""
        );

        vm.prank(alice);
        vm.expectRevert(LBPCommon.SwapOfProjectTokenIn.selector);
        router.swapSingleTokenExactIn(lbp, projectToken, reserveToken, 1e18, 0, MAX_UINT256, false, "");

        assertFalse(_ownerCanExit(lbp), "The forced state is not fully redeemable");
    }

    function testBalanceAtFloorBlocksFurtherSwapsButAllowsWithdrawal() public {
        address lbp = _buildSeeded(HIGH_WEIGHT, true);

        _warpIntoSale();
        _forceBalance(lbp, projectIdx, minRedeemableBalance);

        vm.prank(alice);
        vm.expectRevert(WeightedMath.MaxOutRatio.selector);
        router.swapSingleTokenExactOut(
            lbp,
            reserveToken,
            projectToken,
            minRedeemableBalance,
            MAX_UINT256,
            MAX_UINT256,
            false,
            ""
        );

        vm.prank(alice);
        vm.expectRevert(WeightedMath.MaxOutRatio.selector);
        router.swapSingleTokenExactOut(
            lbp,
            reserveToken,
            projectToken,
            minimumTradeAmount,
            MAX_UINT256,
            MAX_UINT256,
            false,
            ""
        );

        uint256 maximalAmountIn = vault.getCurrentLiveBalances(lbp)[reserveIdx].mulDown(30e16);

        vm.prank(alice);
        vm.expectPartialRevert(LBPCommon.TokenBalanceBlocksRedemption.selector);
        router.swapSingleTokenExactIn(lbp, reserveToken, projectToken, maximalAmountIn, 0, MAX_UINT256, false, "");

        assertTrue(_ownerCanExit(lbp), "Owner cannot withdraw from a balance sitting on the floor");
    }

    function testPartialWithdrawalFromFloorIsRefused() public {
        address lbp = _buildSeeded(LOW_PROJECT_WEIGHT, true);
        _fundBuyer();

        _warpIntoSale();

        uint256 swaps;
        while (swaps < 100) {
            uint256[] memory balances = vault.getCurrentLiveBalances(lbp);
            if (balances[projectIdx] <= 8e6) {
                break;
            }

            uint256 amountIn = balances[reserveIdx].mulDown(30e16);

            vm.prank(alice);
            try
                router.swapSingleTokenExactIn(lbp, reserveToken, projectToken, amountIn, 0, MAX_UINT256, false, "")
            returns (uint256) {
                ++swaps;
            } catch {
                break;
            }
        }

        assertEq(_lowestReachableProjectBalance(lbp), minRedeemableBalance, "The buyer did not stop on the floor");

        vm.warp(saleEnd + 1);

        assertTrue(_ownerCanExit(lbp), "The single full withdrawal does not clear from the floor");

        uint256 totalSupply = IERC20(lbp).totalSupply();
        uint256 burn = totalSupply / 2;

        uint256[] memory endingBalances = vault.getCurrentLiveBalances(lbp);
        uint256 endingProject = endingBalances[projectIdx];
        uint256 endingReserve = endingBalances[reserveIdx];

        uint256 remainingProject = endingProject - (endingProject * burn) / totalSupply;
        uint256 remainingReserve = endingReserve - (endingReserve * burn) / totalSupply;

        assertLt(remainingProject, minRedeemableBalance, "The remainder would not be inside the band");

        uint256 maximalBurn = totalSupply - vault.getPoolMinimumTotalSupply();
        uint256 residueAfterAFullExit = endingReserve - (endingReserve * maximalBurn) / totalSupply;

        assertGt(remainingReserve, residueAfterAFullExit, "Partial withdrawal does not leave additional reserve");

        vm.startPrank(bob);
        IERC20(lbp).approve(address(router), MAX_UINT256);
        vm.expectRevert(
            abi.encodeWithSelector(
                LBPCommon.RemainingBalanceBlocksRedemption.selector,
                projectIdx,
                remainingProject,
                totalSupply - burn
            )
        );
        router.removeLiquidityProportional(lbp, burn, new uint256[](2), false, "");
        vm.stopPrank();

        assertTrue(_ownerCanExit(lbp), "The full exit no longer clears from the floor");
    }

    function testOrdinaryLifecycleOnEveryConfiguration() public {
        address seeded = _buildSeeded(HIGH_WEIGHT, true);
        address seedlessBuyOnly = _buildSeedless(true);
        address seedlessBidirectional = _buildSeedless(false);

        _accrueReserve(seeded, 100e18);
        _accrueReserve(seedlessBuyOnly, 100e18);
        _accrueReserve(seedlessBidirectional, 100e18);

        assertTrue(_ownerCanExit(seeded), "Owner cannot exit a seeded sale");
        assertTrue(_ownerCanExit(seedlessBuyOnly), "Owner cannot exit a seedless buy-only sale");
        assertTrue(_ownerCanExit(seedlessBidirectional), "Owner cannot exit a seedless bidirectional sale");
    }

    function _buildSeedless(bool blockProjectIn) internal returns (address lbp) {
        uint256 saved = reserveTokenVirtualBalance;
        reserveTokenVirtualBalance = poolInitAmount;

        (lbp, ) = _createLBPool(address(0), uint32(saleStart), uint32(saleEnd), blockProjectIn);

        reserveTokenVirtualBalance = saved;

        _initWith(lbp, poolInitAmount, 0);
    }

    function _buildSeedlessWithWeights(uint256 projectWeight) internal returns (address lbp) {
        uint256 saved = reserveTokenVirtualBalance;
        reserveTokenVirtualBalance = poolInitAmount;

        (lbp, ) = _createLBPoolWithCustomWeights(
            address(0),
            projectWeight,
            FixedPoint.ONE - projectWeight,
            projectWeight,
            FixedPoint.ONE - projectWeight,
            uint32(saleStart),
            uint32(saleEnd),
            false
        );

        reserveTokenVirtualBalance = saved;

        _initWith(lbp, poolInitAmount, 0);
    }

    function _buildSeeded(uint256 projectWeight, bool blockProjectIn) internal returns (address lbp) {
        uint256 saved = reserveTokenVirtualBalance;
        reserveTokenVirtualBalance = 0;

        (lbp, ) = _createLBPoolWithCustomWeights(
            address(0),
            projectWeight,
            FixedPoint.ONE - projectWeight,
            projectWeight,
            FixedPoint.ONE - projectWeight,
            uint32(saleStart),
            uint32(saleEnd),
            blockProjectIn
        );

        reserveTokenVirtualBalance = saved;

        _initWith(lbp, poolInitAmount, poolInitAmount);

        vault.manualSetStaticSwapFeePercentage(lbp, MIN_WEIGHTED_SWAP_FEE);
    }

    function _warpIntoSale() internal {
        if (block.timestamp <= saleStart) {
            vm.warp(saleStart + 1);
        }
    }

    function _initWith(address lbp, uint256 projectAmount, uint256 reserveAmount) internal {
        uint256[] memory initAmounts = new uint256[](2);
        initAmounts[projectIdx] = projectAmount;
        initAmounts[reserveIdx] = reserveAmount;

        vm.startPrank(bob);
        _initPool(lbp, initAmounts, 0);
        vm.stopPrank();

        approveForPool(IERC20(lbp));
    }

    function _accrueReserve(address lbp, uint256 amountIn) internal returns (uint256 realReserve) {
        _warpIntoSale();

        vm.prank(alice);
        router.swapSingleTokenExactIn(lbp, reserveToken, projectToken, amountIn, 0, MAX_UINT256, false, "");

        realReserve = vault.getCurrentLiveBalances(lbp)[reserveIdx];
    }

    function _sellProjectExactOut(address lbp, uint256 amountOutRaw) internal {
        vm.prank(lp);
        router.swapSingleTokenExactOut(
            lbp,
            projectToken,
            reserveToken,
            amountOutRaw,
            MAX_UINT256,
            MAX_UINT256,
            false,
            ""
        );
    }

    function _fundBuyer() internal {
        deal(address(reserveToken), alice, 1e30);

        vm.startPrank(alice);
        reserveToken.approve(address(permit2), type(uint256).max);
        permit2.approve(address(reserveToken), address(router), type(uint160).max, type(uint48).max);
        vm.stopPrank();
    }

    function _fundSeller() internal {
        deal(address(projectToken), lp, 1e30);

        vm.startPrank(lp);
        projectToken.approve(address(permit2), type(uint256).max);
        permit2.approve(address(projectToken), address(router), type(uint160).max, type(uint48).max);
        vm.stopPrank();
    }

    function _lowestReachableReserveBalance(address lbp) internal returns (uint256 lowest) {
        uint256 lo = minimumTradeAmount;
        uint256 hi = vault.getCurrentLiveBalances(lbp)[projectIdx].mulDown(30e16);
        uint256 chosen;

        for (uint256 i = 0; i < 128 && lo <= hi; ++i) {
            uint256 mid = (lo + hi) / 2;
            uint256 trial = vm.snapshotState();

            bool ok;

            vm.prank(lp);
            try router.swapSingleTokenExactIn(lbp, projectToken, reserveToken, mid, 0, MAX_UINT256, false, "") returns (
                uint256
            ) {
                ok = true;
            } catch {
                ok = false;
            }

            vm.revertToState(trial);

            if (ok) {
                chosen = mid;
                lo = mid + 1;
            } else {
                hi = mid - 1;
            }
        }

        require(chosen != 0, "No sale was admitted");

        vm.prank(lp);
        router.swapSingleTokenExactIn(lbp, projectToken, reserveToken, chosen, 0, MAX_UINT256, false, "");

        lowest = vault.getCurrentLiveBalances(lbp)[reserveIdx];
    }

    function _lowestReachableProjectBalance(address lbp) internal returns (uint256 lowest) {
        uint256 lo = minimumTradeAmount;
        uint256 hi = vault.getCurrentLiveBalances(lbp)[reserveIdx].mulDown(30e16);
        uint256 chosen;

        lowest = type(uint256).max;

        for (uint256 i = 0; i < 128 && lo <= hi; ++i) {
            uint256 mid = (lo + hi) / 2;
            uint256 trial = vm.snapshotState();

            bool ok;
            uint256 resultingBalance;

            vm.prank(alice);
            try router.swapSingleTokenExactIn(lbp, reserveToken, projectToken, mid, 0, MAX_UINT256, false, "") returns (
                uint256
            ) {
                ok = true;
                resultingBalance = vault.getCurrentLiveBalances(lbp)[projectIdx];
            } catch {
                ok = false;
            }

            vm.revertToState(trial);

            if (ok) {
                chosen = mid;
                lowest = resultingBalance;
                lo = mid + 1;
            } else {
                hi = mid - 1;
            }
        }

        require(chosen != 0, "No purchase was admitted");

        vm.prank(alice);
        router.swapSingleTokenExactIn(lbp, reserveToken, projectToken, chosen, 0, MAX_UINT256, false, "");

        lowest = vault.getCurrentLiveBalances(lbp)[projectIdx];
    }

    function _smallestFirstPurchase(address lbp) internal returns (uint256 smallest) {
        uint256 lo = 1;
        uint256 hi = 1e12;
        smallest = hi;

        for (uint256 i = 0; i < 64 && lo <= hi; ++i) {
            uint256 mid = (lo + hi) / 2;
            uint256 trial = vm.snapshotState();

            bool ok;

            vm.prank(alice);
            try router.swapSingleTokenExactIn(lbp, reserveToken, projectToken, mid, 0, MAX_UINT256, false, "") returns (
                uint256
            ) {
                ok = true;
            } catch {
                ok = false;
            }

            vm.revertToState(trial);

            if (ok) {
                smallest = mid;
                hi = mid - 1;
            } else {
                lo = mid + 1;
            }
        }
    }

    function _expectBlocksRedemption(uint256 tokenIndex, uint256 endingBalance) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                LBPCommon.TokenBalanceBlocksRedemption.selector,
                tokenIndex,
                endingBalance,
                minRedeemableBalance
            )
        );
    }

    function _forceBalance(address lbp, uint256 tokenIndex, uint256 balanceScaled18) internal {
        uint256[] memory balances = vault.getCurrentLiveBalances(lbp);
        balances[tokenIndex] = balanceScaled18;

        vault.manualSetPoolBalances(lbp, balances, balances);
    }

    function _ownerCanExit(address lbp) internal returns (bool ok) {
        uint256 snapshotId = vm.snapshotState();

        vm.warp(saleEnd + 1);

        uint256 ownerBpt = IERC20(lbp).balanceOf(bob);

        vm.startPrank(bob);
        IERC20(lbp).approve(address(router), MAX_UINT256);

        try router.removeLiquidityProportional(lbp, ownerBpt, new uint256[](2), false, "") returns (uint256[] memory) {
            ok = true;
        } catch {
            ok = false;
        }
        vm.stopPrank();

        vm.revertToState(snapshotId);
    }
}
