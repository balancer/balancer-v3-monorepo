// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { ILBPool } from "@balancer-labs/v3-interfaces/contracts/pool-weighted/ILBPool.sol";
import "@balancer-labs/v3-interfaces/contracts/pool-weighted/ILBPCommon.sol";
import {
    RemoveLiquidityKind,
    RemoveLiquidityParams
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { FixedPriceLBPoolContractsDeployer } from "./utils/FixedPriceLBPoolContractsDeployer.sol";
import { FixedPriceLBPoolFactory } from "../../contracts/lbp/FixedPriceLBPoolFactory.sol";
import { WeightedLBPTest } from "./utils/WeightedLBPTest.sol";
import { LBPCommon } from "../../contracts/lbp/LBPCommon.sol";
import { BaseLBPTest } from "./utils/BaseLBPTest.sol";
import { IVaultAdmin } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultAdmin.sol";
import { WeightedPool } from "../../contracts/WeightedPool.sol";

contract LBPoolRedeemableRemovalTest is WeightedLBPTest {
    using FixedPoint for uint256;

    uint256 internal constant LOW_PROJECT_WEIGHT = 10e16;
    uint256 internal constant MIN_WEIGHTED_SWAP_FEE = 0.001e16;

    uint256 internal poolMinimumTotalSupply;
    uint256 internal minimumTradeAmount;
    uint256 internal minRedeemableBalance;

    uint256 internal saleStart;
    uint256 internal saleEnd;

    function setUp() public virtual override {
        vaultMockMinTradeAmount = PRODUCTION_MIN_TRADE_AMOUNT;
        super.setUp();

        poolMinimumTotalSupply = vault.getPoolMinimumTotalSupply();
        minimumTradeAmount = vault.getMinimumTradeAmount();
        minRedeemableBalance = poolMinimumTotalSupply + minimumTradeAmount;

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

    function testMaximalBurnIsPermittedAtTheFloorWithNoCarveOut() public {
        address lbp = _buildSeededAtTheFloor();

        assertTrue(_fullyRedeemable(lbp), "The maximal burn is refused at the floor");

        uint256[] memory amountsOut = _remove(lbp, IERC20(lbp).totalSupply() - poolMinimumTotalSupply);

        assertGt(amountsOut[reserveIdx], 0, "The maximal burn paid out no reserve");
        assertEq(IERC20(lbp).totalSupply(), poolMinimumTotalSupply, "Pool tokens are still outstanding");
    }

    function testNearTotalWithdrawalIsRefusedAtTheFloor() public {
        address lbp = _buildSeededAtTheFloor();

        uint256 nearTotal = _burnLeaving(lbp, minimumTradeAmount);
        assertFalse(_removalIsAdmitted(lbp, nearTotal), "The near-total withdrawal is admitted at the floor");

        assertTrue(_fullyRedeemable(lbp), "The full exit is refused at the floor");
    }

    function testNinetyNinePointNineNinePercentWithdrawalIsAdmittedOnAHealthyPool() public {
        address lbp = _buildSeeded(DEFAULT_WEIGHT, true);
        vm.warp(saleEnd + 1);

        uint256 circulating = IERC20(lbp).totalSupply() - poolMinimumTotalSupply;
        uint256 burn = (circulating * 9999) / 10000;

        assertTrue(_removalIsAdmitted(lbp, burn), "A 99.99 percent withdrawal is refused on a healthy pool");

        _remove(lbp, burn);
        assertTrue(_fullyRedeemable(lbp), "The remainder cannot be redeemed after a 99.99 percent withdrawal");
    }

    function testBurnLeavingSubMinimumPoolTokensIsRefusedOnAHealthyPool() public {
        address lbp = _buildSeeded(DEFAULT_WEIGHT, true);
        vm.warp(saleEnd + 1);

        uint256 burn = _burnLeaving(lbp, minimumTradeAmount - 1);

        vm.startPrank(bob);
        IERC20(lbp).approve(address(router), MAX_UINT256);
        vm.expectRevert(
            abi.encodeWithSelector(LBPCommon.RemainingSupplyBlocksRedemption.selector, minimumTradeAmount - 1)
        );
        router.removeLiquidityProportional(lbp, burn, new uint256[](2), false, bytes(""));
        vm.stopPrank();

        assertTrue(
            _removalIsAdmitted(lbp, _burnLeaving(lbp, minimumTradeAmount)),
            "Leaving exactly the minimum trade amount outstanding is refused"
        );
    }

    function testBurnRegionsAtTheFloorAreNonMonotone() public {
        address lbp = _buildSeededAtTheFloor();

        uint256 circulating = IERC20(lbp).totalSupply() - poolMinimumTotalSupply;

        assertTrue(_removalIsAdmitted(lbp, circulating), "The maximal burn is refused");

        assertFalse(_removalIsAdmitted(lbp, _burnLeaving(lbp, 1)), "Leaving one pool token is admitted");
        assertFalse(
            _removalIsAdmitted(lbp, _burnLeaving(lbp, minimumTradeAmount - 1)),
            "Leaving one below the minimum trade amount is admitted"
        );
        assertFalse(
            _removalIsAdmitted(lbp, _burnLeaving(lbp, minimumTradeAmount)),
            "Leaving exactly the minimum trade amount is admitted"
        );

        assertFalse(_removalIsAdmitted(lbp, (circulating * 3) / 4), "Burning three quarters is admitted");
        assertFalse(_removalIsAdmitted(lbp, circulating / 2), "Burning half is admitted");
        assertFalse(_removalIsAdmitted(lbp, circulating / 4), "Burning a quarter is admitted");

        uint256 largestSmallBurn = _largestZeroPayoutBurn(lbp, projectIdx);
        assertGt(largestSmallBurn, minimumTradeAmount, "The band of small burns is empty");
        assertTrue(_removalIsAdmitted(lbp, minimumTradeAmount), "The smallest legal burn is refused");
        assertTrue(_removalIsAdmitted(lbp, largestSmallBurn), "The top of the small-burn band is refused");

        _remove(lbp, largestSmallBurn);
        assertTrue(_fullyRedeemable(lbp), "An admitted partial burn left a state that is not fully redeemable");
    }

    function testSmallBurnsAreAdmittedUntilTheVaultsOwnMinimumApplies() public {
        address lbp = _buildSeededAtTheFloor();

        uint256 totalSupply = IERC20(lbp).totalSupply();
        uint256 blockingBalance = vault.getCurrentLiveBalances(lbp)[projectIdx];
        uint256 largestZeroPayoutBurn = totalSupply / blockingBalance;

        assertGt(largestZeroPayoutBurn, minimumTradeAmount, "The band of small burns is empty");

        assertTrue(_removalIsAdmitted(lbp, minimumTradeAmount), "The smallest legal burn is refused");
        assertTrue(_removalIsAdmitted(lbp, largestZeroPayoutBurn), "The top of the small-burn band is refused");

        assertEq((blockingBalance * (largestZeroPayoutBurn + 1)) / totalSupply, 1, "The boundary is not where it is");

        vm.startPrank(bob);
        IERC20(lbp).approve(address(router), MAX_UINT256);
        vm.expectRevert(IVaultErrors.TradeAmountTooSmall.selector);
        router.removeLiquidityProportional(lbp, largestZeroPayoutBurn + 1, new uint256[](2), false, bytes(""));
        vm.stopPrank();
    }

    function testRemovalPreservesTheRatioUpToRounding() public {
        address lbp = _buildSeeded(LOW_PROJECT_WEIGHT, true);
        vm.warp(saleEnd + 1);

        uint256 totalSupply = IERC20(lbp).totalSupply();
        uint256[] memory balancesBefore = vault.getCurrentLiveBalances(lbp);
        uint256 burn = (totalSupply - poolMinimumTotalSupply) / 3;

        _remove(lbp, burn);

        uint256 remainingSupply = totalSupply - burn;
        uint256[] memory remaining = vault.getCurrentLiveBalances(lbp);

        for (uint256 i = 0; i < 2; ++i) {
            uint256 expected = balancesBefore[i] - (balancesBefore[i] * burn) / totalSupply;

            assertEq(remaining[i], expected, "The removal did not leave what the identity predicts");

            assertGe(remaining[i] * totalSupply, balancesBefore[i] * remainingSupply, "The ratio moved the unsafe way");
        }
    }

    function testNonRedeemablePoolCanStillRemoveWhatTheVaultPermits() public {
        address lbp = _buildSeeded(DEFAULT_WEIGHT, true);
        vm.warp(saleEnd + 1);

        _forceBalance(lbp, projectIdx, minimumTradeAmount);
        assertFalse(_fullyRedeemable(lbp), "The forced state is fully redeemable");

        uint256 zeroPayoutBurn = _largestZeroPayoutBurn(lbp, projectIdx);
        assertGe(zeroPayoutBurn, minimumTradeAmount, "There is no burn the Vault would permit here");

        uint256 reserveBefore = vault.getCurrentLiveBalances(lbp)[reserveIdx];
        uint256[] memory amountsOut = _remove(lbp, zeroPayoutBurn);

        assertGt(amountsOut[reserveIdx], 0, "The partial removal paid out no reserve");
        assertLt(vault.getCurrentLiveBalances(lbp)[reserveIdx], reserveBefore, "The reserve balance did not move");

        for (uint256 i = 0; i < 20; ++i) {
            uint256 burn = _largestZeroPayoutBurn(lbp, projectIdx);
            if (burn < minimumTradeAmount || _removalIsAdmitted(lbp, burn) == false) {
                break;
            }
            _remove(lbp, burn);
        }

        assertLt(
            vault.getCurrentLiveBalances(lbp)[reserveIdx],
            reserveBefore,
            "Repeated removals did not reduce the reserve"
        );

        assertFalse(_fullyRedeemable(lbp), "The partial removal restored full redeemability");
    }

    function testNonRedeemablePoolStillGetsTheVaultsOwnErrors() public {
        address lbp = _buildSeeded(DEFAULT_WEIGHT, true);
        vm.warp(saleEnd + 1);

        _forceBalance(lbp, projectIdx, minimumTradeAmount);

        vm.startPrank(bob);
        IERC20(lbp).approve(address(router), MAX_UINT256);
        vm.expectRevert(IVaultErrors.TradeAmountTooSmall.selector);
        router.removeLiquidityProportional(lbp, minimumTradeAmount - 1, new uint256[](2), false, bytes(""));
        vm.stopPrank();
    }

    function testOverLargeBurnKeepsTheVaultsError() public {
        address lbp = _buildSeeded(DEFAULT_WEIGHT, true);
        vm.warp(saleEnd + 1);

        uint256 tooMuch = IERC20(lbp).totalSupply() - poolMinimumTotalSupply + 1;

        vm.startPrank(bob);
        IERC20(lbp).approve(address(router), MAX_UINT256);
        vm.expectPartialRevert(IERC20Errors.ERC20InsufficientBalance.selector);
        router.removeLiquidityProportional(lbp, tooMuch, new uint256[](2), false, bytes(""));
        vm.stopPrank();
    }

    function testHealthyPoolRemovalsAreUnaffected() public {
        address lbp = _buildSeeded(DEFAULT_WEIGHT, true);
        vm.warp(saleEnd + 1);

        uint256 circulating = IERC20(lbp).totalSupply() - poolMinimumTotalSupply;

        for (uint256 percent = 1; percent <= 100; ++percent) {
            assertTrue(_removalIsAdmitted(lbp, (circulating * percent) / 100), "A healthy-pool withdrawal was refused");
        }
    }

    function testMidSaleRemovalsAreUnaffected() public {
        address lbp = _buildSeeded(LOW_PROJECT_WEIGHT, true);
        _fundBuyer();

        vm.warp(saleStart + 1);
        vm.prank(alice);
        router.swapSingleTokenExactIn(lbp, reserveToken, projectToken, 200e18, 0, MAX_UINT256, false, bytes(""));

        vm.warp(saleEnd + 1);

        uint256 circulating = IERC20(lbp).totalSupply() - poolMinimumTotalSupply;

        for (uint256 percent = 1; percent <= 100; ++percent) {
            assertTrue(_removalIsAdmitted(lbp, (circulating * percent) / 100), "A mid-sale withdrawal was refused");
        }
    }

    function testRepeatedPartialWithdrawalsPreserveFullExit() public {
        address lbp = _buildSeeded(LOW_PROJECT_WEIGHT, true);
        vm.warp(saleEnd + 1);

        for (uint256 i = 0; i < 8; ++i) {
            uint256 circulating = IERC20(lbp).totalSupply() - poolMinimumTotalSupply;

            _remove(lbp, circulating / 2);
            assertTrue(_fullyRedeemable(lbp), "A halving left a state that is not fully redeemable");
        }

        assertTrue(_fullyRedeemable(lbp), "The full exit does not clear after eight halvings");
    }

    function testPreSaleRemovalIsStillAvailable() public {
        address lbp = _buildSeeded(DEFAULT_WEIGHT, true);

        uint256 circulating = IERC20(lbp).totalSupply() - poolMinimumTotalSupply;

        assertTrue(_removalIsAdmitted(lbp, circulating / 4), "A pre-sale correction was refused");
        assertTrue(_removalIsAdmitted(lbp, circulating), "A pre-sale full withdrawal was refused");
    }

    function testInitializingBelowTheSmallestBurnableSupplyIsRefused() public {
        address lbp = _createSeeded(99e16);

        uint256[] memory initAmounts = new uint256[](2);
        initAmounts[projectIdx] = minimumTradeAmount;
        initAmounts[reserveIdx] = 1e24;

        assertLt(1_513_558 - poolMinimumTotalSupply, minimumTradeAmount, "The expected boundary has changed");

        _initExpectingRevert(
            lbp,
            initAmounts,
            abi.encodeWithSelector(LBPCommon.InitialStateBlocksRedemption.selector, 1_513_558)
        );
    }

    function testInitializingWithATokenShareBelowTheMinimumIsRefused() public {
        address lbp = _createSeeded(99e16);

        uint256[] memory initAmounts = new uint256[](2);
        initAmounts[projectIdx] = poolInitAmount;
        initAmounts[reserveIdx] = minimumTradeAmount;

        uint256 expectedSupply = 707_945_784_384_123_750_561;
        uint256 circulating = expectedSupply - poolMinimumTotalSupply;

        assertGt(circulating, minimumTradeAmount, "The expected boundary has changed");
        assertEq((minimumTradeAmount * circulating) / expectedSupply, minimumTradeAmount - 1, "Payout moved");

        _initExpectingRevert(
            lbp,
            initAmounts,
            abi.encodeWithSelector(LBPCommon.InitialStateBlocksRedemption.selector, expectedSupply)
        );
    }

    function testInitializationMintingNoPoolTokensIsRefused() public {
        address lbp = _createSeeded(DEFAULT_WEIGHT);

        uint256[] memory initAmounts = new uint256[](2);
        initAmounts[projectIdx] = poolMinimumTotalSupply + 1;
        initAmounts[reserveIdx] = poolMinimumTotalSupply + 1;

        _initExpectingRevert(
            lbp,
            initAmounts,
            abi.encodeWithSelector(LBPCommon.InitialStateBlocksRedemption.selector, poolMinimumTotalSupply)
        );
    }

    function testInitializingOneUnitAboveTheBoundaryIsAccepted() public {
        address lbp = _createSeeded(99e16);

        uint256[] memory initAmounts = new uint256[](2);
        initAmounts[projectIdx] = poolInitAmount;
        initAmounts[reserveIdx] = minimumTradeAmount + 1;

        _init(lbp, initAmounts);

        vm.warp(saleEnd + 1);
        assertTrue(_fullyRedeemable(lbp), "A pool one unit above the boundary cannot be exited");
    }

    function testOrdinaryInitializationsAreUnaffected() public {
        address balanced = _buildSeeded(DEFAULT_WEIGHT, true);
        address lopsided = _buildSeeded(1e16, true);
        address seedless = _buildSeedless();

        vm.warp(saleEnd + 1);

        assertTrue(_fullyRedeemable(balanced), "A balanced seeded pool cannot be exited");
        assertTrue(_fullyRedeemable(lopsided), "A one percent weight pool cannot be exited");
        assertTrue(_fullyRedeemable(seedless), "A seedless pool cannot be exited");
    }

    function testSeedlessInitializationIsCheckedOnTheRealBalances() public {
        address seedless = _buildSeedless();

        assertEq(vault.getCurrentLiveBalances(seedless)[reserveIdx], 0, "The real reserve is not zero");

        vm.warp(saleEnd + 1);
        assertTrue(_fullyRedeemable(seedless), "A seedless pool with a zero real reserve cannot be exited");
    }

    function testAddFromOneUnitBalanceIsRejected() public {
        address lbp = _buildSeeded(DEFAULT_WEIGHT, true);
        _forceBalance(lbp, projectIdx, 1);

        assertTrue(_fullyRedeemable(lbp), "A one unit balance is not redeemable to begin with");

        uint256 totalSupply = IERC20(lbp).totalSupply();
        uint256 bptOut = totalSupply / 4;

        uint256 amountIn = (1 * bptOut + totalSupply - 1) / totalSupply;
        assertEq(amountIn, 1, "The amount in is not one unit");
        assertLt(amountIn, minimumTradeAmount, "The Vault would not have refused this on its own");

        _addExpectingRevert(
            lbp,
            bptOut,
            abi.encodeWithSelector(LBPCommon.ResultingStateBlocksRedemption.selector, totalSupply + bptOut)
        );

        assertTrue(_fullyRedeemable(lbp), "The refused add changed the pool");
    }

    function testAddToFullyRedeemedPoolMustRemainRedeemable() public {
        address lbp = _createSeeded(DEFAULT_WEIGHT);

        uint256[] memory initAmounts = new uint256[](2);
        initAmounts[projectIdx] = 1e21;
        initAmounts[reserveIdx] = 1e24;
        _init(lbp, initAmounts);

        _remove(lbp, IERC20(lbp).totalSupply() - poolMinimumTotalSupply);

        assertEq(IERC20(lbp).totalSupply(), poolMinimumTotalSupply, "The pool was not fully redeemed");
        assertTrue(_fullyRedeemable(lbp), "A fully redeemed pool should have no outstanding redemption claim");

        uint256[] memory residues = vault.getCurrentLiveBalances(lbp);
        assertEq(residues[projectIdx], 31_623, "The project residue moved");
        assertEq(residues[reserveIdx], 31_622_777, "The reserve residue moved");

        uint256 bptOut = 31_622_522;
        uint256 addedSupply = poolMinimumTotalSupply + bptOut;
        uint256 addedProject = residues[projectIdx] +
            (residues[projectIdx] * bptOut + poolMinimumTotalSupply - 1) /
            poolMinimumTotalSupply;

        assertEq(
            (addedProject * (addedSupply - poolMinimumTotalSupply)) / addedSupply,
            minimumTradeAmount - 1,
            "The add no longer leaves one unit under the minimum"
        );

        _addExpectingRevert(
            lbp,
            bptOut,
            abi.encodeWithSelector(LBPCommon.ResultingStateBlocksRedemption.selector, addedSupply)
        );

        assertTrue(_tryAdd(lbp, 1e21), "A redeemable re-funding was refused");
        assertTrue(_fullyRedeemable(lbp), "The re-funded pool is not fully redeemable");
    }

    function testAdmittedAddsPreserveRedeemability() public {
        uint256[8] memory balances = [uint256(0), 1, 2, 999_999, 1_000_000, 2_000_000, 1e12, 1e21];
        uint256 admitted;

        for (uint256 i = 0; i < balances.length; ++i) {
            for (uint256 j = 0; j < 5; ++j) {
                uint256 snapshotId = vm.snapshotState();

                address lbp = _buildSeeded(DEFAULT_WEIGHT, true);

                if (j % 2 == 0) {
                    _remove(lbp, IERC20(lbp).totalSupply() - poolMinimumTotalSupply);
                } else {
                    _forceBalance(lbp, projectIdx, balances[i]);
                }

                uint256 totalSupply = IERC20(lbp).totalSupply();
                uint256[5] memory adds = [
                    uint256(1),
                    minimumTradeAmount,
                    totalSupply / 1000,
                    totalSupply,
                    totalSupply * 1000
                ];

                if (_fullyRedeemable(lbp) && _tryAdd(lbp, adds[j])) {
                    ++admitted;
                    assertTrue(_fullyRedeemable(lbp), "An admitted add broke full redeemability");
                }

                vm.revertToState(snapshotId);
            }
        }

        assertGt(admitted, 0, "The scan admitted no adds");
    }

    function testAddToNonRedeemablePoolCanRestoreRedeemability() public {
        address lbp = _buildSeeded(DEFAULT_WEIGHT, true);

        _forceBalance(lbp, projectIdx, minimumTradeAmount);
        assertFalse(_fullyRedeemable(lbp), "The forced state is fully redeemable");

        _add(lbp, IERC20(lbp).totalSupply());

        assertTrue(_fullyRedeemable(lbp), "The add did not restore redeemability the pool");
    }

    function testOrdinaryAddsAreUnaffected() public {
        address balanced = _buildSeeded(DEFAULT_WEIGHT, true);
        address lopsided = _buildSeeded(1e16, true);
        address seedless = _buildSeedless();

        _add(balanced, IERC20(balanced).totalSupply() / 2);
        _add(lopsided, IERC20(lopsided).totalSupply() / 2);
        _add(seedless, IERC20(seedless).totalSupply() / 2);

        assertEq(vault.getCurrentLiveBalances(seedless)[reserveIdx], 0, "The seedless real reserve stopped at zero");

        vm.warp(saleEnd + 1);
        assertTrue(_fullyRedeemable(balanced), "A balanced pool cannot be exited after an ordinary add");
        assertTrue(_fullyRedeemable(lopsided), "A one percent weight pool cannot be exited after an ordinary add");
        assertTrue(_fullyRedeemable(seedless), "A seedless pool cannot be exited after an ordinary add");
    }

    function testRepeatedAddsPreserveRedeemabilityAcrossLifecycle() public {
        address lbp = _buildSeeded(LOW_PROJECT_WEIGHT, true);
        _fundBuyer();

        for (uint256 i = 0; i < 4; ++i) {
            _add(lbp, IERC20(lbp).totalSupply() / 3);
        }

        vm.warp(saleStart + 1);
        vm.prank(alice);
        router.swapSingleTokenExactIn(lbp, reserveToken, projectToken, 200e18, 0, MAX_UINT256, false, bytes(""));

        vm.warp(saleEnd + 1);
        uint256 circulating = IERC20(lbp).totalSupply() - poolMinimumTotalSupply;
        _remove(lbp, circulating / 2);

        assertTrue(_fullyRedeemable(lbp), "The pool is not fully redeemable after adds, a swap and a removal");
    }

    function testSplitHoldersCannotIndividuallyExitAtFloor() public {
        address lbp = _buildSeededAtTheFloor();

        uint256 circulating = IERC20(lbp).totalSupply() - poolMinimumTotalSupply;

        vm.prank(bob);
        IERC20(lbp).transfer(alice, circulating / 100);

        uint256 majority = IERC20(lbp).balanceOf(bob);

        uint256[] memory balances = vault.getCurrentLiveBalances(lbp);
        uint256 totalSupply = IERC20(lbp).totalSupply();
        assertGe(majority, minimumTradeAmount, "The majority burn is below the Vault's own minimum");
        assertGe((balances[projectIdx] * majority) / totalSupply, minimumTradeAmount, "Project payout is too small");
        assertGe((balances[reserveIdx] * majority) / totalSupply, minimumTradeAmount, "Reserve payout is too small");

        for (uint256 percent = 1; percent <= 100; ++percent) {
            assertFalse(_removalIsAdmitted(lbp, (majority * percent) / 100), "A majority fraction was admitted");
        }

        uint256 minority = IERC20(lbp).balanceOf(alice);

        vm.prank(alice);
        IERC20(lbp).transfer(bob, minority);
        assertTrue(_fullyRedeemable(lbp), "The exit does not clear once the holders consolidate");
    }

    function testSubMinimumBptRemainderRejectsOwnerWithdrawal() public {
        address lbp = _buildSeeded(DEFAULT_WEIGHT, true);
        vm.warp(saleEnd + 1);

        vm.prank(bob);
        IERC20(lbp).transfer(alice, minimumTradeAmount - 1);

        uint256 ownerPosition = IERC20(lbp).balanceOf(bob);

        vm.startPrank(bob);
        IERC20(lbp).approve(address(router), MAX_UINT256);
        vm.expectRevert(
            abi.encodeWithSelector(LBPCommon.RemainingSupplyBlocksRedemption.selector, minimumTradeAmount - 1)
        );
        router.removeLiquidityProportional(lbp, ownerPosition, new uint256[](2), false, bytes(""));
        vm.stopPrank();

        assertTrue(_removalIsAdmitted(lbp, ownerPosition - 1), "Stranding one pool token does not clear it");
    }

    function testFloorStateRejectsNonRedeemablePartialBurns() public {
        address lbp = _buildSeededAtTheFloor();

        assertEq(
            vault.getCurrentLiveBalances(lbp)[projectIdx],
            minRedeemableBalance,
            "The buyer did not stop on the swap-side floor"
        );

        uint256 circulating = IERC20(lbp).totalSupply() - poolMinimumTotalSupply;
        uint256 refused;
        for (uint256 percent = 50; percent < 100; ++percent) {
            if (_removalIsAdmitted(lbp, (circulating * percent) / 100) == false) {
                ++refused;
            }
        }
        assertEq(refused, 50, "Some fraction of the circulating supply is still non-redeemable");

        uint256 nonRedeemableBurn = _burnLeavingNonRedeemableRemainder(lbp, projectIdx);
        vm.startPrank(bob);
        IERC20(lbp).approve(address(router), MAX_UINT256);
        _expectRemainingBalanceBlocksRedemption(lbp, nonRedeemableBurn, projectIdx);
        router.removeLiquidityProportional(lbp, nonRedeemableBurn, new uint256[](2), false, bytes(""));
        vm.stopPrank();

        assertTrue(_fullyRedeemable(lbp), "The full exit does not clear from the floor");
    }

    function testSwapThenSafePartialRemovalStaysRedeemable() public {
        address lbp = _buildSeeded(LOW_PROJECT_WEIGHT, true);
        _fundBuyer();

        vm.warp(saleStart + 1);
        vm.prank(alice);
        router.swapSingleTokenExactIn(lbp, reserveToken, projectToken, 200e18, 0, MAX_UINT256, false, bytes(""));

        vm.warp(saleEnd + 1);

        uint256 circulating = IERC20(lbp).totalSupply() - poolMinimumTotalSupply;
        _remove(lbp, circulating / 2);

        assertTrue(_fullyRedeemable(lbp), "The pool is not fully redeemable after a swap and a partial removal");
    }

    function testPreSaleRemovalThenSwapStaysRedeemable() public {
        address lbp = _buildSeeded(LOW_PROJECT_WEIGHT, true);
        _fundBuyer();

        uint256 circulating = IERC20(lbp).totalSupply() - poolMinimumTotalSupply;
        _remove(lbp, circulating / 2);

        vm.warp(saleStart + 1);
        vm.prank(alice);
        router.swapSingleTokenExactIn(lbp, reserveToken, projectToken, 100e18, 0, MAX_UINT256, false, bytes(""));

        vm.warp(saleEnd + 1);
        assertTrue(_fullyRedeemable(lbp), "The pool is not fully redeemable after a pre-sale removal and a swap");
    }

    function testDirectVaultRemovalAppliesRedeemabilityCheck() public {
        address lbp = _buildSeededAtTheFloor();

        vm.prank(bob);
        IERC20(lbp).approve(address(this), MAX_UINT256);

        uint256 circulating = IERC20(lbp).totalSupply() - poolMinimumTotalSupply;
        bytes memory nonRedeemableCall = abi.encodeCall(
            this.removeDirectlyHook,
            (lbp, _burnLeavingNonRedeemableRemainder(lbp, projectIdx))
        );
        bytes memory maximalCall = abi.encodeCall(this.removeDirectlyHook, (lbp, circulating));

        vm.expectPartialRevert(LBPCommon.RemainingBalanceBlocksRedemption.selector);
        vault.unlock(nonRedeemableCall);

        vault.unlock(maximalCall);
        assertEq(IERC20(lbp).totalSupply(), poolMinimumTotalSupply, "The direct maximal burn did not go through");
    }

    function removeDirectlyHook(address lbp, uint256 burn) external {
        (, uint256[] memory amountsOut, ) = vault.removeLiquidity(
            RemoveLiquidityParams({
                pool: lbp,
                from: bob,
                maxBptAmountIn: burn,
                minAmountsOut: new uint256[](2),
                kind: RemoveLiquidityKind.PROPORTIONAL,
                userData: bytes("")
            })
        );

        IERC20[] memory tokens = vault.getPoolTokens(lbp);
        for (uint256 i = 0; i < tokens.length; ++i) {
            if (amountsOut[i] > 0) {
                vault.sendTo(tokens[i], bob, amountsOut[i]);
            }
        }
    }

    function testQueryReportsTheSameRefusal() public {
        address lbp = _buildSeededAtTheFloor();

        uint256 circulating = IERC20(lbp).totalSupply() - poolMinimumTotalSupply;
        uint256 nonRedeemableBurn = _burnLeavingNonRedeemableRemainder(lbp, projectIdx);

        _prankStaticCall();
        vm.expectPartialRevert(LBPCommon.RemainingBalanceBlocksRedemption.selector);
        router.queryRemoveLiquidityProportional(lbp, nonRedeemableBurn, bob, bytes(""));

        _prankStaticCall();
        uint256[] memory amountsOut = router.queryRemoveLiquidityProportional(lbp, circulating, bob, bytes(""));
        assertGt(amountsOut[reserveIdx], 0, "The maximal burn returns no reserve");
    }

    function testSeedlessRemovalUsesTheRealReserveNotTheAugmentedOne() public {
        address lbp = _buildSeedless();
        _fundBuyer();

        vm.warp(saleStart + 1);
        vm.prank(alice);
        router.swapSingleTokenExactIn(lbp, reserveToken, projectToken, 100e18, 0, MAX_UINT256, false, bytes(""));

        vm.warp(saleEnd + 1);
        _forceBalance(lbp, reserveIdx, minRedeemableBalance);

        (, uint256 virtualReserve) = ILBPool(lbp).getReserveTokenVirtualBalance();
        assertGt(virtualReserve, minRedeemableBalance, "The virtual balance is not large enough for this test");

        uint256 nonRedeemableBurn = _burnLeavingNonRedeemableRemainder(lbp, reserveIdx);

        vm.startPrank(bob);
        IERC20(lbp).approve(address(router), MAX_UINT256);
        _expectRemainingBalanceBlocksRedemption(lbp, nonRedeemableBurn, reserveIdx);
        router.removeLiquidityProportional(lbp, nonRedeemableBurn, new uint256[](2), false, bytes(""));
        vm.stopPrank();

        assertTrue(_fullyRedeemable(lbp), "The full exit does not clear on a seedless pool at the floor");
    }

    function testSeedlessWithAZeroRealReserveIsFullyRedeemable() public {
        address lbp = _buildSeedless();
        vm.warp(saleEnd + 1);

        assertEq(vault.getCurrentLiveBalances(lbp)[reserveIdx], 0, "The real reserve is not zero");
        assertTrue(_fullyRedeemable(lbp), "A seedless pool with a zero real reserve cannot be exited");

        uint256 circulating = IERC20(lbp).totalSupply() - poolMinimumTotalSupply;
        assertTrue(_removalIsAdmitted(lbp, circulating / 2), "A partial withdrawal against a zero reserve is refused");
    }

    function testNonEighteenDecimalPoolIsGovernedByTheInheritedMinimum() public {
        uint256 saved = reserveTokenVirtualBalanceNon18;
        reserveTokenVirtualBalanceNon18 = 0;

        (address lbp, ) = _createLBPoolWithCustomWeightsNon18(
            address(0),
            DEFAULT_WEIGHT,
            FixedPoint.ONE - DEFAULT_WEIGHT,
            DEFAULT_WEIGHT,
            FixedPoint.ONE - DEFAULT_WEIGHT,
            uint32(saleStart),
            uint32(saleEnd),
            true
        );

        reserveTokenVirtualBalanceNon18 = saved;

        uint256[] memory initAmounts = new uint256[](2);
        initAmounts[projectIdxNon18] = poolInitAmountsNon18[projectIdxNon18];
        initAmounts[reserveIdxNon18] = poolInitAmountsNon18[reserveIdxNon18];

        vm.startPrank(bob);
        _initPool(lbp, initAmounts, 0);
        vm.stopPrank();

        approveForPool(IERC20(lbp));

        uint256 inherited = WeightedPool(lbp).getMinTokenBalances()[projectIdxNon18];
        assertGt(
            inherited,
            ILBPCommon(lbp).getMinRedeemableBalance(),
            "The inherited minimum is not the larger of the two at eight decimals"
        );

        vm.warp(saleEnd + 1);
        assertTrue(_fullyRedeemable(lbp), "The full withdrawal is refused on the non-eighteen-decimal pool");
    }

    function testRecoveryWithdrawalCanLeaveNonRedeemableState() public {
        address lbp = _buildSeeded(LOW_PROJECT_WEIGHT, true);
        vm.warp(saleEnd + 1);
        approveForPool(IERC20(lbp));

        assertTrue(_fullyRedeemable(lbp), "The pool is not redeemable before the recovery withdrawal");

        authorizer.grantRole(vault.getActionId(IVaultAdmin.enableRecoveryMode.selector), admin);
        vm.prank(admin);
        vault.enableRecoveryMode(lbp);

        uint256 burn = IERC20(lbp).balanceOf(bob) - (minimumTradeAmount - 1);
        vm.prank(bob);
        router.removeLiquidityRecovery(lbp, burn, new uint256[](2));

        authorizer.grantRole(vault.getActionId(IVaultAdmin.disableRecoveryMode.selector), admin);
        vm.prank(admin);
        vault.disableRecoveryMode(lbp);

        uint256 circulating = IERC20(lbp).totalSupply() - poolMinimumTotalSupply;
        assertGt(circulating, 0, "No circulating supply remains");
        assertLt(circulating, minimumTradeAmount, "The remaining supply is not inside the band");
        assertFalse(_fullyRedeemable(lbp), "The recovery withdrawal left a fully redeemable state");
    }

    function testFullyRedeemedPoolCanStillTradeWithoutCirculatingSupply() public {
        uint256 saved = reserveTokenVirtualBalance;
        reserveTokenVirtualBalance = 1e18;

        (address lbp, ) = _createLBPoolWithCustomWeights(
            address(0),
            DEFAULT_WEIGHT,
            FixedPoint.ONE - DEFAULT_WEIGHT,
            DEFAULT_WEIGHT,
            FixedPoint.ONE - DEFAULT_WEIGHT,
            uint32(saleStart),
            uint32(saleEnd),
            true
        );

        reserveTokenVirtualBalance = saved;

        uint256[] memory initAmounts = new uint256[](2);
        initAmounts[projectIdx] = 1e24;

        _initWith(lbp, initAmounts[projectIdx], 0);
        vault.manualSetStaticSwapFeePercentage(lbp, MIN_WEIGHTED_SWAP_FEE);
        _fundBuyer();

        _remove(lbp, IERC20(lbp).totalSupply() - poolMinimumTotalSupply);
        assertEq(IERC20(lbp).totalSupply(), poolMinimumTotalSupply, "Something is still circulating");

        vm.warp(saleStart + 1);

        uint256 reserveBefore = vault.getCurrentLiveBalances(lbp)[reserveIdx];
        vm.prank(alice);
        router.swapSingleTokenExactIn(lbp, reserveToken, projectToken, 1e17, 0, MAX_UINT256, false, bytes(""));

        assertGt(
            vault.getCurrentLiveBalances(lbp)[reserveIdx],
            reserveBefore,
            "The fully redeemed pool did not accept the purchase"
        );
        assertEq(IERC20(lbp).totalSupply() - poolMinimumTotalSupply, 0, "A claim on the reserve appeared");
    }

    function _burnLeaving(address lbp, uint256 remainingCirculating) internal view returns (uint256) {
        return IERC20(lbp).totalSupply() - poolMinimumTotalSupply - remainingCirculating;
    }

    function _largestRoundingToZeroRemainder(address lbp, uint256 tokenIndex) internal view returns (uint256) {
        uint256 totalSupply = IERC20(lbp).totalSupply();
        uint256 balance = vault.getCurrentLiveBalances(lbp)[tokenIndex];

        return totalSupply / balance - poolMinimumTotalSupply;
    }

    function _burnLeavingNonRedeemableRemainder(address lbp, uint256 tokenIndex) internal view returns (uint256) {
        return _burnLeaving(lbp, _largestRoundingToZeroRemainder(lbp, tokenIndex) + 1);
    }

    function _largestZeroPayoutBurn(address lbp, uint256 tokenIndex) internal view returns (uint256) {
        uint256 totalSupply = IERC20(lbp).totalSupply();
        uint256 balance = vault.getCurrentLiveBalances(lbp)[tokenIndex];

        return (totalSupply - 1) / balance;
    }

    function _removalIsAdmitted(address lbp, uint256 burn) internal returns (bool ok) {
        uint256 snapshotId = vm.snapshotState();

        vm.startPrank(bob);
        IERC20(lbp).approve(address(router), MAX_UINT256);
        try router.removeLiquidityProportional(lbp, burn, new uint256[](2), false, bytes("")) returns (
            uint256[] memory
        ) {
            ok = true;
        } catch {
            ok = false;
        }
        vm.stopPrank();

        vm.revertToState(snapshotId);
    }

    function _remove(address lbp, uint256 burn) internal returns (uint256[] memory amountsOut) {
        vm.startPrank(bob);
        IERC20(lbp).approve(address(router), MAX_UINT256);
        amountsOut = router.removeLiquidityProportional(lbp, burn, new uint256[](2), false, bytes(""));
        vm.stopPrank();
    }

    function _expectRemainingBalanceBlocksRedemption(address lbp, uint256 burn, uint256 tokenIndex) internal {
        uint256 totalSupply = IERC20(lbp).totalSupply();
        uint256 balance = vault.getCurrentLiveBalances(lbp)[tokenIndex];
        uint256 remainingBalance = balance - (balance * burn) / totalSupply;

        vm.expectRevert(
            abi.encodeWithSelector(
                LBPCommon.RemainingBalanceBlocksRedemption.selector,
                tokenIndex,
                remainingBalance,
                totalSupply - burn
            )
        );
    }

    function _fullyRedeemable(address lbp) internal returns (bool ok) {
        return _removalIsAdmitted(lbp, IERC20(lbp).totalSupply() - poolMinimumTotalSupply);
    }

    function _forceBalance(address lbp, uint256 tokenIndex, uint256 balanceScaled18) internal {
        uint256[] memory balances = vault.getCurrentLiveBalances(lbp);
        balances[tokenIndex] = balanceScaled18;

        vault.manualSetPoolBalances(lbp, balances, balances);
    }

    function _initExpectingRevert(address lbp, uint256[] memory amounts, bytes memory expectedError) internal {
        (IERC20[] memory tokens, , , ) = vault.getPoolTokenInfo(lbp);

        vm.startPrank(bob);
        vm.expectRevert(expectedError);
        router.initialize(lbp, tokens, amounts, 0, false, bytes(""));
        vm.stopPrank();
    }

    function _wideMaxAmountsIn() internal pure returns (uint256[] memory maxAmountsIn) {
        maxAmountsIn = new uint256[](2);
        maxAmountsIn[0] = MAX_UINT128;
        maxAmountsIn[1] = MAX_UINT128;
    }

    function _fundOwner() internal {
        deal(address(projectToken), bob, 1e30);
        deal(address(reserveToken), bob, 1e30);
    }

    function _add(address lbp, uint256 bptAmountOut) internal {
        _fundOwner();
        uint256[] memory maxAmountsIn = _wideMaxAmountsIn();

        vm.startPrank(bob);
        router.addLiquidityProportional(lbp, maxAmountsIn, bptAmountOut, false, bytes(""));
        vm.stopPrank();
    }

    function _addExpectingRevert(address lbp, uint256 bptAmountOut, bytes memory expectedError) internal {
        _fundOwner();
        uint256[] memory maxAmountsIn = _wideMaxAmountsIn();

        vm.startPrank(bob);
        vm.expectRevert(expectedError);
        router.addLiquidityProportional(lbp, maxAmountsIn, bptAmountOut, false, bytes(""));
        vm.stopPrank();
    }

    function _tryAdd(address lbp, uint256 bptAmountOut) internal returns (bool ok) {
        _fundOwner();
        uint256[] memory maxAmountsIn = _wideMaxAmountsIn();

        vm.startPrank(bob);
        try router.addLiquidityProportional(lbp, maxAmountsIn, bptAmountOut, false, bytes("")) returns (
            uint256[] memory
        ) {
            ok = true;
        } catch {
            ok = false;
        }
        vm.stopPrank();
    }

    function _init(address lbp, uint256[] memory amounts) internal {
        (IERC20[] memory tokens, , , ) = vault.getPoolTokenInfo(lbp);

        vm.startPrank(bob);
        router.initialize(lbp, tokens, amounts, 0, false, bytes(""));
        vm.stopPrank();

        approveForPool(IERC20(lbp));
    }

    function _createSeeded(uint256 projectWeight) internal returns (address lbp) {
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
            true
        );

        reserveTokenVirtualBalance = saved;

        deal(address(projectToken), bob, 1e30);
        deal(address(reserveToken), bob, 1e30);
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

    function _buildSeedless() internal returns (address lbp) {
        uint256 saved = reserveTokenVirtualBalance;
        reserveTokenVirtualBalance = poolInitAmount;

        (lbp, ) = _createLBPoolWithCustomWeights(
            address(0),
            LOW_PROJECT_WEIGHT,
            FixedPoint.ONE - LOW_PROJECT_WEIGHT,
            LOW_PROJECT_WEIGHT,
            FixedPoint.ONE - LOW_PROJECT_WEIGHT,
            uint32(saleStart),
            uint32(saleEnd),
            false
        );

        reserveTokenVirtualBalance = saved;

        _initWith(lbp, poolInitAmount, 0);
        vault.manualSetStaticSwapFeePercentage(lbp, MIN_WEIGHTED_SWAP_FEE);
    }

    function _buildSeededAtTheFloor() internal returns (address lbp) {
        lbp = _buildSeeded(LOW_PROJECT_WEIGHT, true);

        vm.warp(saleEnd + 1);
        _forceBalance(lbp, projectIdx, minRedeemableBalance);
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

    function _fundBuyer() internal {
        deal(address(reserveToken), alice, 1e30);

        vm.startPrank(alice);
        reserveToken.approve(address(permit2), type(uint256).max);
        permit2.approve(address(reserveToken), address(router), type(uint160).max, type(uint48).max);
        vm.stopPrank();
    }
}

contract FixedPriceLBPoolRedeemableRemovalTest is BaseLBPTest, FixedPriceLBPoolContractsDeployer {
    using FixedPoint for uint256;

    uint256 internal constant RATE = FixedPoint.ONE;

    FixedPriceLBPoolFactory internal lbPoolFactory;

    uint256 internal poolMinimumTotalSupply;
    uint256 internal minimumTradeAmount;
    uint256 internal minRedeemableBalance;

    function setUp() public virtual override {
        vaultMockMinTradeAmount = PRODUCTION_MIN_TRADE_AMOUNT;
        super.setUp();

        poolMinimumTotalSupply = vault.getPoolMinimumTotalSupply();
        minimumTradeAmount = vault.getMinimumTradeAmount();
        minRedeemableBalance = poolMinimumTotalSupply + minimumTradeAmount;
    }

    function createPoolFactory() internal virtual override returns (address) {
        lbPoolFactory = deployFixedPriceLBPoolFactory(
            IVault(address(vault)),
            365 days,
            factoryVersion,
            poolVersion,
            address(router)
        );
        vm.label(address(lbPoolFactory), "Fixed Price LB pool factory");

        return address(lbPoolFactory);
    }

    function createPool() internal virtual override returns (address newPool, bytes memory poolArgs) {
        newPool = _create(swapFee);
        poolArgs = bytes("");
    }

    function initPool() internal virtual override {
        uint256[] memory initAmounts = new uint256[](2);
        initAmounts[projectIdx] = poolInitAmount;

        vm.startPrank(bob);
        _initPool(pool, initAmounts, 0);
        vm.stopPrank();
    }

    function testBothRatiosAreBelowOneMidSale() public {
        _warpIntoSale();

        vm.prank(alice);
        router.swapSingleTokenExactIn(pool, reserveToken, projectToken, 400e18, 0, MAX_UINT256, false, bytes(""));

        uint256 totalSupply = IERC20(pool).totalSupply();
        uint256[] memory balances = vault.getCurrentLiveBalances(pool);

        assertLt(balances[projectIdx], totalSupply, "The project ratio is not below one");
        assertLt(balances[reserveIdx], totalSupply, "The reserve ratio is not below one");
    }

    function testMaximalBurnIsPermittedAtTheFloor() public {
        _buildAtTheFloor();

        assertTrue(_fullyRedeemable(pool), "The maximal burn is refused at the floor");
    }

    function testNearTotalWithdrawalIsRefusedAtTheFloor() public {
        _buildAtTheFloor();

        uint256 nearTotal = _burnLeaving(pool, minimumTradeAmount);

        assertFalse(_removalIsAdmitted(pool, nearTotal), "The near-total withdrawal is admitted at the floor");
        assertTrue(_fullyRedeemable(pool), "The full exit is refused at the floor");
    }

    function testNonRedeemablePartialBurnsAreRefusedAtFloor() public {
        _buildAtTheFloor();

        uint256 circulating = IERC20(pool).totalSupply() - poolMinimumTotalSupply;

        assertFalse(_removalIsAdmitted(pool, circulating / 2), "Burning half is admitted at the floor");
        assertFalse(_removalIsAdmitted(pool, (circulating * 3) / 5), "Burning three fifths is admitted at the floor");
        assertFalse(
            _removalIsAdmitted(pool, _burnLeaving(pool, minimumTradeAmount - 1)),
            "Leaving sub-minimum pool tokens is admitted"
        );
    }

    function testHealthyPoolRemovalsAreUnaffected() public {
        _warpPastSale();

        uint256 circulating = IERC20(pool).totalSupply() - poolMinimumTotalSupply;

        for (uint256 percent = 1; percent <= 100; ++percent) {
            assertTrue(_removalIsAdmitted(pool, (circulating * percent) / 100), "A healthy withdrawal was refused");
        }
    }

    function testRepeatedPartialWithdrawalsCompose() public {
        _warpIntoSale();

        vm.prank(alice);
        router.swapSingleTokenExactIn(pool, reserveToken, projectToken, 400e18, 0, MAX_UINT256, false, bytes(""));

        _warpPastSale();

        for (uint256 i = 0; i < 8; ++i) {
            uint256 circulating = IERC20(pool).totalSupply() - poolMinimumTotalSupply;

            _remove(pool, circulating / 2);
            assertTrue(_fullyRedeemable(pool), "A halving left a state that is not fully redeemable");
        }
    }

    function testPoolFundedBelowTheMinimumBurnIsRefused() public {
        address smallPool = _create(swapFee);

        uint256[] memory initAmounts = new uint256[](2);
        initAmounts[projectIdx] = minRedeemableBalance - 1;

        (IERC20[] memory tokens, , , ) = vault.getPoolTokenInfo(smallPool);

        vm.startPrank(bob);
        vm.expectPartialRevert(LBPCommon.InitialStateBlocksRedemption.selector);
        router.initialize(smallPool, tokens, initAmounts, 0, false, bytes(""));
        vm.stopPrank();
    }

    function testNonRedeemablePoolCanStillRemoveWhatTheVaultPermits() public {
        _warpIntoSale();

        vm.prank(alice);
        router.swapSingleTokenExactIn(pool, reserveToken, projectToken, 400e18, 0, MAX_UINT256, false, bytes(""));

        _warpPastSale();
        _forceBalance(pool, projectIdx, minimumTradeAmount);

        assertFalse(_fullyRedeemable(pool), "The forced state is fully redeemable");

        uint256 zeroPayoutBurn = _largestZeroPayoutBurn(pool, projectIdx);
        uint256 reserveBefore = vault.getCurrentLiveBalances(pool)[reserveIdx];

        uint256[] memory amountsOut = _remove(pool, zeroPayoutBurn);

        assertGt(amountsOut[reserveIdx], 0, "The partial removal paid out no reserve");
        assertLt(vault.getCurrentLiveBalances(pool)[reserveIdx], reserveBefore, "The reserve did not move");
        assertFalse(_fullyRedeemable(pool), "The partial removal restored full redeemability");
    }

    function testAddIntoAFullyRedeemedPoolIsRefusedBelowTheBoundary() public {
        _remove(pool, IERC20(pool).totalSupply() - poolMinimumTotalSupply);

        uint256[] memory residues = vault.getCurrentLiveBalances(pool);
        assertEq(residues[projectIdx], poolMinimumTotalSupply, "Unexpected project residue after the full exit");
        assertEq(IERC20(pool).totalSupply(), poolMinimumTotalSupply, "Something is still circulating");

        uint256[] memory maxAmountsIn = new uint256[](2);
        maxAmountsIn[0] = MAX_UINT128;
        maxAmountsIn[1] = MAX_UINT128;

        uint256 tooSmall = minimumTradeAmount - 1;
        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(LBPCommon.ResultingStateBlocksRedemption.selector, poolMinimumTotalSupply + tooSmall)
        );
        router.addLiquidityProportional(pool, maxAmountsIn, tooSmall, false, bytes(""));

        vm.prank(bob);
        router.addLiquidityProportional(pool, maxAmountsIn, minimumTradeAmount, false, bytes(""));

        _warpPastSale();
        assertTrue(_fullyRedeemable(pool), "The pool is not redeemable after the admitted add");
    }

    function testRedeemabilityCheckUsesFullPrecisionArithmetic() public {
        // A rate above one gives a pool token supply above 128 bits from a project amount the Vault can hold.
        address lbp = _create(swapFee, 1e33);

        uint256[] memory initAmounts = new uint256[](2);
        initAmounts[projectIdx] = 1e24;

        vm.startPrank(bob);
        _initPool(lbp, initAmounts, 0);
        vm.stopPrank();

        assertGt(IERC20(lbp).totalSupply(), 2 ** 128, "The pool token supply does not exceed 128 bits");

        // Buy enough project tokens that the reserve balance times the circulating supply exceeds 256 bits.
        _warpIntoSale();
        deal(address(reserveToken), alice, 12e37);

        vm.prank(alice);
        router.swapSingleTokenExactIn(lbp, reserveToken, projectToken, 12e37, 0, MAX_UINT256, false, bytes(""));

        uint256 totalSupply = IERC20(lbp).totalSupply();
        uint256[] memory balances = vault.getCurrentLiveBalances(lbp);
        assertGt(
            balances[reserveIdx],
            type(uint256).max / (totalSupply - poolMinimumTotalSupply),
            "Reserve balance times circulating supply fits in 256 bits"
        );

        // A partial removal whose own products fit is admitted, and it leaves a fully redeemable state.
        _warpPastSale();
        uint256 burn = totalSupply / 10;
        uint256[] memory amountsOut = _remove(lbp, burn);

        assertEq(amountsOut[projectIdx], (balances[projectIdx] * burn) / totalSupply, "Wrong project amount out");
        assertEq(amountsOut[reserveIdx], (balances[reserveIdx] * burn) / totalSupply, "Wrong reserve amount out");
        assertTrue(_fullyRedeemable(lbp), "The remaining state is not fully redeemable");
    }

    function _create(uint256 staticSwapFee) internal returns (address newPool) {
        return _create(staticSwapFee, RATE);
    }

    function _create(uint256 staticSwapFee, uint256 rate) internal returns (address newPool) {
        LBPCommonParams memory lbpCommonParams = LBPCommonParams({
            name: "FixedPriceLBPool",
            symbol: "FLBP",
            owner: bob,
            projectToken: projectToken,
            reserveToken: reserveToken,
            startTime: uint32(block.timestamp + DEFAULT_START_OFFSET),
            endTime: uint32(block.timestamp + DEFAULT_END_OFFSET),
            blockProjectTokenSwapsIn: true
        });

        newPool = lbPoolFactory.create(lbpCommonParams, rate, staticSwapFee, bytes32(_saltCounter++), address(0));
    }

    function _buildAtTheFloor() internal {
        _warpIntoSale();

        uint256 amountOut = vault.getCurrentLiveBalances(pool)[projectIdx] - minRedeemableBalance;

        vm.prank(alice);
        router.swapSingleTokenExactOut(
            pool,
            reserveToken,
            projectToken,
            amountOut,
            MAX_UINT256,
            MAX_UINT256,
            false,
            bytes("")
        );

        _warpPastSale();
    }

    function _burnLeaving(address lbp, uint256 remainingCirculating) internal view returns (uint256) {
        return IERC20(lbp).totalSupply() - poolMinimumTotalSupply - remainingCirculating;
    }

    function _largestRoundingToZeroRemainder(address lbp, uint256 tokenIndex) internal view returns (uint256) {
        uint256 totalSupply = IERC20(lbp).totalSupply();
        uint256 balance = vault.getCurrentLiveBalances(lbp)[tokenIndex];

        return totalSupply / balance - poolMinimumTotalSupply;
    }

    function _largestZeroPayoutBurn(address lbp, uint256 tokenIndex) internal view returns (uint256) {
        uint256 totalSupply = IERC20(lbp).totalSupply();
        uint256 balance = vault.getCurrentLiveBalances(lbp)[tokenIndex];

        return (totalSupply - 1) / balance;
    }

    function _removalIsAdmitted(address lbp, uint256 burn) internal returns (bool ok) {
        uint256 snapshotId = vm.snapshotState();

        vm.startPrank(bob);
        IERC20(lbp).approve(address(router), MAX_UINT256);
        try router.removeLiquidityProportional(lbp, burn, new uint256[](2), false, bytes("")) returns (
            uint256[] memory
        ) {
            ok = true;
        } catch {
            ok = false;
        }
        vm.stopPrank();

        vm.revertToState(snapshotId);
    }

    function _remove(address lbp, uint256 burn) internal returns (uint256[] memory amountsOut) {
        vm.startPrank(bob);
        IERC20(lbp).approve(address(router), MAX_UINT256);
        amountsOut = router.removeLiquidityProportional(lbp, burn, new uint256[](2), false, bytes(""));
        vm.stopPrank();
    }

    function _fullyRedeemable(address lbp) internal returns (bool ok) {
        return _removalIsAdmitted(lbp, IERC20(lbp).totalSupply() - poolMinimumTotalSupply);
    }

    function _forceBalance(address lbp, uint256 tokenIndex, uint256 balanceScaled18) internal {
        uint256[] memory balances = vault.getCurrentLiveBalances(lbp);
        balances[tokenIndex] = balanceScaled18;

        vault.manualSetPoolBalances(lbp, balances, balances);
    }

    function _warpIntoSale() internal {
        vm.warp(block.timestamp + DEFAULT_START_OFFSET + 1);
    }

    function _warpPastSale() internal {
        vm.warp(block.timestamp + DEFAULT_END_OFFSET + 1);
    }
}
