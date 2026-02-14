// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { ILBPool } from "@balancer-labs/v3-interfaces/contracts/pool-weighted/ILBPool.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import "@balancer-labs/v3-interfaces/contracts/pool-weighted/ILBPCommon.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { LBPCommon } from "../../contracts/lbp/LBPCommon.sol";
import { WeightedLBPTest } from "./utils/WeightedLBPTest.sol";

contract LBPoolRealReservesTest is WeightedLBPTest {
    /// @dev Seedless pool with bidirectional swaps (blockProjectTokenSwapsIn = false)
    address internal bidirectionalPool;

    function setUp() public virtual override {
        // Configure as seedless (virtual balance > 0) before base setUp
        reserveTokenVirtualBalance = poolInitAmount;

        super.setUp();

        _deployBidirectionalPool();
    }

    function createPool() internal virtual override returns (address newPool, bytes memory poolArgs) {
        // Default pool uses the standard seedless config with project-token-in blocked
        return
            _createLBPool(
                address(0),
                uint32(block.timestamp + DEFAULT_START_OFFSET),
                uint32(block.timestamp + DEFAULT_END_OFFSET),
                DEFAULT_PROJECT_TOKENS_SWAP_IN
            );
    }

    function initPool() internal virtual override {
        // Seedless initialization: zero reserve tokens
        uint256[] memory initAmounts = new uint256[](2);
        initAmounts[projectIdx] = poolInitAmount;

        vm.startPrank(bob);
        _initPool(pool, initAmounts, 0);
        vm.stopPrank();
    }

    /// @dev Deploy a second seedless pool with project-token swap-in allowed
    function _deployBidirectionalPool() internal {
        (bidirectionalPool, ) = _createLBPoolWithCustomWeights(
            address(0),
            startWeights[projectIdx],
            startWeights[reserveIdx],
            endWeights[projectIdx],
            endWeights[reserveIdx],
            uint32(block.timestamp + DEFAULT_START_OFFSET),
            uint32(block.timestamp + DEFAULT_END_OFFSET),
            false // Do NOT block project token swaps in
        );

        // Seedless init for the bidirectional pool
        uint256[] memory initAmounts = new uint256[](2);
        initAmounts[projectIdx] = poolInitAmount;

        address savedPool = pool;
        pool = bidirectionalPool;

        vm.startPrank(bob);
        _initPool(bidirectionalPool, initAmounts, 0);
        vm.stopPrank();

        pool = savedPool;
    }

    /**
     * @notice A valid EXACT_OUT swap where reserveOut < realBalance should succeed.
     * @dev With a large virtual balance relative to a small real reserve, even a modest EXACT_OUT request produces
     * a computed in-amount that exceeds the real reserve. This test insures that the swap checks
     * request.amountGivenScaled18 - not the calculated amount - so the swap succeeds.
     *
     * If we checked `calculatedAmountScaled18` (as in EXACT_IN), this valid swap would be rejected (false positive).
     *
     */
    function testValidExactOutSwap() public {
        // Precondition: pool is seedless.
        (, uint256 virtualBalanceScaled18) = ILBPool(bidirectionalPool).getReserveTokenVirtualBalance();
        assertGt(virtualBalanceScaled18, 0, "Pool must be seedless for this test");

        // Warp to just before endTime so weights are close to endWeights (project ≈ 10%, reserve ≈ 90%).
        // The high reserve weight means the exponent in computeInGivenExactOut (weightOut/weightIn ≈ 9) amplifies
        // the computed in-amount well beyond the out-amount.
        vm.warp(block.timestamp + DEFAULT_END_OFFSET - 2);

        assertTrue(ILBPCommon(bidirectionalPool).isSwapEnabled(), "Swaps should be enabled");

        // Use a small real reserve with a large project balance. The pool will internally add virtualBalanceScaled18
        // to the reserve, creating a large effective reserve. With project balance ≈ effective reserve, the weighted
        // math amplification factor (≈ weightOut/weightIn for small amounts) means the computed in-amount will be a
        // multiple of the out-amount, easily exceeding the tiny real reserve.
        uint256 realReserveBalance = 1e18;
        uint256 reserveOutAmount = realReserveBalance / 2;

        // Mock balances according to the vault (which are real reserves).
        uint256[] memory balances = new uint256[](2);
        balances[projectIdx] = poolInitAmount; // ~1000e18
        balances[reserveIdx] = realReserveBalance;

        PoolSwapParams memory request = PoolSwapParams({
            kind: SwapKind.EXACT_OUT,
            amountGivenScaled18: reserveOutAmount,
            balancesScaled18: balances,
            indexIn: projectIdx,
            indexOut: reserveIdx,
            router: address(router),
            userData: bytes("")
        });

        // calculatedAmountScaled18 (project-in) > realReserveBalance, but realReserveBalance > reserveOutAmount
        vm.prank(address(vault));
        uint256 amountCalculated = IBasePool(bidirectionalPool).onSwap(request);
        assertGt(amountCalculated, realReserveBalance, "amountCalculated should exceed realReserveBalance");

        assertGt(realReserveBalance, reserveOutAmount, "realReserveBalance should exceed reserveOutAmount");
    }

    /**
     * @notice A invalid EXACT_OUT swap where reserveOut > realBalance should fail.
     * @dev An EXACT_OUT swap requesting more reserve tokens than the real balance should revert with
     * `InsufficientRealReserveBalance`, since we are comparing request.amountGivenScaled18 to originalReserveBalance.
     */
    function testInvalidExactOutSwap() public {
        // Warp into the sale period.
        vm.warp(block.timestamp + DEFAULT_START_OFFSET + 1);

        // Use a small real reserve with a large project balance
        uint256 realReserveBalance = 1e18;

        uint256[] memory balances = new uint256[](2);
        balances[projectIdx] = poolInitAmount;
        balances[reserveIdx] = realReserveBalance;

        // Request more reserve tokens out than the real balance
        uint256 reserveOutAmount = realReserveBalance + 1;

        PoolSwapParams memory request = PoolSwapParams({
            kind: SwapKind.EXACT_OUT,
            amountGivenScaled18: reserveOutAmount,
            balancesScaled18: balances,
            indexIn: projectIdx,
            indexOut: reserveIdx,
            router: address(router),
            userData: bytes("")
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                ILBPool.InsufficientRealReserveBalance.selector,
                reserveOutAmount,
                realReserveBalance
            )
        );
        vm.prank(address(vault));
        IBasePool(bidirectionalPool).onSwap(request);
    }

    /// @notice Sanity check: EXACT_IN with reserve as output still works correctly
    function testValidExactInSwap() public {
        // Warp into the sale period
        vm.warp(block.timestamp + DEFAULT_START_OFFSET + 1);

        // Use some real reserve
        uint256 realReserveBalance = 10e18;

        uint256[] memory balances = new uint256[](2);
        balances[projectIdx] = poolInitAmount;
        balances[reserveIdx] = realReserveBalance;

        // Small EXACT_IN of project tokens → reserve tokens out
        uint256 projectInAmount = 1e18;

        PoolSwapParams memory request = PoolSwapParams({
            kind: SwapKind.EXACT_IN,
            amountGivenScaled18: projectInAmount,
            balancesScaled18: balances,
            indexIn: projectIdx,
            indexOut: reserveIdx,
            router: address(router),
            userData: bytes("")
        });

        vm.prank(address(vault));
        uint256 amountOut = IBasePool(bidirectionalPool).onSwap(request);
        assertGt(amountOut, 0, "EXACT_IN swap should return non-zero out-amount");
        assertLe(amountOut, realReserveBalance, "Out amount should not exceed real reserve balance");
    }

    /// @notice EXACT_IN that would produce more reserve out than real balance should revert.
    function testInvalidExactInSwap() public {
        // Warp into the sale period
        vm.warp(block.timestamp + DEFAULT_START_OFFSET + 1);

        // Use a tiny real reserve so that even a small swap exceeds it
        uint256 realReserveBalance = 1e18;

        uint256[] memory balances = new uint256[](2);
        balances[projectIdx] = poolInitAmount;
        balances[reserveIdx] = realReserveBalance;

        // At start weights (project ≈ 90%, reserve ≈ 10%) with effective reserve ≈ 1001e18, the spot price of reserve
        // per project is ~0.11. So ~20e18 project-in yields ~2e18 reserve-out, exceeding the 1e18 real reserve, but
        // stays well under MaxInRatio (30%)
        uint256 projectInAmount = 20e18;

        PoolSwapParams memory request = PoolSwapParams({
            kind: SwapKind.EXACT_IN,
            amountGivenScaled18: projectInAmount,
            balancesScaled18: balances,
            indexIn: projectIdx,
            indexOut: reserveIdx,
            router: address(router),
            userData: bytes("")
        });

        // Should revert because the calculated out will exceed the real reserve
        vm.expectPartialRevert(ILBPool.InsufficientRealReserveBalance.selector);
        vm.prank(address(vault));
        IBasePool(bidirectionalPool).onSwap(request);
    }

    /// @notice EXACT_OUT where reserve is the INPUT (project is output) should not be affected.
    function testExactOutWithReserveInput() public {
        // Warp to start of sale (project weight ≈ 90%, reserve weight ≈ 10%)
        vm.warp(block.timestamp + DEFAULT_START_OFFSET + 1);
        assertTrue(ILBPCommon(bidirectionalPool).isSwapEnabled(), "Swaps should be enabled");

        uint256[] memory balances = vault.getCurrentLiveBalances(bidirectionalPool);

        // EXACT_OUT: reserve in for project out; no real reserve balance check required
        uint256 projectOutAmount = 1e18;

        PoolSwapParams memory request = PoolSwapParams({
            kind: SwapKind.EXACT_OUT,
            amountGivenScaled18: projectOutAmount,
            balancesScaled18: balances,
            indexIn: reserveIdx,
            indexOut: projectIdx,
            router: address(router),
            userData: bytes("")
        });

        vm.prank(address(vault));
        uint256 amountCalculated = IBasePool(bidirectionalPool).onSwap(request);
        assertGt(amountCalculated, 0, "Swap should return non-zero in-amount");
    }

    /// @notice End-to-end EXACT_OUT swap buying project tokens with reserve tokens on a seedless pool.
    function testE2ESwapExactOutBuyProjectToken() public {
        vm.warp(block.timestamp + DEFAULT_START_OFFSET + 1);

        uint256 projectOutAmount = 1e18;
        uint256 projectBefore = projectToken.balanceOf(alice);
        uint256 reserveBefore = reserveToken.balanceOf(alice);

        vm.prank(alice);
        router.swapSingleTokenExactOut(
            bidirectionalPool,
            reserveToken,
            projectToken,
            projectOutAmount,
            type(uint256).max,
            type(uint256).max,
            false,
            bytes("")
        );

        uint256 projectReceived = projectToken.balanceOf(alice) - projectBefore;
        uint256 reserveSpent = reserveBefore - reserveToken.balanceOf(alice);

        assertEq(projectReceived, projectOutAmount, "Should receive exact project tokens requested");
        assertGt(reserveSpent, 0, "Should spend reserve tokens");
    }

    /// @notice End-to-end EXACT_OUT swap buying project tokens with reserve tokens on a seedless pool.
    function testE2ESwapExactOutSellProjectToken() public {
        // Build real reserve first.
        vm.warp(block.timestamp + DEFAULT_START_OFFSET + 1);

        uint256 buyAmount = 50e18;
        vm.prank(bob);
        router.swapSingleTokenExactIn(
            bidirectionalPool,
            reserveToken,
            projectToken,
            buyAmount,
            0,
            type(uint256).max,
            false,
            bytes("")
        );

        // Now do an EXACT_OUT selling project tokens for a small amount of reserve tokens
        uint256[] memory balances = vault.getCurrentLiveBalances(bidirectionalPool);
        uint256 realReserveBalance = balances[reserveIdx];
        uint256 reserveOutAmount = realReserveBalance / 4;

        uint256 projectBefore = projectToken.balanceOf(alice);
        uint256 reserveBefore = reserveToken.balanceOf(alice);

        vm.prank(alice);
        router.swapSingleTokenExactOut(
            bidirectionalPool,
            projectToken,
            reserveToken,
            reserveOutAmount,
            type(uint256).max,
            type(uint256).max,
            false,
            bytes("")
        );

        uint256 projectSpent = projectBefore - projectToken.balanceOf(alice);
        uint256 reserveReceived = reserveToken.balanceOf(alice) - reserveBefore;

        assertEq(reserveReceived, reserveOutAmount, "Should receive exact reserve tokens requested");
        assertGt(projectSpent, 0, "Should spend project tokens");
    }
}
