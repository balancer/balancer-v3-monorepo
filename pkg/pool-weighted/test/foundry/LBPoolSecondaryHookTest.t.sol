// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";
import "@balancer-labs/v3-interfaces/contracts/pool-weighted/ILBPCommon.sol";
import "@balancer-labs/v3-interfaces/contracts/pool-weighted/ILBPool.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { DirectionalSwapFeeTaxHook } from "@balancer-labs/v3-pool-hooks/contracts/DirectionalSwapFeeTaxHook.sol";
import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { BaseHooks } from "@balancer-labs/v3-vault/contracts/BaseHooks.sol";

import { LBPoolFactory } from "../../contracts/lbp/LBPoolFactory.sol";
import { LBPCommon } from "../../contracts/lbp/LBPCommon.sol";
import { WeightedLBPTest } from "./utils/WeightedLBPTest.sol";
import { LBPool } from "../../contracts/lbp/LBPool.sol";

contract LBPoolSecondaryHookTest is WeightedLBPTest {
    using CastingHelpers for address[];
    using FixedPoint for uint256;
    using ArrayHelpers for *;

    // The secondary hook contract.
    DirectionalSwapFeeTaxHook internal secondaryHook;

    // Tax percentage for the hook (5%).
    uint256 internal constant TAX_PERCENTAGE = 5e16;

    // The token the hook taxes (reserve token, so selling project tokens incurs a tax).
    IERC20 internal taxFeeToken;

    function setUp() public virtual override {
        super.setUp();
    }

    function onAfterDeployMainContracts() internal override {
        super.onAfterDeployMainContracts();

        // The fee token is the reserve token: swaps that output reserve tokens are taxed.
        // Must be set before createPool() runs, since the hook is deployed during pool creation.
        taxFeeToken = reserveToken;
    }

    /// @dev Override createPool to deploy with the secondary hook attached.
    function createPool() internal virtual override returns (address newPool, bytes memory poolArgs) {
        return
            _createLBPoolWithSecondaryHook(
                address(0), // Pool creator
                uint32(block.timestamp + DEFAULT_START_OFFSET),
                uint32(block.timestamp + DEFAULT_END_OFFSET),
                DEFAULT_PROJECT_TOKENS_SWAP_IN
            );
    }

    /*******************************************************************************
                              Registration & Flags
    *******************************************************************************/

    function testSecondaryHookRegistered() public view {
        // The secondary hook should have the pool as its authorized caller.
        assertEq(secondaryHook.getAuthorizedCaller(), pool, "Secondary hook authorized caller should be the pool");
    }

    function testPoolAuthorizedCallerIsVault() public view {
        // The pool (primary hook) should have the vault as its authorized caller.
        assertEq(IHooks(pool).getAuthorizedCaller(), address(vault), "Pool authorized caller should be the vault");
    }

    function testHookFlagsIncludeSecondaryHookFlags() public view {
        HookFlags memory flags = IHooks(pool).getHookFlags();

        // LBP native flags.
        assertTrue(flags.shouldCallBeforeInitialize, "shouldCallBeforeInitialize should be true");
        assertTrue(flags.shouldCallBeforeAddLiquidity, "shouldCallBeforeAddLiquidity should be true");
        assertTrue(flags.shouldCallBeforeRemoveLiquidity, "shouldCallBeforeRemoveLiquidity should be true");

        // Flags from the secondary hook.
        assertTrue(flags.shouldCallAfterSwap, "shouldCallAfterSwap should be true (from secondary hook)");
        assertTrue(flags.enableHookAdjustedAmounts, "enableHookAdjustedAmounts should be true (from secondary hook)");

        // Flags that neither the LBP nor the secondary hook set.
        assertFalse(flags.shouldCallBeforeSwap, "shouldCallBeforeSwap should be false");
        assertFalse(flags.shouldCallComputeDynamicSwapFee, "shouldCallComputeDynamicSwapFee should be false");
        assertFalse(flags.shouldCallAfterInitialize, "shouldCallAfterInitialize should be false");
        assertFalse(flags.shouldCallAfterAddLiquidity, "shouldCallAfterAddLiquidity should be false");
        assertFalse(flags.shouldCallAfterRemoveLiquidity, "shouldCallAfterRemoveLiquidity should be false");
    }

    function testSecondaryHookGetters() public view {
        assertEq(address(secondaryHook.getFeeToken()), address(taxFeeToken), "Wrong fee token");
        assertEq(secondaryHook.getTaxPercentage(), TAX_PERCENTAGE, "Wrong tax percentage");
    }

    /*******************************************************************************
                            Swap with Tax (Exact In)
    *******************************************************************************/

    /// @notice Swap reserve → project (exact in). The output is project token, not the fee token, so no tax.
    function testSwapExactIn_NoTax_ReserveToProject() public {
        _warpToSale();

        uint256 swapAmount = poolInitAmount / 100;

        uint256 userProjectBefore = projectToken.balanceOf(bob);
        uint256 userReserveBefore = reserveToken.balanceOf(bob);
        uint256 hookProjectBefore = projectToken.balanceOf(address(secondaryHook));
        uint256 hookReserveBefore = reserveToken.balanceOf(address(secondaryHook));

        vm.prank(bob);
        router.swapSingleTokenExactIn(pool, reserveToken, projectToken, swapAmount, 0, MAX_UINT256, false, bytes(""));

        uint256 userProjectAfter = projectToken.balanceOf(bob);
        uint256 userReserveAfter = reserveToken.balanceOf(bob);
        uint256 hookProjectAfter = projectToken.balanceOf(address(secondaryHook));
        uint256 hookReserveAfter = reserveToken.balanceOf(address(secondaryHook));

        // User paid swapAmount of reserve token.
        assertEq(userReserveBefore - userReserveAfter, swapAmount, "User reserve balance wrong");

        // User received project tokens. For exact in, the output is project token (not fee token), so no tax.
        uint256 projectReceived = userProjectAfter - userProjectBefore;
        assertGt(projectReceived, 0, "Should receive project tokens");

        // Hook should not have collected any fees.
        assertEq(hookReserveAfter, hookReserveBefore, "Hook should not collect reserve token fees");
        assertEq(hookProjectAfter, hookProjectBefore, "Hook should not collect project token fees");
    }

    /**
     * @notice Swap project → reserve (exact in). Output is reserve (the fee token), so tax applies.
     * @dev This requires blockProjectTokenSwapsIn = false.
     */
    function testSwapExactIn_WithTax_ProjectToReserve() public {
        _createAndInitPoolAllowingProjectSwapIn();
        _warpToSale();

        uint256 swapAmount = poolInitAmount / 100;

        uint256 userProjectBefore = projectToken.balanceOf(bob);
        uint256 userReserveBefore = reserveToken.balanceOf(bob);
        uint256 hookReserveBefore = reserveToken.balanceOf(address(secondaryHook));

        vm.prank(bob);
        router.swapSingleTokenExactIn(pool, projectToken, reserveToken, swapAmount, 0, MAX_UINT256, false, bytes(""));

        uint256 userProjectAfter = projectToken.balanceOf(bob);
        uint256 userReserveAfter = reserveToken.balanceOf(bob);
        uint256 hookReserveAfter = reserveToken.balanceOf(address(secondaryHook));

        assertEq(userProjectBefore - userProjectAfter, swapAmount, "User project balance wrong");

        uint256 reserveReceived = userReserveAfter - userReserveBefore;
        uint256 hookFeeCollected = hookReserveAfter - hookReserveBefore;

        assertGt(hookFeeCollected, 0, "Hook should have collected reserve token fees");
        assertGt(reserveReceived, 0, "User should have received some reserve tokens");

        uint256 originalAmountOut = reserveReceived + hookFeeCollected;
        uint256 expectedFee = originalAmountOut.mulUp(TAX_PERCENTAGE);
        assertEq(hookFeeCollected, expectedFee, "Hook fee amount incorrect");
    }

    /// @notice Fuzz test for exact in swaps where tax applies.
    function testSwapExactIn_WithTax_Fuzz(uint256 swapAmount) public {
        _createAndInitPoolAllowingProjectSwapIn();
        _warpToSale();

        // Bound to reasonable range.
        swapAmount = bound(swapAmount, POOL_MINIMUM_TOTAL_SUPPLY, poolInitAmount / 10);

        uint256 userReserveBefore = reserveToken.balanceOf(bob);
        uint256 hookReserveBefore = reserveToken.balanceOf(address(secondaryHook));

        vm.prank(bob);
        router.swapSingleTokenExactIn(pool, projectToken, reserveToken, swapAmount, 0, MAX_UINT256, false, bytes(""));

        uint256 userReserveAfter = reserveToken.balanceOf(bob);
        uint256 hookReserveAfter = reserveToken.balanceOf(address(secondaryHook));

        uint256 reserveReceived = userReserveAfter - userReserveBefore;
        uint256 hookFeeCollected = hookReserveAfter - hookReserveBefore;

        uint256 originalAmountOut = reserveReceived + hookFeeCollected;
        uint256 expectedFee = originalAmountOut.mulUp(TAX_PERCENTAGE);
        assertEq(hookFeeCollected, expectedFee, "Hook fee amount incorrect (fuzz)");
    }

    /*******************************************************************************
                            Swap with Tax (Exact Out)
    *******************************************************************************/

    /**
     * @notice Swap reserve -> project (exact out).
     * @dev The calculated amount is amountIn (reserve), which is the fee token, so tax applies.
     * The user pays more reserve tokens.
     */
    function testSwapExactOut_WithTax_ReserveToProject() public {
        _warpToSale();

        uint256 exactAmountOut = poolInitAmount / 100;

        uint256 userProjectBefore = projectToken.balanceOf(bob);
        uint256 userReserveBefore = reserveToken.balanceOf(bob);
        uint256 hookReserveBefore = reserveToken.balanceOf(address(secondaryHook));

        vm.prank(bob);
        router.swapSingleTokenExactOut(
            pool,
            reserveToken,
            projectToken,
            exactAmountOut,
            MAX_UINT256,
            MAX_UINT256,
            false,
            bytes("")
        );

        uint256 userProjectAfter = projectToken.balanceOf(bob);
        uint256 userReserveAfter = reserveToken.balanceOf(bob);
        uint256 hookReserveAfter = reserveToken.balanceOf(address(secondaryHook));

        // User received exactly the requested project tokens.
        assertEq(
            userProjectAfter - userProjectBefore,
            exactAmountOut,
            "User should receive exact project token amount"
        );

        // For exact out, the calculated amount is amountIn (reserve token = fee token).
        // The hook increases the amountIn by the tax.
        uint256 reservePaid = userReserveBefore - userReserveAfter;
        uint256 hookFeeCollected = hookReserveAfter - hookReserveBefore;

        assertGt(hookFeeCollected, 0, "Hook should collect reserve token fees on exact out");

        // reservePaid = originalAmountIn + hookFee, so originalAmountIn = reservePaid - hookFee.
        uint256 originalAmountIn = reservePaid - hookFeeCollected;
        uint256 expectedFee = originalAmountIn.mulUp(TAX_PERCENTAGE);
        assertEq(hookFeeCollected, expectedFee, "Hook fee amount incorrect (exact out)");
    }

    /// @notice Swap project → reserve (exact out). The calculated amount is amountIn (project token), which is
    /// NOT the fee token, so no tax.
    function testSwapExactOut_NoTax_ProjectToReserve() public {
        _createAndInitPoolAllowingProjectSwapIn();
        _warpToSale();

        uint256 exactAmountOut = poolInitAmount / 100;

        uint256 userReserveBefore = reserveToken.balanceOf(bob);
        uint256 hookProjectBefore = projectToken.balanceOf(address(secondaryHook));
        uint256 hookReserveBefore = reserveToken.balanceOf(address(secondaryHook));

        vm.prank(bob);
        router.swapSingleTokenExactOut(
            pool,
            projectToken,
            reserveToken,
            exactAmountOut,
            MAX_UINT256,
            MAX_UINT256,
            false,
            bytes("")
        );

        uint256 userReserveAfter = reserveToken.balanceOf(bob);
        uint256 hookProjectAfter = projectToken.balanceOf(address(secondaryHook));
        uint256 hookReserveAfter = reserveToken.balanceOf(address(secondaryHook));

        // User received exact reserve tokens.
        assertEq(
            userReserveAfter - userReserveBefore,
            exactAmountOut,
            "User should receive exact reserve token amount"
        );

        // For exact out, calculated amount is amountIn = project token, not the fee token. No tax.
        assertEq(hookReserveAfter, hookReserveBefore, "Hook should not collect reserve fees");
        assertEq(hookProjectAfter, hookProjectBefore, "Hook should not collect project fees");
    }

    /*******************************************************************************
                              Limit Violations
    *******************************************************************************/

    /// @notice Exact in: user sets minAmountOut expecting no tax, but the hook reduces the output.
    function testSwapExactIn_LimitViolation() public {
        _createAndInitPoolAllowingProjectSwapIn();
        _warpToSale();

        uint256 swapAmount = poolInitAmount / 100;

        // Discover the actual post-tax output.
        uint256 snapshotId = vm.snapshotState();
        vm.prank(bob);
        uint256 actualAmountOut = router.swapSingleTokenExactIn(
            pool,
            projectToken,
            reserveToken,
            swapAmount,
            0,
            MAX_UINT256,
            false,
            bytes("")
        );
        vm.revertToState(snapshotId);

        // Set minAmountOut just above the post-tax output.
        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(IVaultErrors.HookAdjustedSwapLimit.selector, actualAmountOut, actualAmountOut + 1)
        );
        router.swapSingleTokenExactIn(
            pool,
            projectToken,
            reserveToken,
            swapAmount,
            actualAmountOut + 1,
            MAX_UINT256,
            false,
            bytes("")
        );
    }

    /// @notice Exact out: user sets maxAmountIn too low, but the hook increases the required input.
    function testSwapExactOut_LimitViolation() public {
        _warpToSale();

        uint256 exactAmountOut = poolInitAmount / 100;

        // Discover the actual post-tax amountIn.
        uint256 snapshotId = vm.snapshotState();
        uint256 reserveBefore = reserveToken.balanceOf(bob);
        vm.prank(bob);
        router.swapSingleTokenExactOut(
            pool,
            reserveToken,
            projectToken,
            exactAmountOut,
            MAX_UINT256,
            MAX_UINT256,
            false,
            bytes("")
        );
        uint256 actualAmountIn = reserveBefore - reserveToken.balanceOf(bob);
        vm.revertToState(snapshotId);

        // Set maxAmountIn just below the post-tax amountIn.
        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(IVaultErrors.HookAdjustedSwapLimit.selector, actualAmountIn, actualAmountIn - 1)
        );
        router.swapSingleTokenExactOut(
            pool,
            reserveToken,
            projectToken,
            exactAmountOut,
            actualAmountIn - 1,
            MAX_UINT256,
            false,
            bytes("")
        );
    }

    /*******************************************************************************
                              Fee Withdrawal
    *******************************************************************************/

    function testWithdrawFees() public {
        _createAndInitPoolAllowingProjectSwapIn();
        _warpToSale();

        uint256 swapAmount = poolInitAmount / 100;

        // Do a taxed swap to accumulate fees.
        vm.prank(bob);
        router.swapSingleTokenExactIn(pool, projectToken, reserveToken, swapAmount, 0, MAX_UINT256, false, bytes(""));

        uint256 hookBalance = reserveToken.balanceOf(address(secondaryHook));
        assertGt(hookBalance, 0, "Hook should have accumulated fees");

        // The hook owner (bob in our setup) withdraws.
        address hookOwner = secondaryHook.owner();
        uint256 ownerBalanceBefore = reserveToken.balanceOf(hookOwner);

        vm.expectEmit();
        emit DirectionalSwapFeeTaxHook.HookFeeWithdrawn(address(secondaryHook), reserveToken, hookOwner, hookBalance);

        vm.prank(bob);
        secondaryHook.withdrawFees(reserveToken);

        uint256 ownerBalanceAfter = reserveToken.balanceOf(hookOwner);
        assertEq(ownerBalanceAfter - ownerBalanceBefore, hookBalance, "Owner should receive all fees");
        assertEq(reserveToken.balanceOf(address(secondaryHook)), 0, "Hook should have zero balance after withdrawal");
    }

    function testWithdrawFeesNoBalance() public {
        // Withdrawing with no balance should be a no-op (no revert).
        uint256 ownerBalance = reserveToken.balanceOf(secondaryHook.owner());

        vm.prank(bob);
        secondaryHook.withdrawFees(reserveToken);
        assertEq(reserveToken.balanceOf(secondaryHook.owner()), ownerBalance, "Balance should not change");
    }

    /*******************************************************************************
                           Access Control
    *******************************************************************************/

    /// @notice The secondary hook's onAfterSwap should revert if called by an unauthorized address.
    function testSecondaryHookRejectsUnauthorizedCaller() public {
        _warpToSale();

        AfterSwapParams memory fakeParams = AfterSwapParams({
            kind: SwapKind.EXACT_IN,
            tokenIn: reserveToken,
            tokenOut: projectToken,
            amountInScaled18: 1e18,
            amountOutScaled18: 1e18,
            tokenInBalanceScaled18: poolInitAmount,
            tokenOutBalanceScaled18: poolInitAmount,
            amountCalculatedScaled18: 1e18,
            amountCalculatedRaw: 1e18,
            router: address(router),
            pool: pool,
            userData: bytes("")
        });

        // Direct call from an attacker should fail.
        vm.prank(address(0xdead));
        vm.expectRevert(abi.encodeWithSelector(IHooks.HookCallerNotAuthorized.selector, address(0xdead), pool));
        secondaryHook.onAfterSwap(fakeParams);

        // Direct call from the vault should also fail (only the pool is authorized).
        vm.prank(address(vault));
        vm.expectRevert(abi.encodeWithSelector(IHooks.HookCallerNotAuthorized.selector, address(vault), pool));
        secondaryHook.onAfterSwap(fakeParams);
    }

    /// @notice The secondary hook's onRegister is a no-op if called again with the same value.
    function testSecondaryHookCanReregisterSamePool() public {
        TokenConfig[] memory tokenConfig = vault.buildTokenConfig(
            [address(projectToken), address(reserveToken)].toMemoryArray().asIERC20()
        );

        address callerBefore = secondaryHook.getAuthorizedCaller();

        vm.prank(pool);
        bool success = secondaryHook.onRegister(
            address(lbPoolFactory),
            pool,
            tokenConfig,
            LiquidityManagement({
                disableUnbalancedLiquidity: false,
                enableAddLiquidityCustom: false,
                enableRemoveLiquidityCustom: false,
                enableDonation: false
            })
        );

        assertTrue(success, "Re-registration should succeed");
        assertEq(secondaryHook.getAuthorizedCaller(), callerBefore, "Authorized caller should not change");
    }

    /// @notice The secondary hook's onRegister cannot be called again (AuthorizedCallerAlreadySet).
    function testSecondaryHookCannotRegisterDifferentPool() public {
        TokenConfig[] memory tokenConfig = vault.buildTokenConfig(
            [address(projectToken), address(reserveToken)].toMemoryArray().asIERC20()
        );

        // A different pool trying to register should fail because _authorizedCaller is already
        // set to the original pool, and the new pool address won't match.
        address differentPool = address(0xbeef);
        vm.prank(differentPool);
        vm.expectRevert(IHooks.AuthorizedCallerAlreadySet.selector);
        secondaryHook.onRegister(
            address(lbPoolFactory),
            differentPool,
            tokenConfig,
            LiquidityManagement({
                disableUnbalancedLiquidity: false,
                enableAddLiquidityCustom: false,
                enableRemoveLiquidityCustom: false,
                enableDonation: false
            })
        );
    }

    /*******************************************************************************
                        LBP Native Hooks Still Work
    *******************************************************************************/

    /// @notice Swaps are still disabled outside the sale window.
    function testSwapsStillDisabledOutsideSale() public {
        // Before sale.
        vm.prank(bob);
        vm.expectRevert(LBPCommon.SwapsDisabled.selector);
        router.swapSingleTokenExactIn(pool, reserveToken, projectToken, 1e18, 0, MAX_UINT256, false, bytes(""));

        // After sale.
        vm.warp(block.timestamp + DEFAULT_END_OFFSET + 1);

        vm.prank(bob);
        vm.expectRevert(LBPCommon.SwapsDisabled.selector);
        router.swapSingleTokenExactIn(pool, reserveToken, projectToken, 1e18, 0, MAX_UINT256, false, bytes(""));
    }

    /// @notice Adding liquidity after the sale starts is still blocked.
    function testAddLiquidityStillBlockedAfterSaleStart() public {
        _warpToSale();

        vm.prank(bob);
        vm.expectRevert(LBPCommon.AddingLiquidityNotAllowed.selector);
        router.addLiquidityProportional(pool, [poolInitAmount, poolInitAmount].toMemoryArray(), 1e18, false, bytes(""));
    }

    /// @notice Removing liquidity during the sale is still blocked.
    function testRemoveLiquidityStillBlockedDuringSale() public {
        _warpToSale();

        vm.prank(bob);
        vm.expectRevert(LBPCommon.RemovingLiquidityNotAllowed.selector);
        router.removeLiquidityProportional(pool, 1e18, [uint256(0), uint256(0)].toMemoryArray(), false, bytes(""));
    }

    /*******************************************************************************
                        Pool Without Secondary Hook (Baseline)
    *******************************************************************************/

    /// @notice Verify that a pool without a secondary hook does not tax swaps.
    function testNoSecondaryHook_NoTax() public {
        // Create a pool without a secondary hook for comparison.
        (address plainPool, ) = _createLBPoolWithCustomWeights(
            address(0),
            startWeights[projectIdx],
            startWeights[reserveIdx],
            endWeights[projectIdx],
            endWeights[reserveIdx],
            uint32(block.timestamp + DEFAULT_START_OFFSET),
            uint32(block.timestamp + DEFAULT_END_OFFSET),
            false // allow project swaps in
        );
        _initSpecificPool(plainPool);

        _warpToSale();

        uint256 swapAmount = poolInitAmount / 100;

        uint256 reserveBefore = reserveToken.balanceOf(bob);

        vm.prank(bob);
        router.swapSingleTokenExactIn(
            plainPool,
            projectToken,
            reserveToken,
            swapAmount,
            0,
            MAX_UINT256,
            false,
            bytes("")
        );

        uint256 reserveAfter = reserveToken.balanceOf(bob);
        uint256 reserveReceived = reserveAfter - reserveBefore;

        // No hook fees taken. Compare to a taxed swap on the same-config pool.
        // The full amountOut goes to the user.
        assertGt(reserveReceived, 0, "Should receive reserve tokens");

        // Verify the hook flags don't include afterSwap.
        HookFlags memory flags = IHooks(plainPool).getHookFlags();
        assertFalse(flags.shouldCallAfterSwap, "Plain pool should not call afterSwap");
        assertFalse(flags.enableHookAdjustedAmounts, "Plain pool should not enable adjusted amounts");
    }

    /*******************************************************************************
                              Private Helpers
    *******************************************************************************/

    function _warpToSale() private {
        vm.warp(block.timestamp + DEFAULT_START_OFFSET + 1);
    }

    /// @dev Deploy the DirectionalSwapFeeTaxHook and create an LBPool with it as secondary hook.
    function _createLBPoolWithSecondaryHook(
        address poolCreator,
        uint32 startTime,
        uint32 endTime,
        bool blockProjectTokenSwapsIn
    ) internal returns (address newPool, bytes memory poolArgs) {
        // Deploy hook first (as secondary).
        secondaryHook = new DirectionalSwapFeeTaxHook(
            IVault(address(vault)),
            taxFeeToken,
            TAX_PERCENTAGE,
            bob, // hook owner
            true // isSecondaryHook
        );
        vm.label(address(secondaryHook), "DirectionalSwapFeeTaxHook");

        LBPCommonParams memory lbpCommonParams = LBPCommonParams({
            name: "LBPool",
            symbol: "LBP",
            owner: bob,
            projectToken: projectToken,
            reserveToken: reserveToken,
            startTime: startTime,
            endTime: endTime,
            blockProjectTokenSwapsIn: blockProjectTokenSwapsIn
        });

        LBPParams memory lbpParams = LBPParams({
            projectTokenStartWeight: startWeights[projectIdx],
            reserveTokenStartWeight: startWeights[reserveIdx],
            projectTokenEndWeight: endWeights[projectIdx],
            reserveTokenEndWeight: endWeights[reserveIdx],
            reserveTokenVirtualBalance: reserveTokenVirtualBalance
        });

        MigrationParams memory migrationParams;

        uint256 salt = _saltCounter++;

        newPool = lbPoolFactory.create(
            lbpCommonParams,
            lbpParams,
            swapFee,
            bytes32(salt),
            poolCreator,
            address(secondaryHook) // secondary hook
        );

        poolArgs = abi.encode(lbpCommonParams, migrationParams, lbpParams, vault, address(router), poolVersion);
    }

    /// @dev Create and init a pool that allows project token swaps in, with the secondary hook.
    function _createAndInitPoolAllowingProjectSwapIn() internal {
        (pool, ) = _createLBPoolWithSecondaryHook(
            address(0),
            uint32(block.timestamp + DEFAULT_START_OFFSET),
            uint32(block.timestamp + DEFAULT_END_OFFSET),
            false // allow project token swaps in
        );
        initPool();
    }

    /// @dev Initialize a specific pool (not the default `pool` variable).
    function _initSpecificPool(address targetPool) internal {
        address originalPool = pool;
        pool = targetPool;
        initPool();
        pool = originalPool;
    }
}
