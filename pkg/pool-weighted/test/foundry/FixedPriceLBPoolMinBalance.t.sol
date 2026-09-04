// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { stdError } from "forge-std/StdError.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IFixedPriceLBPool } from "@balancer-labs/v3-interfaces/contracts/pool-weighted/IFixedPriceLBPool.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v3-interfaces/contracts/pool-weighted/ILBPCommon.sol";

import { ERC20TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC20TestToken.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { FixedPriceLBPoolContractsDeployer } from "./utils/FixedPriceLBPoolContractsDeployer.sol";
import { FixedPriceLBPoolFactory } from "../../contracts/lbp/FixedPriceLBPoolFactory.sol";
import { LBPCommon } from "../../contracts/lbp/LBPCommon.sol";
import { BaseLBPTest } from "./utils/BaseLBPTest.sol";

contract FixedPriceLBPoolMinBalanceTest is BaseLBPTest, FixedPriceLBPoolContractsDeployer {
    using FixedPoint for uint256;

    uint256 internal constant RATE = FixedPoint.ONE;

    FixedPriceLBPoolFactory internal lbPoolFactory;

    uint256 internal minRedeemableBalance;
    uint256 internal minimumTradeAmount;

    function setUp() public virtual override {
        vaultMockMinTradeAmount = PRODUCTION_MIN_TRADE_AMOUNT;
        super.setUp();

        minimumTradeAmount = vault.getMinimumTradeAmount();
        minRedeemableBalance = vault.getPoolMinimumTotalSupply() + minimumTradeAmount;
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
        newPool = _create(projectToken, reserveToken, swapFee);
        poolArgs = bytes("");
    }

    function initPool() internal virtual override {
        uint256[] memory initAmounts = new uint256[](2);
        initAmounts[projectIdx] = poolInitAmount;

        vm.startPrank(bob);
        _initPool(pool, initAmounts, 0);
        vm.stopPrank();
    }

    function testThresholdIsTightAtTheSmallestRedeemableSupply() public view {
        uint256 poolMinimumTotalSupply = vault.getPoolMinimumTotalSupply();
        uint256 smallestRedeemableSupply = poolMinimumTotalSupply + minimumTradeAmount;
        uint256 circulating = smallestRedeemableSupply - poolMinimumTotalSupply;

        assertEq(
            (minRedeemableBalance * circulating) / smallestRedeemableSupply,
            minimumTradeAmount,
            "The floor does not withdraw exactly the minimum trade amount at the smallest redeemable supply"
        );
        assertLt(
            ((minRedeemableBalance - 1) * circulating) / smallestRedeemableSupply,
            minimumTradeAmount,
            "One below the floor is not rejected at the smallest redeemable supply"
        );
    }

    function testMinRedeemableBalanceGetter() public view {
        assertEq(
            ILBPCommon(pool).getMinRedeemableBalance(),
            minRedeemableBalance,
            "The pool reports a floor other than the sum of the two Vault constants"
        );
    }

    function testExactOutAllowsZeroOrBalanceAtOrAboveFloor() public {
        uint256 balance = 10 * minRedeemableBalance;
        address smallPool = _createAndInitWith(0, balance);
        _warpIntoSale();

        assertTrue(
            _exactOutIsAdmitted(smallPool, balance - minRedeemableBalance),
            "The largest partial buy is refused"
        );
        assertFalse(_exactOutIsAdmitted(smallPool, balance - minRedeemableBalance + 1), "The hole does not start here");
        assertFalse(_exactOutIsAdmitted(smallPool, balance - 1), "The hole does not run to the top");
        assertTrue(_exactOutIsAdmitted(smallPool, balance), "Buying the whole balance is refused");

        assertEq(minRedeemableBalance - 1, 1_999_999, "Unexpected width for the admissible gap");
    }

    function testEndingBalanceZeroIsAccepted() public {
        _warpIntoSale();
        _buyProjectDownTo(pool, 0);

        assertEq(vault.getCurrentLiveBalances(pool)[projectIdx], 0, "Project balance is not zero");
        assertTrue(_ownerCanExit(pool), "Owner cannot exit a fully drained pool");
    }

    function testEndingBalanceOneIsRejected() public {
        _warpIntoSale();

        uint256 amountOut = _amountToLeave(pool, 1);

        _expectBlocksRedemption(projectIdx, 1);
        _buyProjectExactOut(pool, amountOut);
    }

    function testEndingBalanceJustBelowFloorIsRejected() public {
        _warpIntoSale();

        uint256 amountOut = _amountToLeave(pool, minRedeemableBalance - 1);

        _expectBlocksRedemption(projectIdx, minRedeemableBalance - 1);
        _buyProjectExactOut(pool, amountOut);
    }

    function testEndingBalanceAtFloorIsAccepted() public {
        _warpIntoSale();
        _buyProjectDownTo(pool, minRedeemableBalance);

        assertEq(vault.getCurrentLiveBalances(pool)[projectIdx], minRedeemableBalance, "Floor not placed exactly");
        assertTrue(_ownerCanExit(pool), "Owner cannot exit with the balance sitting on the floor");
    }

    function testEndingBalanceJustAboveFloorIsAccepted() public {
        _warpIntoSale();
        _buyProjectDownTo(pool, minRedeemableBalance + 1);

        assertTrue(_ownerCanExit(pool), "Owner cannot exit one above the floor");
    }

    function testProjectResidualBelowMinimumTradeAmountIsRejected() public {
        _warpIntoSale();

        uint256 residual = minimumTradeAmount - 1;
        uint256 amountOut = _amountToLeave(pool, residual);

        _expectBlocksRedemption(projectIdx, residual);
        _buyProjectExactOut(pool, amountOut);
    }

    function testProjectResidualAtMinimumTradeAmountIsRejected() public {
        _warpIntoSale();

        uint256 snapshotId = vm.snapshotState();
        _forceBalance(pool, projectIdx, minimumTradeAmount);
        assertFalse(_ownerCanExit(pool), "A balance at the minimum trade amount is not fully redeemable");
        vm.revertToState(snapshotId);

        uint256 amountOut = _amountToLeave(pool, minimumTradeAmount);

        _expectBlocksRedemption(projectIdx, minimumTradeAmount);
        _buyProjectExactOut(pool, amountOut);
    }

    function testExactInAndExactOutAgreeAtTheBoundary() public {
        address zeroFeePool = _createAndInit(0);
        _warpIntoSale();

        uint256 snapshotId = vm.snapshotState();

        uint256 amountOut = _amountToLeave(zeroFeePool, minRedeemableBalance - 1);

        _expectBlocksRedemption(projectIdx, minRedeemableBalance - 1);
        _buyProjectExactOut(zeroFeePool, amountOut);
        vm.revertToState(snapshotId);

        _expectBlocksRedemption(projectIdx, minRedeemableBalance - 1);
        _buyProjectExactIn(zeroFeePool, amountOut);
        vm.revertToState(snapshotId);

        uint256 amountAtFloor = _amountToLeave(zeroFeePool, minRedeemableBalance);

        _buyProjectExactOut(zeroFeePool, amountAtFloor);
        assertEq(
            vault.getCurrentLiveBalances(zeroFeePool)[projectIdx],
            minRedeemableBalance,
            "Exact-out missed the floor"
        );
        vm.revertToState(snapshotId);

        _buyProjectExactIn(zeroFeePool, amountAtFloor);
        assertEq(
            vault.getCurrentLiveBalances(zeroFeePool)[projectIdx],
            minRedeemableBalance,
            "Exact-in missed the floor"
        );
    }

    function testOrdinarySaleIsUnaffected() public {
        _warpIntoSale();

        vm.prank(alice);
        router.swapSingleTokenExactIn(pool, reserveToken, projectToken, 100e18, 0, MAX_UINT256, false, bytes(""));

        assertEq(
            vault.getCurrentLiveBalances(pool)[projectIdx],
            poolInitAmount - 100e18 + uint256(100e18).mulUp(swapFee),
            "Ordinary purchase did not go through cleanly"
        );
        assertTrue(_ownerCanExit(pool), "Owner cannot exit after an ordinary sale");
    }

    function testElevenDecimalsCanLeaveOneRawUnit() public {
        (address lbp, uint256 newProjectIdx, uint256 seedRaw, IERC20 project) = _buildPoolWithProjectDecimals(11);

        _buyExactOut(lbp, reserveToken, project, seedRaw - 1);

        uint256 endingBalance = vault.getCurrentLiveBalances(lbp)[newProjectIdx];
        assertEq(endingBalance, 1e7, "Unexpected scaled18 value for one raw unit at eleven decimals");
        assertGe(endingBalance, minRedeemableBalance, "One raw unit at eleven decimals is below the floor");
        assertTrue(_ownerCanExit(lbp), "Owner cannot exit with one raw unit of an eleven-decimal token left");
    }

    function testTwelveDecimalsCannotLeaveOneRawUnit() public {
        (address lbp, uint256 newProjectIdx, uint256 seedRaw, IERC20 project) = _buildPoolWithProjectDecimals(12);

        _expectBlocksRedemption(newProjectIdx, 1e6);
        _buyExactOut(lbp, reserveToken, project, seedRaw - 1);
    }

    function testThirteenDecimalsCannotLeaveOneRawUnit() public {
        (address lbp, uint256 newProjectIdx, uint256 seedRaw, IERC20 project) = _buildPoolWithProjectDecimals(13);

        _expectBlocksRedemption(newProjectIdx, 1e5);
        _buyExactOut(lbp, reserveToken, project, seedRaw - 1);
    }

    function testReserveStartsAtZero() public view {
        assertEq(vault.getCurrentLiveBalances(pool)[reserveIdx], 0, "Reserve does not start at zero");
    }

    function testZeroFeeFirstPurchaseAtTheMinimumTradeAmountIsRejected() public {
        address zeroFeePool = _createAndInit(0);
        _warpIntoSale();

        uint256 snapshotId = vm.snapshotState();
        _forceBalance(zeroFeePool, reserveIdx, minimumTradeAmount);
        assertFalse(_ownerCanExit(zeroFeePool), "A reserve balance at the minimum trade amount is fully redeemable");
        vm.revertToState(snapshotId);

        _expectBlocksRedemption(reserveIdx, minimumTradeAmount);
        vm.prank(alice);
        router.swapSingleTokenExactIn(
            zeroFeePool,
            reserveToken,
            projectToken,
            minimumTradeAmount,
            0,
            MAX_UINT256,
            false,
            bytes("")
        );
    }

    function testZeroFeeFirstPurchaseAtTheFloorIsAccepted() public {
        address zeroFeePool = _createAndInit(0);
        _warpIntoSale();

        vm.prank(alice);
        router.swapSingleTokenExactIn(
            zeroFeePool,
            reserveToken,
            projectToken,
            minRedeemableBalance,
            0,
            MAX_UINT256,
            false,
            bytes("")
        );

        assertEq(
            vault.getCurrentLiveBalances(zeroFeePool)[reserveIdx],
            minRedeemableBalance,
            "First purchase did not leave the reserve on the floor"
        );
        assertTrue(_ownerCanExit(zeroFeePool), "Owner cannot exit after a first purchase at the floor");
    }

    function testNonZeroFeeFirstPurchaseBoundary() public {
        _warpIntoSale();

        uint256 smallestFirstPurchase = minRedeemableBalance.divUp(FixedPoint.ONE - swapFee);
        uint256 snapshotId = vm.snapshotState();

        _expectBlocksRedemption(reserveIdx, minRedeemableBalance - 1);
        vm.prank(alice);
        router.swapSingleTokenExactIn(
            pool,
            reserveToken,
            projectToken,
            smallestFirstPurchase - 1,
            0,
            MAX_UINT256,
            false,
            bytes("")
        );

        vm.revertToState(snapshotId);

        vm.prank(alice);
        router.swapSingleTokenExactIn(
            pool,
            reserveToken,
            projectToken,
            smallestFirstPurchase,
            0,
            MAX_UINT256,
            false,
            bytes("")
        );

        assertGe(
            vault.getCurrentLiveBalances(pool)[reserveIdx],
            minRedeemableBalance,
            "Stored reserve fell below the checked lower bound"
        );
        assertTrue(_ownerCanExit(pool), "Owner cannot exit after the smallest admitted first purchase");
    }

    function testNonZeroAggregateFeeFirstPurchaseIsNotOverConstrained() public {
        _warpIntoSale();
        vault.manualSetAggregateSwapFeePercentage(pool, 99e16);

        uint256 smallestFirstPurchase = minRedeemableBalance.divUp(FixedPoint.ONE - swapFee);

        vm.prank(alice);
        router.swapSingleTokenExactIn(
            pool,
            reserveToken,
            projectToken,
            smallestFirstPurchase,
            0,
            MAX_UINT256,
            false,
            bytes("")
        );

        assertGe(
            vault.getCurrentLiveBalances(pool)[reserveIdx],
            minRedeemableBalance,
            "The aggregate fee took the stored reserve below the floor"
        );
        assertTrue(_ownerCanExit(pool), "Owner cannot exit with the aggregate fee at its maximum");
    }

    function testSwapIndicesSelectTheConfiguredRoles() public {
        _warpIntoSale();

        (uint256 configuredProjectIdx, uint256 configuredReserveIdx) = ILBPCommon(pool).getTokenIndices();
        assertEq(configuredProjectIdx, projectIdx, "Harness disagrees with the pool on the project index");
        assertEq(configuredReserveIdx, reserveIdx, "Harness disagrees with the pool on the reserve index");

        vm.prank(alice);
        vm.expectRevert(LBPCommon.SwapOfProjectTokenIn.selector);
        router.swapSingleTokenExactIn(pool, projectToken, reserveToken, 1e18, 0, MAX_UINT256, false, bytes(""));

        vm.prank(alice);
        vm.expectRevert(LBPCommon.SwapOfProjectTokenIn.selector);
        router.swapSingleTokenExactOut(
            pool,
            projectToken,
            reserveToken,
            1e18,
            MAX_UINT256,
            MAX_UINT256,
            false,
            bytes("")
        );
    }

    function testZeroSwapFeePoolIsStillCreatable() public {
        address zeroFeePool = _create(projectToken, reserveToken, 0);

        assertEq(vault.getStaticSwapFeePercentage(zeroFeePool), 0, "A zero swap fee was refused at creation");
    }

    function testOverdrawReturnsSwapAmountExceedsBalance() public {
        _warpIntoSale();

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IFixedPriceLBPool.SwapAmountExceedsBalance.selector,
                poolInitAmount + 1,
                poolInitAmount
            )
        );
        router.swapSingleTokenExactOut(
            pool,
            reserveToken,
            projectToken,
            poolInitAmount + 1,
            MAX_UINT256,
            MAX_UINT256,
            false,
            bytes("")
        );
    }

    function testInitializationBelowFloorIsRefused() public {
        address smallPool = _create(projectToken, reserveToken, swapFee);

        uint256[] memory initAmounts = new uint256[](2);
        initAmounts[projectIdx] = minRedeemableBalance - 1;

        (IERC20[] memory tokens, , , ) = vault.getPoolTokenInfo(smallPool);

        vm.startPrank(bob);
        vm.expectPartialRevert(LBPCommon.InitialStateBlocksRedemption.selector);
        router.initialize(smallPool, tokens, initAmounts, 0, false, bytes(""));
        vm.stopPrank();
    }

    function testInitializationAtTheFloorIsAccepted() public {
        address smallPool = _create(projectToken, reserveToken, swapFee);

        uint256[] memory initAmounts = new uint256[](2);
        initAmounts[projectIdx] = minRedeemableBalance;

        vm.startPrank(bob);
        _initPool(smallPool, initAmounts, 0);
        vm.stopPrank();
        approveForPool(IERC20(smallPool));

        assertEq(
            vault.getCurrentLiveBalances(smallPool)[projectIdx],
            minRedeemableBalance,
            "The pool was not funded on the floor"
        );
        assertTrue(_ownerCanExit(smallPool), "A pool funded on the floor cannot be exited");
    }

    function testOrdinaryInitializationIsUnaffected() public {
        address ordinaryPool = _create(projectToken, reserveToken, swapFee);

        uint256[] memory initAmounts = new uint256[](2);
        initAmounts[projectIdx] = poolInitAmount;

        vm.startPrank(bob);
        _initPool(ordinaryPool, initAmounts, 0);
        vm.stopPrank();
        approveForPool(IERC20(ordinaryPool));

        assertGt(poolInitAmount / minRedeemableBalance, 1e11, "The ordinary seed is not far above the boundary");
        assertTrue(_ownerCanExit(ordinaryPool), "An ordinary pool cannot be exited");
    }

    function testPartialWithdrawalWithNonRedeemableRemainderIsRefused() public {
        _warpIntoSale();
        _buyProjectDownTo(pool, minRedeemableBalance);
        _warpPastSale();

        uint256 totalSupply = IERC20(pool).totalSupply();
        uint256 burn = totalSupply / 2;

        uint256[] memory balances = vault.getCurrentLiveBalances(pool);
        uint256 remainingProject = balances[projectIdx] - (balances[projectIdx] * burn) / totalSupply;
        uint256 remainingReserve = balances[reserveIdx] - (balances[reserveIdx] * burn) / totalSupply;

        assertEq(remainingProject, minimumTradeAmount, "The burn does not leave the expected project remainder");
        assertGt(remainingReserve, 400e18, "The remaining reserve is smaller than expected");

        vm.startPrank(bob);
        IERC20(pool).approve(address(router), MAX_UINT256);
        vm.expectRevert(
            abi.encodeWithSelector(
                LBPCommon.RemainingBalanceBlocksRedemption.selector,
                projectIdx,
                remainingProject,
                totalSupply - burn
            )
        );
        router.removeLiquidityProportional(pool, burn, new uint256[](2), false, bytes(""));
        vm.stopPrank();

        assertTrue(_ownerCanExit(pool), "The full exit no longer clears from the floor");
    }

    function testRoundedTwelveDecimalRemainderIsRejected() public {
        (address lbp, uint256 newProjectIdx, uint256 seedRaw, IERC20 project) = _buildPoolWithProjectDecimals(12);
        uint256 scalingFactor = 1e6;

        _buyExactOut(lbp, reserveToken, project, seedRaw - 2);
        assertEq(
            vault.getCurrentLiveBalances(lbp)[newProjectIdx],
            2 * scalingFactor,
            "The project balance is not on the floor"
        );

        _warpPastSale();

        uint256 totalSupply = IERC20(lbp).totalSupply();
        uint256 balance = vault.getCurrentLiveBalances(lbp)[newProjectIdx];

        uint256 remainingSupply = totalSupply / balance;
        uint256 burn = totalSupply - remainingSupply;

        assertEq(balance - (balance * burn) / totalSupply, 1, "The projected remainder is not one unit");

        assertGe((balance * burn) / totalSupply, minimumTradeAmount, "The Vault would have refused this anyway");

        uint256 actualRemainder = balance - ((balance * burn) / totalSupply / scalingFactor) * scalingFactor;
        assertEq(actualRemainder, scalingFactor, "The rounded remainder is not the scaling factor");
        assertLt(
            (actualRemainder * (remainingSupply - vault.getPoolMinimumTotalSupply())) / remainingSupply,
            minimumTradeAmount,
            "The rounded remainder would remain redeemable"
        );

        vm.startPrank(bob);
        IERC20(lbp).approve(address(router), MAX_UINT256);
        vm.expectRevert(
            abi.encodeWithSelector(
                LBPCommon.RemainingBalanceBlocksRedemption.selector,
                newProjectIdx,
                1,
                remainingSupply
            )
        );
        router.removeLiquidityProportional(lbp, burn, new uint256[](2), false, bytes(""));
        vm.stopPrank();

        assertTrue(_ownerCanExit(lbp), "The full exit is refused on the twelve-decimal pool");
    }

    function _create(IERC20 project, IERC20 reserve, uint256 staticSwapFee) internal returns (address newPool) {
        LBPCommonParams memory lbpCommonParams = LBPCommonParams({
            name: "FixedPriceLBPool",
            symbol: "FLBP",
            owner: bob,
            projectToken: project,
            reserveToken: reserve,
            startTime: uint32(block.timestamp + DEFAULT_START_OFFSET),
            endTime: uint32(block.timestamp + DEFAULT_END_OFFSET),
            blockProjectTokenSwapsIn: true
        });

        newPool = lbPoolFactory.create(lbpCommonParams, RATE, staticSwapFee, bytes32(_saltCounter++), address(0));
    }

    function _exactOutIsAdmitted(address lbp, uint256 amountOutRaw) internal returns (bool ok) {
        uint256 snapshotId = vm.snapshotState();

        vm.prank(alice);
        try
            router.swapSingleTokenExactOut(
                lbp,
                reserveToken,
                projectToken,
                amountOutRaw,
                MAX_UINT256,
                MAX_UINT256,
                false,
                bytes("")
            )
        returns (uint256) {
            ok = true;
        } catch {
            ok = false;
        }

        vm.revertToState(snapshotId);
    }

    function _createAndInit(uint256 staticSwapFee) internal returns (address newPool) {
        return _createAndInitWith(staticSwapFee, poolInitAmount);
    }

    function _createAndInitWith(uint256 staticSwapFee, uint256 projectAmount) internal returns (address newPool) {
        newPool = _create(projectToken, reserveToken, staticSwapFee);

        uint256[] memory initAmounts = new uint256[](2);
        initAmounts[projectIdx] = projectAmount;

        vm.startPrank(bob);
        _initPool(newPool, initAmounts, 0);
        vm.stopPrank();

        approveForPool(IERC20(newPool));
    }

    function _warpIntoSale() internal {
        vm.warp(block.timestamp + DEFAULT_START_OFFSET + 1);
    }

    function _warpPastSale() internal {
        vm.warp(block.timestamp + DEFAULT_END_OFFSET + 1);
    }

    function _amountToLeave(address lbp, uint256 target) internal view returns (uint256) {
        (uint256 poolProjectIdx, ) = ILBPCommon(lbp).getTokenIndices();

        return vault.getCurrentLiveBalances(lbp)[poolProjectIdx] - target;
    }

    function _buyProjectExactOut(address lbp, uint256 amountOutRaw) internal {
        _buyExactOut(lbp, reserveToken, projectToken, amountOutRaw);
    }

    function _buyExactOut(address lbp, IERC20 reserve, IERC20 project, uint256 amountOutRaw) internal {
        vm.prank(alice);
        router.swapSingleTokenExactOut(lbp, reserve, project, amountOutRaw, MAX_UINT256, MAX_UINT256, false, bytes(""));
    }

    function _buyProjectExactIn(address lbp, uint256 amountOutRaw) internal {
        vm.prank(alice);
        router.swapSingleTokenExactIn(lbp, reserveToken, projectToken, amountOutRaw, 0, MAX_UINT256, false, bytes(""));
    }

    function _buyProjectDownTo(address lbp, uint256 target) internal {
        _buyProjectExactOut(lbp, _amountToLeave(lbp, target));
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

        vm.warp(block.timestamp + DEFAULT_END_OFFSET + 1);

        uint256 ownerBpt = IERC20(lbp).balanceOf(bob);

        vm.startPrank(bob);
        IERC20(lbp).approve(address(router), MAX_UINT256);

        try router.removeLiquidityProportional(lbp, ownerBpt, new uint256[](2), false, bytes("")) returns (
            uint256[] memory
        ) {
            ok = true;
        } catch {
            ok = false;
        }
        vm.stopPrank();

        vm.revertToState(snapshotId);
    }

    function _buildPoolWithProjectDecimals(
        uint8 decimals
    ) internal returns (address lbp, uint256 newProjectIdx, uint256 seedRaw, IERC20 project) {
        ERC20TestToken newToken = createERC20("P", decimals);
        project = newToken;

        seedRaw = 1_000 * 10 ** decimals;
        _fund(newToken, seedRaw * 10);

        lbp = _create(project, reserveToken, 0);

        uint256 newReserveIdx;
        (newProjectIdx, newReserveIdx) = getSortedIndexes(address(project), address(reserveToken));

        IERC20[] memory poolTokens = new IERC20[](2);
        poolTokens[newProjectIdx] = project;
        poolTokens[newReserveIdx] = reserveToken;

        uint256[] memory initAmounts = new uint256[](2);
        initAmounts[newProjectIdx] = seedRaw;

        vm.prank(bob);
        router.initialize(lbp, poolTokens, initAmounts, 0, false, bytes(""));

        _warpIntoSale();
    }

    function _fund(ERC20TestToken token, uint256 amount) internal {
        address[3] memory who = [address(bob), address(alice), address(lp)];

        for (uint256 i = 0; i < who.length; ++i) {
            token.mint(who[i], amount);

            vm.startPrank(who[i]);
            token.approve(address(permit2), type(uint256).max);
            permit2.approve(address(token), address(router), type(uint160).max, type(uint48).max);
            vm.stopPrank();
        }
    }
}
