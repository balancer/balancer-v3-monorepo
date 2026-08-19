// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { stdError } from "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import {
    ICompositeLiquidityRouterErrors
} from "@balancer-labs/v3-interfaces/contracts/vault/ICompositeLiquidityRouterErrors.sol";
import { IVaultAdmin } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultAdmin.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { ERC4626TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC4626TestToken.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { RevertCodec } from "@balancer-labs/v3-solidity-utils/contracts/helpers/RevertCodec.sol";

import { BalancerPoolToken } from "../../contracts/BalancerPoolToken.sol";
import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

/**
 * @notice Proportional liquidity on an ERC4626 pool at the Vault minimums the deployed Vaults actually report.
 * @dev `BaseVaultTest` defaults to a minimum wrap amount of 1 and no minimum trade amount, so no other flat
 * composite router suite can reach the band in which the buffer refuses a non-zero amount. This one raises both and
 * pins what happens across that band, on the way out and on the way in.
 *
 * The amount handed to the buffer is the pool's rather than the caller's in both directions: on a removal it is that
 * token's share of the burned pool tokens, and on an addition it is what the pool requires for the pool tokens
 * requested. Where the buffer will not serve it, the router reports the refusal in the terms of the operation the
 * caller asked for: `UnwrapAmountTooSmall` for a removal, naming the amount that was available, and
 * `RequiredWrapAmountTooSmall` for an addition, naming the amount the pool required. Neither substitutes an asset,
 * and neither takes more than the caller allowed.
 *
 * Note that the boundary is a property of the wrapper and is not `getMinimumWrapAmount()`, and that it is not the
 * same in the two directions. `erc4626BufferWrapOrUnwrap` applies that minimum twice: to the amount it is given, and
 * to the amount it calculates. Unwrapping calculates `previewRedeem(amount - 1) - 1`, so at a redeem rate of exactly
 * one the first accepted amount is two above the stated minimum; wrapping calculates `previewMint(amount + 1) + 1`,
 * which is the larger number at that same rate, so the boundary is the stated minimum itself. A rate below one
 * pushes both boundaries well above the stated minimum, and a rate above one leaves the wrap boundary where it is
 * while lowering the unwrap boundary to the stated minimum. All of these are exercised below.
 */
contract CompositeLiquidityRouterERC4626PoolMinWrapAmountTest is BaseVaultTest {
    using ArrayHelpers for *;
    using FixedPoint for *;

    // Value reported by the Vault on every chain it is deployed to.
    uint256 private constant _PRODUCTION_MIN_WRAP_AMOUNT = 1e4;

    // Smallest raw wrapped amount the buffer accepts, at a redeem rate of exactly one.
    uint256 private constant _FIRST_ACCEPTED_RAW = _PRODUCTION_MIN_WRAP_AMOUNT + 2;

    uint256 private constant _WA6_POOL_BALANCE = 1e6; // 1.0 unit of a 6-decimal wrapper
    uint256 private constant _WADAI_POOL_BALANCE = 1e6 * 1e18;
    uint256 private constant _WA6_BUFFER_UNDERLYING = 1e5 * 1e6;

    ERC4626TestToken private _wa6;

    uint256 private _wa6Idx;
    uint256 private _waDaiIdx;

    function setUp() public override {
        vaultMockMinTradeAmount = PRODUCTION_MIN_TRADE_AMOUNT;
        vaultMockMinWrapAmount = _PRODUCTION_MIN_WRAP_AMOUNT;

        BaseVaultTest.setUp();

        authorizer.grantRole(vault.getActionId(IVaultAdmin.pauseVaultBuffers.selector), admin);
    }

    function createPool() internal override returns (address newPool, bytes memory poolArgs) {
        _wa6 = createERC4626("Wrapped USDC-6", "wa6", 6, usdc6Decimals);

        (_wa6Idx, _waDaiIdx) = getSortedIndexes(address(_wa6), address(waDAI));

        return _createPool([address(_wa6), address(waDAI)].toMemoryArray(), "minWrapPool");
    }

    function initPool() internal override {
        // The wrapper is created inside `createPool`, after the base approvals ran, so it needs its own.
        for (uint256 i = 0; i < users.length; ++i) {
            vm.startPrank(users[i]);
            usdc6Decimals.approve(address(_wa6), type(uint256).max);
            _wa6.approve(address(permit2), type(uint256).max);
            permit2.approve(address(_wa6), address(router), type(uint160).max, type(uint48).max);
            permit2.approve(address(_wa6), address(bufferRouter), type(uint160).max, type(uint48).max);
            permit2.approve(address(_wa6), address(compositeLiquidityRouter), type(uint160).max, type(uint48).max);
            vm.stopPrank();
        }

        vm.startPrank(lp);
        _wa6.deposit(_WA6_BUFFER_UNDERLYING + _WA6_POOL_BALANCE, lp);
        bufferRouter.initializeBuffer(_wa6, _WA6_BUFFER_UNDERLYING, _wa6.previewDeposit(_WA6_BUFFER_UNDERLYING), 0);
        bufferRouter.initializeBuffer(waDAI, _WA6_BUFFER_UNDERLYING * 1e12, waDAI.previewDeposit(1e5 * 1e18), 0);

        uint256[] memory amountsIn = new uint256[](2);
        amountsIn[_wa6Idx] = _WA6_POOL_BALANCE;
        amountsIn[_waDaiIdx] = _WADAI_POOL_BALANCE;

        _initPool(pool, amountsIn, 0);
        vm.stopPrank();
    }

    /***************************************************************************
                        The band: what a caller sees, and why
    ***************************************************************************/

    /**
     * @dev Every non-zero amount the buffer will not unwrap fails as a router error naming the token and the amount,
     * rather than as the Vault's `WrapAmountTooSmall`, which names only the token. The two amounts at the stated
     * minimum itself are the reason a router-side check against `getMinimumWrapAmount()` would be wrong.
     */
    function testSubMinimumUnwrapRevertsWithRouterError() public {
        uint256[4] memory rawTargets = [
            uint256(1),
            _PRODUCTION_MIN_WRAP_AMOUNT - 1,
            _PRODUCTION_MIN_WRAP_AMOUNT,
            _FIRST_ACCEPTED_RAW - 1
        ];

        for (uint256 i = 0; i < rawTargets.length; ++i) {
            uint256 bptIn = _burnForRawWa6(rawTargets[i]);
            assertEq(_rawAmountsOut(bptIn)[_wa6Idx], rawTargets[i], "Setup: wrong raw wa6 amount");

            uint256 snapshotId = vm.snapshotState();

            uint256 bptBefore = BalancerPoolToken(pool).balanceOf(lp);
            uint256 wa6Before = _wa6.balanceOf(lp);
            uint256 usdcBefore = usdc6Decimals.balanceOf(lp);

            vm.prank(lp);
            vm.expectRevert(
                abi.encodeWithSelector(
                    ICompositeLiquidityRouterErrors.UnwrapAmountTooSmall.selector,
                    address(_wa6),
                    rawTargets[i]
                )
            );
            compositeLiquidityRouter.removeLiquidityProportionalFromERC4626Pool(
                pool,
                _unwrapBoth(),
                bptIn,
                new uint256[](2),
                false,
                bytes("")
            );

            // Nothing partial is left behind, and in particular no wrapped token is handed over in place of the
            // underlying the caller asked for.
            assertEq(BalancerPoolToken(pool).balanceOf(lp), bptBefore, "BPT was burned");
            assertEq(_wa6.balanceOf(lp), wa6Before, "The wrapped token was delivered");
            assertEq(usdc6Decimals.balanceOf(lp), usdcBefore, "The underlying token was delivered");

            vm.revertToState(snapshotId);
        }
    }

    /// @dev The query reverts with the identical error, so a caller learns this without spending a transaction.
    function testSubMinimumUnwrapQueryMatchesExecution() public {
        uint256[2] memory rawTargets = [uint256(1), _FIRST_ACCEPTED_RAW - 1];

        for (uint256 i = 0; i < rawTargets.length; ++i) {
            uint256 bptIn = _burnForRawWa6(rawTargets[i]);

            uint256 snapshotId = vm.snapshotState();

            _prankStaticCall();
            vm.expectRevert(
                abi.encodeWithSelector(
                    ICompositeLiquidityRouterErrors.UnwrapAmountTooSmall.selector,
                    address(_wa6),
                    rawTargets[i]
                )
            );
            compositeLiquidityRouter.queryRemoveLiquidityProportionalFromERC4626Pool(
                pool,
                _unwrapBoth(),
                bptIn,
                lp,
                bytes("")
            );

            vm.revertToState(snapshotId);
        }
    }

    /**
     * @dev A redeem rate below one moves the boundary far above the Vault's stated minimum, because the second check
     * lands on the underlying output. At a rate of one half, a raw wrapped amount of 15000 clears the stated minimum
     * of 10000 and is still refused, since it redeems for roughly 7500. This is the case a router-side check written
     * against `getMinimumWrapAmount()` would wave through, and it is why the failure is read from the Vault's own
     * verdict rather than predicted here.
     */
    function testBelowParRateRefusesAmountAboveTheStatedMinimum() public {
        _wa6.mockRate(FixedPoint.ONE / 2);
        assertLt(_wa6.getRate(), FixedPoint.ONE, "Setup: the rate did not fall below one");

        uint256 rawTarget = 15000;
        assertGt(rawTarget, vault.getMinimumWrapAmount(), "Setup: the target is not above the stated minimum");

        uint256 bptIn = _burnForRawWa6(rawTarget);
        assertEq(_rawAmountsOut(bptIn)[_wa6Idx], rawTarget, "Setup: wrong raw wa6 amount");

        vm.prank(lp);
        vm.expectRevert(
            abi.encodeWithSelector(
                ICompositeLiquidityRouterErrors.UnwrapAmountTooSmall.selector,
                address(_wa6),
                rawTarget
            )
        );
        compositeLiquidityRouter.removeLiquidityProportionalFromERC4626Pool(
            pool,
            _unwrapBoth(),
            bptIn,
            new uint256[](2),
            false,
            bytes("")
        );
    }

    /**
     * @dev A redeem rate above one goes the other way: the second check is slack, so the first accepted amount falls
     * back to the Vault's stated minimum, two below what the same pool accepts at a rate of one.
     */
    function testRateAboveOneMovesTheBoundaryToTheStatedMinimum() public {
        _wa6.mockRate(2 * FixedPoint.ONE);
        assertGt(_wa6.getRate(), FixedPoint.ONE, "Setup: the rate did not rise above one");

        uint256 refusedBptIn = _burnForRawWa6(_PRODUCTION_MIN_WRAP_AMOUNT - 1);
        uint256 acceptedBptIn = _burnForRawWa6(_PRODUCTION_MIN_WRAP_AMOUNT);

        uint256 snapshotId = vm.snapshotState();

        vm.prank(lp);
        vm.expectRevert(
            abi.encodeWithSelector(
                ICompositeLiquidityRouterErrors.UnwrapAmountTooSmall.selector,
                address(_wa6),
                _PRODUCTION_MIN_WRAP_AMOUNT - 1
            )
        );
        compositeLiquidityRouter.removeLiquidityProportionalFromERC4626Pool(
            pool,
            _unwrapBoth(),
            refusedBptIn,
            new uint256[](2),
            false,
            bytes("")
        );

        vm.revertToState(snapshotId);

        // At a rate of one this same amount reverts; see `testSubMinimumUnwrapRevertsWithRouterError`.
        vm.prank(lp);
        uint256[] memory amountsOut = compositeLiquidityRouter.removeLiquidityProportionalFromERC4626Pool(
            pool,
            _unwrapBoth(),
            acceptedBptIn,
            new uint256[](2),
            false,
            bytes("")
        );

        assertGt(amountsOut[_wa6Idx], _PRODUCTION_MIN_WRAP_AMOUNT, "The stated minimum was not accepted");
    }

    /***************************************************************************
                                    Boundaries
    ***************************************************************************/

    /// @dev Zero is not the failing case: it is returned as zero of the underlying, and the withdrawal succeeds.
    function testZeroUnwrapLegSucceeds() public {
        uint256 bptIn = _burnForRawWa6(0);
        assertEq(_rawAmountsOut(bptIn)[_wa6Idx], 0, "Setup: wa6 leg should be exactly zero");

        uint256 wa6Before = _wa6.balanceOf(lp);

        vm.prank(lp);
        uint256[] memory amountsOut = compositeLiquidityRouter.removeLiquidityProportionalFromERC4626Pool(
            pool,
            _unwrapBoth(),
            bptIn,
            new uint256[](2),
            false,
            bytes("")
        );

        assertEq(amountsOut[_wa6Idx], 0, "Zero leg should report zero");
        assertGt(amountsOut[_waDaiIdx], 0, "DAI leg should be non-zero");
        assertEq(_wa6.balanceOf(lp), wa6Before, "The wrapped token was delivered for the zero leg");
    }

    /// @dev A zero leg is still measured against the caller's own limit, on the underlying axis.
    function testZeroUnwrapLegWithNonZeroLimitReverts() public {
        uint256 bptIn = _burnForRawWa6(0);

        uint256[] memory minAmountsOut = new uint256[](2);
        minAmountsOut[_wa6Idx] = 1;

        vm.prank(lp);
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.AmountOutBelowMin.selector, address(usdc6Decimals), 0, 1));
        compositeLiquidityRouter.removeLiquidityProportionalFromERC4626Pool(
            pool,
            _unwrapBoth(),
            bptIn,
            minAmountsOut,
            false,
            bytes("")
        );
    }

    /**
     * @dev The router error is not the only way this band fails, and the interface says so. Where the wrapped amount
     * clears the Vault's stated minimum but the underlying it redeems to does not, the buffer checks the caller's own
     * limit first (`Vault.erc4626BufferWrapOrUnwrap` tests `limitRaw` before applying the minimum to the calculated
     * output), so a caller carrying a limit the leg cannot meet is told that instead.
     */
    function testLimitOnASubMinimumLegIsReportedFirst() public {
        uint256 bptIn = _burnForRawWa6(_PRODUCTION_MIN_WRAP_AMOUNT);

        uint256[] memory minAmountsOut = new uint256[](2);
        minAmountsOut[_wa6Idx] = _PRODUCTION_MIN_WRAP_AMOUNT;

        // The unwrap deducts two wei, so the leg redeems to two below the minimum and misses the limit as well.
        vm.prank(lp);
        vm.expectRevert(
            abi.encodeWithSelector(
                IVaultErrors.SwapLimit.selector,
                _PRODUCTION_MIN_WRAP_AMOUNT - 2,
                _PRODUCTION_MIN_WRAP_AMOUNT
            )
        );
        compositeLiquidityRouter.removeLiquidityProportionalFromERC4626Pool(
            pool,
            _unwrapBoth(),
            bptIn,
            minAmountsOut,
            false,
            bytes("")
        );
    }

    /// @dev The first accepted amount, and an ordinary amount above it. The unwrap deducts two wei.
    function testAcceptedAmountsAreUnaffected() public {
        uint256[2] memory rawTargets = [_FIRST_ACCEPTED_RAW, uint256(20000)];

        for (uint256 i = 0; i < rawTargets.length; ++i) {
            uint256 bptIn = _burnForRawWa6(rawTargets[i]);
            assertEq(_rawAmountsOut(bptIn)[_wa6Idx], rawTargets[i], "Setup: wrong raw wa6 amount");

            uint256 snapshotId = vm.snapshotState();

            vm.prank(lp);
            uint256[] memory amountsOut = compositeLiquidityRouter.removeLiquidityProportionalFromERC4626Pool(
                pool,
                _unwrapBoth(),
                bptIn,
                new uint256[](2),
                false,
                bytes("")
            );

            assertEq(amountsOut[_wa6Idx], rawTargets[i] - 2, "USDC-6 leg is wrong");
            assertGt(amountsOut[_waDaiIdx], 0, "DAI leg should be non-zero");

            vm.revertToState(snapshotId);
        }
    }

    /// @dev `minAmountsOut` is denominated in what the caller receives, so a query result is directly reusable.
    function testQueryResultIsExecutableAsLimits() public {
        uint256 bptIn = _burnForRawWa6(20000);

        uint256 snapshotId = vm.snapshotState();
        _prankStaticCall();
        uint256[] memory queried = compositeLiquidityRouter.queryRemoveLiquidityProportionalFromERC4626Pool(
            pool,
            _unwrapBoth(),
            bptIn,
            lp,
            bytes("")
        );
        vm.revertToState(snapshotId);

        vm.prank(lp);
        uint256[] memory amountsOut = compositeLiquidityRouter.removeLiquidityProportionalFromERC4626Pool(
            pool,
            _unwrapBoth(),
            bptIn,
            queried,
            false,
            bytes("")
        );

        assertEq(amountsOut[_wa6Idx], queried[_wa6Idx], "USDC-6 leg does not match the query");
        assertEq(amountsOut[_waDaiIdx], queried[_waDaiIdx], "DAI leg does not match the query");
    }

    /***************************************************************************
                                    Controls
    ***************************************************************************/

    /// @dev The documented remedy, executed: clearing the flag returns the same value as the wrapped token.
    function testUnwrapFlagClearedIsUnaffected() public {
        uint256 rawTarget = _FIRST_ACCEPTED_RAW - 1;
        uint256 bptIn = _burnForRawWa6(rawTarget);

        uint256 wa6Before = _wa6.balanceOf(lp);

        vm.prank(lp);
        uint256[] memory amountsOut = compositeLiquidityRouter.removeLiquidityProportionalFromERC4626Pool(
            pool,
            new bool[](2),
            bptIn,
            new uint256[](2),
            false,
            bytes("")
        );

        assertEq(amountsOut[_wa6Idx], rawTarget, "The wrapped leg should be paid in full");
        assertEq(_wa6.balanceOf(lp) - wa6Before, rawTarget, "The wrapped token did not arrive");
    }

    /// @dev A failure that is not this one keeps the Vault's own error rather than being reported as too small.
    function testOtherBufferFailuresAreNotReinterpreted() public {
        uint256 bptIn = _burnForRawWa6(20000);

        vm.prank(admin);
        IVaultAdmin(address(vault)).pauseVaultBuffers();

        vm.prank(lp);
        vm.expectRevert(IVaultErrors.VaultBuffersArePaused.selector);
        compositeLiquidityRouter.removeLiquidityProportionalFromERC4626Pool(
            pool,
            _unwrapBoth(),
            bptIn,
            new uint256[](2),
            false,
            bytes("")
        );
    }

    /**
     * @dev A failure carrying no selector to read is not this one either. The wrapper is made to revert with no
     * data at all, which is what an out-of-gas sub-call also produces; the point of the assertion is that the
     * operation does not come back as a too-small amount, since nothing established that.
     */
    function testShortRevertDataIsNotReinterpreted() public {
        uint256 bptIn = _burnForRawWa6(20000);

        vm.mockCallRevert(address(_wa6), abi.encodeWithSelector(IERC4626.previewRedeem.selector), bytes(""));

        vm.prank(lp);
        vm.expectRevert(RevertCodec.ErrorSelectorNotFound.selector);
        compositeLiquidityRouter.removeLiquidityProportionalFromERC4626Pool(
            pool,
            _unwrapBoth(),
            bptIn,
            new uint256[](2),
            false,
            bytes("")
        );
    }

    /**
     * @dev Where a share is worth less than one raw unit of the underlying, the Vault's own arithmetic reverts
     * before either minimum has anything to say: it computes the output as `previewRedeem(amount - 1) - 1`, which
     * underflows when the preview returns zero. That is the Vault's, not this router's, and it must stay visible
     * as what it is rather than be reported as an amount too small to unwrap.
     */
    function testArithmeticPanicIsNotReinterpreted() public {
        uint256 bptIn = _burnForRawWa6(20000);

        vm.mockCall(address(_wa6), abi.encodeWithSelector(IERC4626.previewRedeem.selector), abi.encode(uint256(0)));

        vm.prank(lp);
        vm.expectRevert(stdError.arithmeticError);
        compositeLiquidityRouter.removeLiquidityProportionalFromERC4626Pool(
            pool,
            _unwrapBoth(),
            bptIn,
            new uint256[](2),
            false,
            bytes("")
        );
    }

    /// @dev The prepaid variant shares this path exactly; only how the BPT is approved differs.
    function testPrepaidRouterBehavesIdentically() public {
        uint256 rawTarget = _FIRST_ACCEPTED_RAW - 1;
        uint256 bptIn = _burnForRawWa6(rawTarget);

        vm.startPrank(lp);
        BalancerPoolToken(pool).approve(address(prepaidCompositeLiquidityRouter), bptIn);

        vm.expectRevert(
            abi.encodeWithSelector(
                ICompositeLiquidityRouterErrors.UnwrapAmountTooSmall.selector,
                address(_wa6),
                rawTarget
            )
        );
        prepaidCompositeLiquidityRouter.removeLiquidityProportionalFromERC4626Pool(
            pool,
            _unwrapBoth(),
            bptIn,
            new uint256[](2),
            false,
            bytes("")
        );
        vm.stopPrank();
    }

    /**
     * @dev The nested remove path is a separate entry point onto the same pool, and it reports the same condition the
     * same way: the same token, the same amount, the same error. Driven from the same pool at the same burn as
     * `testSubMinimumUnwrapRevertsWithRouterError`, so the entry point is the only variable.
     */
    function testNestedPathReportsTheSameError() public {
        uint256 rawTarget = _FIRST_ACCEPTED_RAW - 1;
        uint256 bptIn = _burnForRawWa6(rawTarget);

        (uint256 usdc6Idx, uint256 daiIdx) = getSortedIndexes(address(usdc6Decimals), address(dai));

        address[] memory tokensOut = new address[](2);
        tokensOut[usdc6Idx] = address(usdc6Decimals);
        tokensOut[daiIdx] = address(dai);

        address[] memory tokensToUnwrap = new address[](2);
        tokensToUnwrap[0] = address(_wa6);
        tokensToUnwrap[1] = address(waDAI);

        bytes memory expectedError = abi.encodeWithSelector(
            ICompositeLiquidityRouterErrors.UnwrapAmountTooSmall.selector,
            address(_wa6),
            rawTarget
        );

        uint256 snapshotId = vm.snapshotState();

        vm.prank(lp);
        vm.expectRevert(expectedError);
        compositeLiquidityRouter.removeLiquidityProportionalNestedPool(
            pool,
            bptIn,
            tokensOut,
            new uint256[](2),
            tokensToUnwrap,
            false,
            bytes("")
        );

        vm.revertToState(snapshotId);

        vm.prank(lp);
        vm.expectRevert(expectedError);
        compositeLiquidityRouter.removeLiquidityProportionalFromERC4626Pool(
            pool,
            _unwrapBoth(),
            bptIn,
            new uint256[](2),
            false,
            bytes("")
        );
    }

    /**
     * @dev Recovery Mode does not widen what this router can reach. The composite router carries no Recovery Mode
     * handling, so an unpaused pool in Recovery Mode is served by the ordinary removal path, which applies the
     * Vault's trade-amount floor; a recovery withdrawal applies no floor at all. So a burn small enough to put the
     * 18-decimal leg inside the sub-minimum band never reaches the buffer through this router, and the amount is
     * reachable only through the plain Router, which does not unwrap.
     */
    function testRecoveryModeDoesNotWidenTheBand() public {
        vault.manualEnableRecoveryMode(pool);

        uint256 bptIn = _burnForRawWaDaiRecovery(_PRODUCTION_MIN_WRAP_AMOUNT - 1);

        uint256 snapshotId = vm.snapshotState();
        _prankStaticCall();
        uint256[] memory recoveryAmountsOut = router.queryRemoveLiquidityRecovery(pool, bptIn);
        vm.revertToState(snapshotId);

        // The amount really is inside the band: non-zero, and below anything the buffer would unwrap.
        assertGt(recoveryAmountsOut[_waDaiIdx], 0, "Setup: the waDAI leg is zero");
        assertLt(
            recoveryAmountsOut[_waDaiIdx],
            vault.getMinimumWrapAmount(),
            "Setup: the waDAI leg is not in the band"
        );

        // Through the composite router the burn is rejected by the ordinary path's trade-amount floor, before any
        // buffer call. Before Recovery Mode handling was removed from this router, the same call reached the buffer
        // and failed there instead.
        vm.prank(lp);
        vm.expectRevert(IVaultErrors.TradeAmountTooSmall.selector);
        compositeLiquidityRouter.removeLiquidityProportionalFromERC4626Pool(
            pool,
            _unwrapBoth(),
            bptIn,
            new uint256[](2),
            false,
            bytes("")
        );

        // The capability is not lost: the plain Router pays the registered wrapped tokens, with no floor and no
        // buffer call, and an ERC4626 share redeems against its own protocol afterward.
        vm.prank(lp);
        uint256[] memory wrappedAmountsOut = router.removeLiquidityRecovery(pool, bptIn, new uint256[](2));

        assertEq(wrappedAmountsOut[_waDaiIdx], recoveryAmountsOut[_waDaiIdx], "Wrong waDAI amount out");
    }

    /***************************************************************************
                    Proportional add: the amount the pool requires
    ***************************************************************************/

    /**
     * @dev The mirror of the removal case. The wrapped amount here is not one the caller chose either: it is what the
     * pool requires for the pool tokens requested, and the caller reaches it only through `exactBptAmountOut`. Where
     * the buffer will not wrap it, the operation fails with a router error naming the token and that amount, rather
     * than with the Vault's `WrapAmountTooSmall`, which names only the token.
     */
    function testSubMinimumWrapRevertsWithRouterError() public {
        uint256[3] memory rawTargets = [uint256(1), _PRODUCTION_MIN_WRAP_AMOUNT - 2, _PRODUCTION_MIN_WRAP_AMOUNT - 1];

        for (uint256 i = 0; i < rawTargets.length; ++i) {
            uint256 bptOut = _mintForRawWa6(rawTargets[i]);
            uint256[] memory required = _rawAmountsIn(bptOut);
            assertEq(required[_wa6Idx], rawTargets[i], "Setup: wrong required raw wa6 amount");

            uint256 snapshotId = vm.snapshotState();

            uint256 bptBefore = BalancerPoolToken(pool).balanceOf(lp);
            uint256 wa6Before = _wa6.balanceOf(lp);
            uint256 usdcBefore = usdc6Decimals.balanceOf(lp);
            uint256 daiBefore = dai.balanceOf(lp);

            vm.prank(lp);
            vm.expectRevert(
                abi.encodeWithSelector(
                    ICompositeLiquidityRouterErrors.RequiredWrapAmountTooSmall.selector,
                    address(_wa6),
                    rawTargets[i]
                )
            );
            compositeLiquidityRouter.addLiquidityProportionalToERC4626Pool(
                pool,
                _wrapBoth(),
                _generousMaxAmountsIn(required),
                bptOut,
                false,
                bytes("")
            );

            // The caller keeps their own assets: nothing was charged, in either denomination, and no wrapped token
            // was taken in place of the underlying they offered.
            assertEq(BalancerPoolToken(pool).balanceOf(lp), bptBefore, "Pool tokens were minted");
            assertEq(_wa6.balanceOf(lp), wa6Before, "The wrapped token was charged");
            assertEq(usdc6Decimals.balanceOf(lp), usdcBefore, "The underlying token was charged");
            assertEq(dai.balanceOf(lp), daiBefore, "The other leg was charged");

            vm.revertToState(snapshotId);
        }
    }

    /// @dev The query reverts with the identical error, so a caller learns this without spending a transaction.
    function testSubMinimumWrapQueryMatchesExecution() public {
        uint256[2] memory rawTargets = [uint256(1), _PRODUCTION_MIN_WRAP_AMOUNT - 1];

        for (uint256 i = 0; i < rawTargets.length; ++i) {
            uint256 bptOut = _mintForRawWa6(rawTargets[i]);

            uint256 snapshotId = vm.snapshotState();

            _prankStaticCall();
            vm.expectRevert(
                abi.encodeWithSelector(
                    ICompositeLiquidityRouterErrors.RequiredWrapAmountTooSmall.selector,
                    address(_wa6),
                    rawTargets[i]
                )
            );
            compositeLiquidityRouter.queryAddLiquidityProportionalToERC4626Pool(
                pool,
                _wrapBoth(),
                bptOut,
                lp,
                bytes("")
            );

            vm.revertToState(snapshotId);
        }
    }

    /**
     * @dev This path's boundary is a property of the wrapper too, and it moves the other way from the removal path's.
     * Wrapping costs `previewMint(amount + 1) + 1` of the underlying, so a rate below one makes the underlying cost
     * the smaller number, and the Vault's second check lands on it: at a rate of one half a required amount of 15000
     * clears the stated minimum of 10000 and is still refused, and the first accepted amount is about twice the
     * stated minimum. This is the case a router-side check against `getMinimumWrapAmount()` would wave through.
     */
    function testBelowParRateRefusesWrapAmountAboveTheStatedMinimum() public {
        _wa6.mockRate(FixedPoint.ONE / 2);
        assertLt(_wa6.getRate(), FixedPoint.ONE, "Setup: the rate did not fall below one");

        uint256 refusedTarget = 15000;
        assertGt(refusedTarget, vault.getMinimumWrapAmount(), "Setup: the target is not above the stated minimum");

        uint256 refusedBptOut = _mintForRawWa6(refusedTarget);
        uint256[] memory refusedMaxAmountsIn = _generousMaxAmountsIn(_rawAmountsIn(refusedBptOut));
        assertEq(_rawAmountsIn(refusedBptOut)[_wa6Idx], refusedTarget, "Setup: wrong required raw wa6 amount");

        uint256 snapshotId = vm.snapshotState();

        vm.prank(lp);
        vm.expectRevert(
            abi.encodeWithSelector(
                ICompositeLiquidityRouterErrors.RequiredWrapAmountTooSmall.selector,
                address(_wa6),
                refusedTarget
            )
        );
        compositeLiquidityRouter.addLiquidityProportionalToERC4626Pool(
            pool,
            _wrapBoth(),
            refusedMaxAmountsIn,
            refusedBptOut,
            false,
            bytes("")
        );

        vm.revertToState(snapshotId);

        // Roughly twice the stated minimum, which is where the underlying cost first reaches it.
        uint256 acceptedBptOut = _mintForRawWa6(19995);
        uint256[] memory acceptedMaxAmountsIn = _generousMaxAmountsIn(_rawAmountsIn(acceptedBptOut));
        assertEq(_rawAmountsIn(acceptedBptOut)[_wa6Idx], 19995, "Setup: wrong accepted raw wa6 amount");

        vm.prank(lp);
        uint256[] memory amountsIn = compositeLiquidityRouter.addLiquidityProportionalToERC4626Pool(
            pool,
            _wrapBoth(),
            acceptedMaxAmountsIn,
            acceptedBptOut,
            false,
            bytes("")
        );

        assertEq(amountsIn[_wa6Idx], _PRODUCTION_MIN_WRAP_AMOUNT, "The accepted amount cost the wrong underlying");
    }

    /**
     * @dev A rate above one goes the other way: the underlying cost is the larger number, so the second check is
     * slack and the boundary is the Vault's stated minimum, which is also where it sits at a rate of exactly one.
     */
    function testRateAboveOneLeavesTheWrapBoundaryAtTheStatedMinimum() public {
        _wa6.mockRate(2 * FixedPoint.ONE);
        assertGt(_wa6.getRate(), FixedPoint.ONE, "Setup: the rate did not rise above one");

        uint256 refusedBptOut = _mintForRawWa6(_PRODUCTION_MIN_WRAP_AMOUNT - 1);
        uint256 acceptedBptOut = _mintForRawWa6(_PRODUCTION_MIN_WRAP_AMOUNT);

        uint256[] memory refusedMaxAmountsIn = _generousMaxAmountsIn(_rawAmountsIn(refusedBptOut));
        uint256[] memory acceptedMaxAmountsIn = _generousMaxAmountsIn(_rawAmountsIn(acceptedBptOut));

        uint256 snapshotId = vm.snapshotState();

        vm.prank(lp);
        vm.expectRevert(
            abi.encodeWithSelector(
                ICompositeLiquidityRouterErrors.RequiredWrapAmountTooSmall.selector,
                address(_wa6),
                _PRODUCTION_MIN_WRAP_AMOUNT - 1
            )
        );
        compositeLiquidityRouter.addLiquidityProportionalToERC4626Pool(
            pool,
            _wrapBoth(),
            refusedMaxAmountsIn,
            refusedBptOut,
            false,
            bytes("")
        );

        vm.revertToState(snapshotId);

        vm.prank(lp);
        uint256[] memory amountsIn = compositeLiquidityRouter.addLiquidityProportionalToERC4626Pool(
            pool,
            _wrapBoth(),
            acceptedMaxAmountsIn,
            acceptedBptOut,
            false,
            bytes("")
        );

        assertGt(amountsIn[_wa6Idx], _PRODUCTION_MIN_WRAP_AMOUNT, "The stated minimum was not accepted");
    }

    /**
     * @dev The router error is not the only way this band fails, and the interface says so. The buffer tests the
     * caller's own limit before applying the minimum to the amount it calculates, so where the required wrapped
     * amount clears the stated minimum but the underlying it costs does not, a caller whose `maxAmountsIn` is below
     * that cost is told `SwapLimit` instead. The caller's limit stays authoritative either way.
     */
    function testWrapLimitIsReportedFirst() public {
        _wa6.mockRate(FixedPoint.ONE / 2);

        uint256 bptOut = _mintForRawWa6(_PRODUCTION_MIN_WRAP_AMOUNT);
        uint256[] memory required = _rawAmountsIn(bptOut);

        // 10000 shares cost 5002 underlying at this rate, which is below the stated minimum.
        uint256[] memory maxAmountsIn = _generousMaxAmountsIn(required);
        maxAmountsIn[_wa6Idx] = 5000;

        vm.prank(lp);
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.SwapLimit.selector, 5002, 5000));
        compositeLiquidityRouter.addLiquidityProportionalToERC4626Pool(
            pool,
            _wrapBoth(),
            maxAmountsIn,
            bptOut,
            false,
            bytes("")
        );
    }

    /**
     * @dev Zero is not reachable one leg at a time on this path: the proportional math rounds up, so a token's share
     * is zero only when every share is, which is to say when no pool tokens were requested. That case makes no buffer
     * call at all and moves nothing, which is what the non-zero test in front of the wrap is for.
     */
    function testZeroPoolTokensOutIsANoOp() public {
        uint256[] memory maxAmountsIn = new uint256[](2);
        maxAmountsIn[_wa6Idx] = 1e6;
        maxAmountsIn[_waDaiIdx] = 1e18;

        uint256 bptBefore = BalancerPoolToken(pool).balanceOf(lp);
        uint256 usdcBefore = usdc6Decimals.balanceOf(lp);
        uint256 daiBefore = dai.balanceOf(lp);

        vm.prank(lp);
        uint256[] memory amountsIn = compositeLiquidityRouter.addLiquidityProportionalToERC4626Pool(
            pool,
            _wrapBoth(),
            maxAmountsIn,
            0,
            false,
            bytes("")
        );

        assertEq(amountsIn[_wa6Idx], 0, "The wrapped leg charged something");
        assertEq(amountsIn[_waDaiIdx], 0, "The other leg charged something");
        assertEq(BalancerPoolToken(pool).balanceOf(lp), bptBefore, "Pool tokens were minted");
        assertEq(usdc6Decimals.balanceOf(lp), usdcBefore, "The underlying token was charged");
        assertEq(dai.balanceOf(lp), daiBefore, "The other underlying token was charged");
    }

    /// @dev The first accepted amount and one above it, which cost what they cost before: two wei over the amount.
    function testAcceptedAddsAreUnaffected() public {
        uint256[2] memory rawTargets = [_PRODUCTION_MIN_WRAP_AMOUNT, uint256(20000)];

        for (uint256 i = 0; i < rawTargets.length; ++i) {
            uint256 bptOut = _mintForRawWa6(rawTargets[i]);
            uint256[] memory required = _rawAmountsIn(bptOut);
            assertEq(required[_wa6Idx], rawTargets[i], "Setup: wrong required raw wa6 amount");

            uint256 snapshotId = vm.snapshotState();

            uint256[] memory maxAmountsIn = _generousMaxAmountsIn(required);
            uint256 usdcBefore = usdc6Decimals.balanceOf(lp);

            vm.prank(lp);
            uint256[] memory amountsIn = compositeLiquidityRouter.addLiquidityProportionalToERC4626Pool(
                pool,
                _wrapBoth(),
                maxAmountsIn,
                bptOut,
                false,
                bytes("")
            );

            // Wrapping adds one wei to the amount given and one to the preview result.
            assertEq(amountsIn[_wa6Idx], rawTargets[i] + 2, "The wrapped leg cost the wrong underlying");

            // Nothing beyond what the leg cost is kept: the rest of the limit comes back.
            assertEq(usdcBefore - usdc6Decimals.balanceOf(lp), rawTargets[i] + 2, "More than the cost was charged");

            vm.revertToState(snapshotId);
        }
    }

    /// @dev The documented remedy, executed: clearing the flag pays the wrapper directly, with no buffer call.
    function testWrapFlagClearedIsUnaffected() public {
        uint256 rawTarget = _PRODUCTION_MIN_WRAP_AMOUNT - 1;
        uint256 bptOut = _mintForRawWa6(rawTarget);
        uint256[] memory required = _rawAmountsIn(bptOut);

        // The pool init spent every share the sender held, so paying the wrapper needs some minted first.
        vm.prank(lp);
        _wa6.deposit(2 * required[_wa6Idx], lp);

        uint256 wa6Before = _wa6.balanceOf(lp);

        // Exact limits: nothing is wrapped, so the leg costs precisely what the pool requires.
        vm.prank(lp);
        uint256[] memory amountsIn = compositeLiquidityRouter.addLiquidityProportionalToERC4626Pool(
            pool,
            new bool[](2),
            required,
            bptOut,
            false,
            bytes("")
        );

        assertEq(amountsIn[_wa6Idx], rawTarget, "The wrapped leg should be charged in full");
        assertEq(wa6Before - _wa6.balanceOf(lp), rawTarget, "The wrapped token was not taken");
    }

    /// @dev A failure that is not this one keeps the Vault's own error rather than being reported as too small.
    function testAddOtherBufferFailuresAreNotReinterpreted() public {
        uint256 bptOut = _mintForRawWa6(20000);
        uint256[] memory required = _rawAmountsIn(bptOut);

        vm.prank(admin);
        IVaultAdmin(address(vault)).pauseVaultBuffers();

        vm.prank(lp);
        vm.expectRevert(IVaultErrors.VaultBuffersArePaused.selector);
        compositeLiquidityRouter.addLiquidityProportionalToERC4626Pool(
            pool,
            _wrapBoth(),
            _generousMaxAmountsIn(required),
            bptOut,
            false,
            bytes("")
        );
    }

    /// @dev `maxAmountsIn` is denominated in what the caller pays, so a query result is directly reusable.
    function testAddQueryResultIsExecutableAsLimits() public {
        uint256 bptOut = _mintForRawWa6(20000);

        uint256 snapshotId = vm.snapshotState();
        _prankStaticCall();
        uint256[] memory queried = compositeLiquidityRouter.queryAddLiquidityProportionalToERC4626Pool(
            pool,
            _wrapBoth(),
            bptOut,
            lp,
            bytes("")
        );
        vm.revertToState(snapshotId);

        vm.prank(lp);
        uint256[] memory amountsIn = compositeLiquidityRouter.addLiquidityProportionalToERC4626Pool(
            pool,
            _wrapBoth(),
            queried,
            bptOut,
            false,
            bytes("")
        );

        assertEq(amountsIn[_wa6Idx], queried[_wa6Idx], "USDC-6 leg does not match the query");
        assertEq(amountsIn[_waDaiIdx], queried[_waDaiIdx], "DAI leg does not match the query");
    }

    /// @dev The prepaid variant shares this path exactly; only how the tokens arrive differs.
    function testPrepaidRouterAddBehavesIdentically() public {
        uint256 rawTarget = _PRODUCTION_MIN_WRAP_AMOUNT - 1;
        uint256 bptOut = _mintForRawWa6(rawTarget);
        uint256[] memory maxAmountsIn = _generousMaxAmountsIn(_rawAmountsIn(bptOut));

        vm.startPrank(lp);
        usdc6Decimals.transfer(address(vault), maxAmountsIn[_wa6Idx]);
        dai.transfer(address(vault), maxAmountsIn[_waDaiIdx]);

        vm.expectRevert(
            abi.encodeWithSelector(
                ICompositeLiquidityRouterErrors.RequiredWrapAmountTooSmall.selector,
                address(_wa6),
                rawTarget
            )
        );
        prepaidCompositeLiquidityRouter.addLiquidityProportionalToERC4626Pool(
            pool,
            _wrapBoth(),
            maxAmountsIn,
            bptOut,
            false,
            bytes("")
        );
        vm.stopPrank();
    }

    /***************************************************************************
                              The three call sites
    ***************************************************************************/

    /**
     * @dev Every proportional operation that hands the buffer a pool-derived amount reports a refusal in the terms of
     * the operation the caller asked for, and none of them leaks the Vault's buffer error. The amounts differ because
     * the boundaries differ: an unwrap is refused two above the Vault's stated minimum at this wrapper's rate, and a
     * wrap is refused one below it, which is exactly why the router does not compare against a threshold of its own.
     */
    function testEveryPoolDerivedCallSiteReportsARouterError() public {
        uint256 unwrapTarget = _FIRST_ACCEPTED_RAW - 1;
        uint256 wrapTarget = _PRODUCTION_MIN_WRAP_AMOUNT - 1;

        bytes memory unwrapError = abi.encodeWithSelector(
            ICompositeLiquidityRouterErrors.UnwrapAmountTooSmall.selector,
            address(_wa6),
            unwrapTarget
        );

        // Proportional remove from the ERC4626 pool.
        uint256 bptIn = _burnForRawWa6(unwrapTarget);
        uint256 snapshotId = vm.snapshotState();

        vm.prank(lp);
        vm.expectRevert(unwrapError);
        compositeLiquidityRouter.removeLiquidityProportionalFromERC4626Pool(
            pool,
            _unwrapBoth(),
            bptIn,
            new uint256[](2),
            false,
            bytes("")
        );

        vm.revertToState(snapshotId);

        // Proportional remove through the nested traversal, same pool and same burn.
        (uint256 usdc6Idx, uint256 daiIdx) = getSortedIndexes(address(usdc6Decimals), address(dai));

        address[] memory tokensOut = new address[](2);
        tokensOut[usdc6Idx] = address(usdc6Decimals);
        tokensOut[daiIdx] = address(dai);

        address[] memory tokensToUnwrap = new address[](2);
        tokensToUnwrap[0] = address(_wa6);
        tokensToUnwrap[1] = address(waDAI);

        vm.prank(lp);
        vm.expectRevert(unwrapError);
        compositeLiquidityRouter.removeLiquidityProportionalNestedPool(
            pool,
            bptIn,
            tokensOut,
            new uint256[](2),
            tokensToUnwrap,
            false,
            bytes("")
        );

        vm.revertToState(snapshotId);

        // Proportional add to the same pool, at its own boundary.
        uint256 bptOut = _mintForRawWa6(wrapTarget);
        uint256[] memory maxAmountsIn = _generousMaxAmountsIn(_rawAmountsIn(bptOut));

        vm.prank(lp);
        vm.expectRevert(
            abi.encodeWithSelector(
                ICompositeLiquidityRouterErrors.RequiredWrapAmountTooSmall.selector,
                address(_wa6),
                wrapTarget
            )
        );
        compositeLiquidityRouter.addLiquidityProportionalToERC4626Pool(
            pool,
            _wrapBoth(),
            maxAmountsIn,
            bptOut,
            false,
            bytes("")
        );
    }

    /***************************************************************************
                                     Helpers
    ***************************************************************************/

    /// @dev Both pool tokens are ERC4626 wrappers, and both are flagged for wrapping.
    function _wrapBoth() private pure returns (bool[] memory wrapUnderlying) {
        wrapUnderlying = new bool[](2);
        wrapUnderlying[0] = true;
        wrapUnderlying[1] = true;
    }

    /// @dev Raw pool-token amounts a proportional mint of `bptOut` would require, from the plain Router's query.
    function _rawAmountsIn(uint256 bptOut) private returns (uint256[] memory amountsIn) {
        uint256 snapshotId = vm.snapshotState();
        _prankStaticCall();
        amountsIn = router.queryAddLiquidityProportional(pool, bptOut, address(this), bytes(""));
        vm.revertToState(snapshotId);
    }

    /// @dev True when a proportional mint of `bptOut` is above the Vault's scaled18 trade minimum for every token.
    function _mintIsReachable(uint256 bptOut) private returns (bool reachable) {
        uint256 snapshotId = vm.snapshotState();
        _prankStaticCall();
        try router.queryAddLiquidityProportional(pool, bptOut, address(this), bytes("")) returns (uint256[] memory) {
            reachable = true;
        } catch {
            reachable = false;
        }
        vm.revertToState(snapshotId);
    }

    /// @dev Largest `bptOut` whose required raw wa6 amount is at most `targetRaw`.
    function _mintForRawWa6(uint256 targetRaw) private returns (uint256) {
        uint256 low = 1;
        uint256 high = 1e24;

        while (low < high) {
            uint256 mid = (low + high + 1) / 2;
            if (_mintIsReachable(mid) == false || _rawAmountsIn(mid)[_wa6Idx] <= targetRaw) {
                low = mid;
            } else {
                high = mid - 1;
            }
        }

        return low;
    }

    /// @dev Limits well above what the legs cost, so the caller's limit is never what fails.
    function _generousMaxAmountsIn(uint256[] memory required) private view returns (uint256[] memory maxAmountsIn) {
        maxAmountsIn = new uint256[](2);
        maxAmountsIn[_wa6Idx] = required[_wa6Idx] * 4 + 1e6;
        maxAmountsIn[_waDaiIdx] = required[_waDaiIdx] * 4 + 1e18;
    }

    /// @dev Both pool tokens are ERC4626 wrappers, and both are flagged for unwrapping.
    function _unwrapBoth() private pure returns (bool[] memory unwrapWrapped) {
        unwrapWrapped = new bool[](2);
        unwrapWrapped[0] = true;
        unwrapWrapped[1] = true;
    }

    /// @dev Raw pool-token amounts a proportional burn of `bptIn` would return, from the plain Router's query.
    function _rawAmountsOut(uint256 bptIn) private returns (uint256[] memory amountsOut) {
        uint256 snapshotId = vm.snapshotState();
        _prankStaticCall();
        amountsOut = router.queryRemoveLiquidityProportional(pool, bptIn, address(this), bytes(""));
        vm.revertToState(snapshotId);
    }

    /// @dev Largest `bptIn` whose raw wa6 output is at most `targetRaw`.
    function _burnForRawWa6(uint256 targetRaw) private returns (uint256) {
        uint256 low = PRODUCTION_MIN_TRADE_AMOUNT;
        uint256 high = BalancerPoolToken(pool).balanceOf(lp);

        while (low < high) {
            uint256 mid = (low + high + 1) / 2;
            if (_rawAmountsOut(mid)[_wa6Idx] <= targetRaw) {
                low = mid;
            } else {
                high = mid - 1;
            }
        }

        return low;
    }

    /// @dev Raw amounts a recovery withdrawal of `bptIn` would return. It applies no trade-amount floor.
    function _rawAmountsOutRecovery(uint256 bptIn) private returns (uint256[] memory amountsOut) {
        uint256 snapshotId = vm.snapshotState();
        _prankStaticCall();
        amountsOut = router.queryRemoveLiquidityRecovery(pool, bptIn);
        vm.revertToState(snapshotId);
    }

    /// @dev Largest `bptIn` whose raw waDAI output under a recovery withdrawal is at most `targetRaw`.
    function _burnForRawWaDaiRecovery(uint256 targetRaw) private returns (uint256) {
        uint256 low = 1;
        uint256 high = BalancerPoolToken(pool).balanceOf(lp);

        while (low < high) {
            uint256 mid = (low + high + 1) / 2;
            if (_rawAmountsOutRecovery(mid)[_waDaiIdx] <= targetRaw) {
                low = mid;
            } else {
                high = mid - 1;
            }
        }

        return low;
    }
}
