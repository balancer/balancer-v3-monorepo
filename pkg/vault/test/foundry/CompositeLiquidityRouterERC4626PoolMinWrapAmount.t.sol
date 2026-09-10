// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { stdError } from "forge-std/Test.sol";

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import {
    ICompositeLiquidityRouterErrors
} from "@balancer-labs/v3-interfaces/contracts/vault/ICompositeLiquidityRouterErrors.sol";
import { IVaultAdmin } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultAdmin.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";

import { RevertCodec } from "@balancer-labs/v3-solidity-utils/contracts/helpers/RevertCodec.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { CompositeLiquidityRouterMinWrapAmountBase } from "./utils/CompositeLiquidityRouterMinWrapAmountBase.sol";
import { BalancerPoolToken } from "../../contracts/BalancerPoolToken.sol";

/**
 * @notice Proportional liquidity on an ERC4626 pool at the production Vault minimums.
 * @dev The fixture is `CompositeLiquidityRouterMinWrapAmountBase`. This suite covers the flat entry points in both
 * directions: `UnwrapAmountTooSmall` on the way out, `RequiredWrapAmountTooSmall` on the way in.
 *
 * The two boundaries differ. Unwrapping calculates `previewRedeem(amount - 1) - 1` and wrapping calculates
 * `previewMint(amount + 1) + 1`, and the Vault applies its minimum to that result as well as to the amount given,
 * so which of the two checks reaches the minimum first depends on the wrapper's rate. See `_FIRST_ACCEPTED_RAW`.
 */
contract CompositeLiquidityRouterERC4626PoolMinWrapAmountTest is CompositeLiquidityRouterMinWrapAmountBase {
    /***************************************************************************
                              Proportional remove
    ***************************************************************************/

    /// @dev Every non-zero share the buffer will not unwrap reverts with `UnwrapAmountTooSmall`, and nothing moves.
    function testSubMinimumUnwrapRevertsWithRouterError() public {
        uint256[4] memory rawTargets = [
            uint256(1),
            PRODUCTION_MIN_WRAP_AMOUNT - 1,
            PRODUCTION_MIN_WRAP_AMOUNT,
            _FIRST_ACCEPTED_RAW - 1
        ];

        for (uint256 i = 0; i < rawTargets.length; ++i) {
            uint256 bptIn = _burnForRawWaUsdc6(rawTargets[i]);
            assertEq(_rawAmountsOut(bptIn)[_waUsdc6Idx], rawTargets[i], "Setup: wrong raw waUSDC6 amount");

            uint256 snapshotId = vm.snapshotState();

            uint256 bptBefore = BalancerPoolToken(pool).balanceOf(lp);
            uint256 waUSDC6Before = _waUSDC6.balanceOf(lp);
            uint256 usdcBefore = usdc6Decimals.balanceOf(lp);

            vm.prank(lp);
            vm.expectRevert(
                abi.encodeWithSelector(
                    ICompositeLiquidityRouterErrors.UnwrapAmountTooSmall.selector,
                    address(_waUSDC6),
                    rawTargets[i]
                )
            );
            compositeLiquidityRouter.removeLiquidityProportionalFromERC4626Pool(
                pool,
                _setupTrueBoolArray(2),
                bptIn,
                new uint256[](2),
                false,
                bytes("")
            );

            assertEq(BalancerPoolToken(pool).balanceOf(lp), bptBefore, "BPT was burned");
            assertEq(_waUSDC6.balanceOf(lp), waUSDC6Before, "The wrapped token was delivered");
            assertEq(usdc6Decimals.balanceOf(lp), usdcBefore, "The underlying token was delivered");

            vm.revertToState(snapshotId);
        }
    }

    /// @dev The query reverts with the same error as the operation it quotes.
    function testSubMinimumUnwrapQueryMatchesExecution() public {
        uint256[2] memory rawTargets = [uint256(1), _FIRST_ACCEPTED_RAW - 1];

        for (uint256 i = 0; i < rawTargets.length; ++i) {
            uint256 bptIn = _burnForRawWaUsdc6(rawTargets[i]);

            uint256 snapshotId = vm.snapshotState();

            _prankStaticCall();
            vm.expectRevert(
                abi.encodeWithSelector(
                    ICompositeLiquidityRouterErrors.UnwrapAmountTooSmall.selector,
                    address(_waUSDC6),
                    rawTargets[i]
                )
            );
            compositeLiquidityRouter.queryRemoveLiquidityProportionalFromERC4626Pool(
                pool,
                _setupTrueBoolArray(2),
                bptIn,
                lp,
                bytes("")
            );

            vm.revertToState(snapshotId);
        }
    }

    /**
     * @dev A redeem rate below 1 raises the boundary, since the check on the underlying output is the tighter one.
     * At a rate of 0.5, 15000 wrapped clears the stated minimum of 10000 but redeems to only ~7500, which does not.
     */
    function testBelowParRateRefusesAmountAboveTheStatedMinimum() public {
        _waUSDC6.mockRate(FixedPoint.ONE / 2);
        assertLt(_waUSDC6.getRate(), FixedPoint.ONE, "Setup: the rate did not fall below one");

        uint256 rawTarget = 15000;
        assertGt(rawTarget, vault.getMinimumWrapAmount(), "Setup: the target is not above the stated minimum");

        uint256 bptIn = _burnForRawWaUsdc6(rawTarget);
        assertEq(_rawAmountsOut(bptIn)[_waUsdc6Idx], rawTarget, "Setup: wrong raw waUSDC6 amount");

        vm.prank(lp);
        vm.expectRevert(
            abi.encodeWithSelector(
                ICompositeLiquidityRouterErrors.UnwrapAmountTooSmall.selector,
                address(_waUSDC6),
                rawTarget
            )
        );
        compositeLiquidityRouter.removeLiquidityProportionalFromERC4626Pool(
            pool,
            _setupTrueBoolArray(2),
            bptIn,
            new uint256[](2),
            false,
            bytes("")
        );
    }

    /**
     * @dev A redeem rate above 1 goes the other way: the check on the underlying output is slack, so the boundary
     * falls back to the stated minimum, 2 below what the same pool accepts at a rate of 1.
     */
    function testRateAboveOneMovesTheBoundaryToTheStatedMinimum() public {
        _waUSDC6.mockRate(2 * FixedPoint.ONE);
        assertGt(_waUSDC6.getRate(), FixedPoint.ONE, "Setup: the rate did not rise above one");

        uint256 refusedBptIn = _burnForRawWaUsdc6(PRODUCTION_MIN_WRAP_AMOUNT - 1);
        uint256 acceptedBptIn = _burnForRawWaUsdc6(PRODUCTION_MIN_WRAP_AMOUNT);

        uint256 snapshotId = vm.snapshotState();

        vm.prank(lp);
        vm.expectRevert(
            abi.encodeWithSelector(
                ICompositeLiquidityRouterErrors.UnwrapAmountTooSmall.selector,
                address(_waUSDC6),
                PRODUCTION_MIN_WRAP_AMOUNT - 1
            )
        );
        compositeLiquidityRouter.removeLiquidityProportionalFromERC4626Pool(
            pool,
            _setupTrueBoolArray(2),
            refusedBptIn,
            new uint256[](2),
            false,
            bytes("")
        );

        vm.revertToState(snapshotId);

        // At a rate of 1 this same amount reverts; see `testSubMinimumUnwrapRevertsWithRouterError`.
        vm.prank(lp);
        uint256[] memory amountsOut = compositeLiquidityRouter.removeLiquidityProportionalFromERC4626Pool(
            pool,
            _setupTrueBoolArray(2),
            acceptedBptIn,
            new uint256[](2),
            false,
            bytes("")
        );

        assertGt(amountsOut[_waUsdc6Idx], PRODUCTION_MIN_WRAP_AMOUNT, "The stated minimum was not accepted");
    }

    /***************************************************************************
                                    Boundaries
    ***************************************************************************/

    /// @dev A zero share is returned as zero of the underlying token, and the withdrawal succeeds.
    function testZeroUnwrapShareSucceeds() public {
        uint256 bptIn = _burnForRawWaUsdc6(0);
        assertEq(_rawAmountsOut(bptIn)[_waUsdc6Idx], 0, "Setup: waUSDC6 share should be exactly zero");

        uint256 waUSDC6Before = _waUSDC6.balanceOf(lp);

        vm.prank(lp);
        uint256[] memory amountsOut = compositeLiquidityRouter.removeLiquidityProportionalFromERC4626Pool(
            pool,
            _setupTrueBoolArray(2),
            bptIn,
            new uint256[](2),
            false,
            bytes("")
        );

        assertEq(amountsOut[_waUsdc6Idx], 0, "Zero share should report zero");
        assertGt(amountsOut[_waDaiIdx], 0, "DAI amount should be non-zero");
        assertEq(_waUSDC6.balanceOf(lp), waUSDC6Before, "The wrapped token was delivered for the zero share");
    }

    /// @dev A zero share is still measured against `minAmountsOut`, in the underlying token.
    function testZeroUnwrapShareWithNonZeroLimitReverts() public {
        uint256 bptIn = _burnForRawWaUsdc6(0);

        uint256[] memory minAmountsOut = new uint256[](2);
        minAmountsOut[_waUsdc6Idx] = 1;

        vm.prank(lp);
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.AmountOutBelowMin.selector, address(usdc6Decimals), 0, 1));
        compositeLiquidityRouter.removeLiquidityProportionalFromERC4626Pool(
            pool,
            _setupTrueBoolArray(2),
            bptIn,
            minAmountsOut,
            false,
            bytes("")
        );
    }

    /**
     * @dev The buffer is handed no limit, so a share it refuses is reported as `UnwrapAmountTooSmall` even when
     * `minAmountsOut` would also have failed. `minAmountsOut` is checked after the unwrap, not before.
     */
    function testSubMinimumUnderlyingIsReportedAheadOfTheLimit() public {
        uint256 bptIn = _burnForRawWaUsdc6(PRODUCTION_MIN_WRAP_AMOUNT);

        uint256[] memory minAmountsOut = new uint256[](2);
        minAmountsOut[_waUsdc6Idx] = PRODUCTION_MIN_WRAP_AMOUNT;

        // The unwrap deducts 2 wei, so the underlying falls below both the minimum and the limit.
        vm.prank(lp);
        vm.expectRevert(
            abi.encodeWithSelector(
                ICompositeLiquidityRouterErrors.UnwrapAmountTooSmall.selector,
                address(_waUSDC6),
                PRODUCTION_MIN_WRAP_AMOUNT
            )
        );
        compositeLiquidityRouter.removeLiquidityProportionalFromERC4626Pool(
            pool,
            _setupTrueBoolArray(2),
            bptIn,
            minAmountsOut,
            false,
            bytes("")
        );
    }

    /// @dev The first accepted amount, and an ordinary amount above it. The unwrap deducts 2 wei.
    function testAcceptedAmountsAreUnaffected() public {
        uint256[2] memory rawTargets = [_FIRST_ACCEPTED_RAW, uint256(20000)];

        for (uint256 i = 0; i < rawTargets.length; ++i) {
            uint256 bptIn = _burnForRawWaUsdc6(rawTargets[i]);
            assertEq(_rawAmountsOut(bptIn)[_waUsdc6Idx], rawTargets[i], "Setup: wrong raw waUSDC6 amount");

            uint256 snapshotId = vm.snapshotState();

            vm.prank(lp);
            uint256[] memory amountsOut = compositeLiquidityRouter.removeLiquidityProportionalFromERC4626Pool(
                pool,
                _setupTrueBoolArray(2),
                bptIn,
                new uint256[](2),
                false,
                bytes("")
            );

            assertEq(amountsOut[_waUsdc6Idx], rawTargets[i] - 2, "USDC-6 amount is wrong");
            assertGt(amountsOut[_waDaiIdx], 0, "DAI amount should be non-zero");

            vm.revertToState(snapshotId);
        }
    }

    /// @dev `minAmountsOut` is denominated in what the caller receives, so a query result is directly reusable.
    function testQueryResultIsExecutableAsLimits() public {
        uint256 bptIn = _burnForRawWaUsdc6(20000);

        uint256 snapshotId = vm.snapshotState();
        _prankStaticCall();
        uint256[] memory queried = compositeLiquidityRouter.queryRemoveLiquidityProportionalFromERC4626Pool(
            pool,
            _setupTrueBoolArray(2),
            bptIn,
            lp,
            bytes("")
        );
        vm.revertToState(snapshotId);

        vm.prank(lp);
        uint256[] memory amountsOut = compositeLiquidityRouter.removeLiquidityProportionalFromERC4626Pool(
            pool,
            _setupTrueBoolArray(2),
            bptIn,
            queried,
            false,
            bytes("")
        );

        assertEq(amountsOut[_waUsdc6Idx], queried[_waUsdc6Idx], "USDC-6 amount does not match the query");
        assertEq(amountsOut[_waDaiIdx], queried[_waDaiIdx], "DAI amount does not match the query");
    }

    /***************************************************************************
                                    Controls
    ***************************************************************************/

    /// @dev Clearing the unwrap flag pays the same share as the wrapped token, with no buffer call.
    function testUnwrapFlagClearedIsUnaffected() public {
        uint256 rawTarget = _FIRST_ACCEPTED_RAW - 1;
        uint256 bptIn = _burnForRawWaUsdc6(rawTarget);

        uint256 waUSDC6Before = _waUSDC6.balanceOf(lp);

        vm.prank(lp);
        uint256[] memory amountsOut = compositeLiquidityRouter.removeLiquidityProportionalFromERC4626Pool(
            pool,
            new bool[](2),
            bptIn,
            new uint256[](2),
            false,
            bytes("")
        );

        assertEq(amountsOut[_waUsdc6Idx], rawTarget, "The wrapped token should be paid in full");
        assertEq(_waUSDC6.balanceOf(lp) - waUSDC6Before, rawTarget, "The wrapped token did not arrive");
    }

    /// @dev Any other buffer failure keeps the Vault's own error.
    function testOtherBufferFailuresAreNotReinterpreted() public {
        uint256 bptIn = _burnForRawWaUsdc6(20000);

        vm.prank(admin);
        IVaultAdmin(address(vault)).pauseVaultBuffers();

        vm.prank(lp);
        vm.expectRevert(IVaultErrors.VaultBuffersArePaused.selector);
        compositeLiquidityRouter.removeLiquidityProportionalFromERC4626Pool(
            pool,
            _setupTrueBoolArray(2),
            bptIn,
            new uint256[](2),
            false,
            bytes("")
        );
    }

    /// @dev Revert data with no selector to read comes back as `ErrorSelectorNotFound`, not as a too-small amount.
    function testShortRevertDataIsNotReinterpreted() public {
        uint256 bptIn = _burnForRawWaUsdc6(20000);

        vm.mockCallRevert(address(_waUSDC6), abi.encodeWithSelector(IERC4626.previewRedeem.selector), bytes(""));

        vm.prank(lp);
        vm.expectRevert(RevertCodec.ErrorSelectorNotFound.selector);
        compositeLiquidityRouter.removeLiquidityProportionalFromERC4626Pool(
            pool,
            _setupTrueBoolArray(2),
            bptIn,
            new uint256[](2),
            false,
            bytes("")
        );
    }

    /**
     * @dev The router matches on the revert selector, so a wrapper that raises `WrapAmountTooSmall` from one of its
     * own calls is reported as a refusal too. The operation reverts either way, but retry logic keyed on the error
     * should know that a larger amount will not help in that case.
     */
    function testWrapperSpoofedSelectorIsReportedAsARefusal() public {
        uint256 rawTarget = 20000;
        uint256 bptIn = _burnForRawWaUsdc6(rawTarget);
        assertEq(_rawAmountsOut(bptIn)[_waUsdc6Idx], rawTarget, "Setup: wrong raw waUSDC6 amount");

        vm.mockCallRevert(
            address(_waUSDC6),
            abi.encodeWithSelector(IERC4626.previewRedeem.selector),
            abi.encodeWithSelector(IVaultErrors.WrapAmountTooSmall.selector, address(_waUSDC6))
        );

        vm.prank(lp);
        vm.expectRevert(
            abi.encodeWithSelector(
                ICompositeLiquidityRouterErrors.UnwrapAmountTooSmall.selector,
                address(_waUSDC6),
                rawTarget
            )
        );
        compositeLiquidityRouter.removeLiquidityProportionalFromERC4626Pool(
            pool,
            _setupTrueBoolArray(2),
            bptIn,
            new uint256[](2),
            false,
            bytes("")
        );
    }

    /**
     * @dev A share worth less than 1 raw unit of the underlying underflows the Vault's `previewRedeem(amount - 1) - 1`
     * before either minimum applies. That panic stays visible as a panic.
     */
    function testArithmeticPanicIsNotReinterpreted() public {
        uint256 bptIn = _burnForRawWaUsdc6(20000);

        vm.mockCall(address(_waUSDC6), abi.encodeWithSelector(IERC4626.previewRedeem.selector), abi.encode(uint256(0)));

        vm.prank(lp);
        vm.expectRevert(stdError.arithmeticError);
        compositeLiquidityRouter.removeLiquidityProportionalFromERC4626Pool(
            pool,
            _setupTrueBoolArray(2),
            bptIn,
            new uint256[](2),
            false,
            bytes("")
        );
    }

    /// @dev The prepaid variant shares this path; only how the BPT is approved differs.
    function testPrepaidRouterBehavesIdentically() public {
        uint256 rawTarget = _FIRST_ACCEPTED_RAW - 1;
        uint256 bptIn = _burnForRawWaUsdc6(rawTarget);

        vm.startPrank(lp);
        BalancerPoolToken(pool).approve(address(prepaidCompositeLiquidityRouter), bptIn);

        vm.expectRevert(
            abi.encodeWithSelector(
                ICompositeLiquidityRouterErrors.UnwrapAmountTooSmall.selector,
                address(_waUSDC6),
                rawTarget
            )
        );
        prepaidCompositeLiquidityRouter.removeLiquidityProportionalFromERC4626Pool(
            pool,
            _setupTrueBoolArray(2),
            bptIn,
            new uint256[](2),
            false,
            bytes("")
        );
        vm.stopPrank();
    }

    /// @dev The nested entry point reports the same token, amount and error, at the same pool and the same burn.
    function testNestedPathReportsTheSameError() public {
        uint256 rawTarget = _FIRST_ACCEPTED_RAW - 1;
        uint256 bptIn = _burnForRawWaUsdc6(rawTarget);

        (address[] memory tokensOut, address[] memory tokensToUnwrap) = _tokenLists();

        bytes memory expectedError = abi.encodeWithSelector(
            ICompositeLiquidityRouterErrors.UnwrapAmountTooSmall.selector,
            address(_waUSDC6),
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
            _setupTrueBoolArray(2),
            bptIn,
            new uint256[](2),
            false,
            bytes("")
        );
    }

    /**
     * @dev A pool in Recovery Mode still takes the ordinary removal path, which applies the Vault's minimum trade
     * amount. A recovery withdrawal applies no such minimum, so amounts below it are reachable only through the
     * plain Router, which pays the wrapped token rather than unwrapping.
     */
    function testRecoveryModeDoesNotWidenTheBand() public {
        vault.manualEnableRecoveryMode(pool);

        uint256 bptIn = _burnForRawWaDaiRecovery(PRODUCTION_MIN_WRAP_AMOUNT - 1);

        uint256 snapshotId = vm.snapshotState();
        _prankStaticCall();
        uint256[] memory recoveryAmountsOut = router.queryRemoveLiquidityRecovery(pool, bptIn);
        vm.revertToState(snapshotId);

        // The amount is non-zero and below anything the buffer would unwrap.
        assertGt(recoveryAmountsOut[_waDaiIdx], 0, "Setup: the waDAI amount is zero");
        assertLt(
            recoveryAmountsOut[_waDaiIdx],
            vault.getMinimumWrapAmount(),
            "Setup: the waDAI amount is not in the band"
        );

        // The composite router rejects the burn on the ordinary path's minimum trade amount, before any buffer call.
        vm.prank(lp);
        vm.expectRevert(IVaultErrors.TradeAmountTooSmall.selector);
        compositeLiquidityRouter.removeLiquidityProportionalFromERC4626Pool(
            pool,
            _setupTrueBoolArray(2),
            bptIn,
            new uint256[](2),
            false,
            bytes("")
        );

        // The plain Router pays the registered wrapped tokens, with no minimum and no buffer call. The shares
        // redeem against the wrapper afterwards.
        vm.prank(lp);
        uint256[] memory wrappedAmountsOut = router.removeLiquidityRecovery(pool, bptIn, new uint256[](2));

        assertEq(wrappedAmountsOut[_waDaiIdx], recoveryAmountsOut[_waDaiIdx], "Wrong waDAI amount out");
    }

    /***************************************************************************
                                Proportional add
    ***************************************************************************/

    /**
     * @dev The mirror of the removal case: the pool fixes the amount to wrap, and the caller reaches it only through
     * `exactBptAmountOut`. An amount the buffer will not wrap reverts with `RequiredWrapAmountTooSmall`.
     */
    function testSubMinimumWrapRevertsWithRouterError() public {
        uint256[3] memory rawTargets = [uint256(1), PRODUCTION_MIN_WRAP_AMOUNT - 2, PRODUCTION_MIN_WRAP_AMOUNT - 1];

        for (uint256 i = 0; i < rawTargets.length; ++i) {
            uint256 bptOut = _mintForRawWaUsdc6(rawTargets[i]);
            uint256[] memory required = _rawAmountsIn(bptOut);
            assertEq(required[_waUsdc6Idx], rawTargets[i], "Setup: wrong required raw waUSDC6 amount");

            uint256 snapshotId = vm.snapshotState();

            uint256 bptBefore = BalancerPoolToken(pool).balanceOf(lp);
            uint256 waUSDC6Before = _waUSDC6.balanceOf(lp);
            uint256 usdcBefore = usdc6Decimals.balanceOf(lp);
            uint256 daiBefore = dai.balanceOf(lp);

            vm.prank(lp);
            vm.expectRevert(
                abi.encodeWithSelector(
                    ICompositeLiquidityRouterErrors.RequiredWrapAmountTooSmall.selector,
                    address(_waUSDC6),
                    rawTargets[i]
                )
            );
            compositeLiquidityRouter.addLiquidityProportionalToERC4626Pool(
                pool,
                _setupTrueBoolArray(2),
                _generousMaxAmountsIn(required),
                bptOut,
                false,
                bytes("")
            );

            assertEq(BalancerPoolToken(pool).balanceOf(lp), bptBefore, "Pool tokens were minted");
            assertEq(_waUSDC6.balanceOf(lp), waUSDC6Before, "The wrapped token was charged");
            assertEq(usdc6Decimals.balanceOf(lp), usdcBefore, "The underlying token was charged");
            assertEq(dai.balanceOf(lp), daiBefore, "The other token was charged");

            vm.revertToState(snapshotId);
        }
    }

    /// @dev The query reverts with the same error as the operation it quotes.
    function testSubMinimumWrapQueryMatchesExecution() public {
        uint256[2] memory rawTargets = [uint256(1), PRODUCTION_MIN_WRAP_AMOUNT - 1];

        for (uint256 i = 0; i < rawTargets.length; ++i) {
            uint256 bptOut = _mintForRawWaUsdc6(rawTargets[i]);

            uint256 snapshotId = vm.snapshotState();

            _prankStaticCall();
            vm.expectRevert(
                abi.encodeWithSelector(
                    ICompositeLiquidityRouterErrors.RequiredWrapAmountTooSmall.selector,
                    address(_waUSDC6),
                    rawTargets[i]
                )
            );
            compositeLiquidityRouter.queryAddLiquidityProportionalToERC4626Pool(
                pool,
                _setupTrueBoolArray(2),
                bptOut,
                lp,
                bytes("")
            );

            vm.revertToState(snapshotId);
        }
    }

    /**
     * @dev Wrapping costs `previewMint(amount + 1) + 1` of the underlying, so at a rate below 1 the underlying cost
     * is the smaller number and the check on it is the tighter one. At a rate of 0.5, a required 15000 clears the
     * stated minimum of 10000 but costs only ~5000, and the first accepted amount is about twice the minimum.
     */
    function testBelowParRateRefusesWrapAmountAboveTheStatedMinimum() public {
        _waUSDC6.mockRate(FixedPoint.ONE / 2);
        assertLt(_waUSDC6.getRate(), FixedPoint.ONE, "Setup: the rate did not fall below one");

        uint256 refusedTarget = 15000;
        assertGt(refusedTarget, vault.getMinimumWrapAmount(), "Setup: the target is not above the stated minimum");

        uint256 refusedBptOut = _mintForRawWaUsdc6(refusedTarget);
        uint256[] memory refusedRequired = _rawAmountsIn(refusedBptOut);
        uint256[] memory refusedMaxAmountsIn = _generousMaxAmountsIn(refusedRequired);
        assertEq(refusedRequired[_waUsdc6Idx], refusedTarget, "Setup: wrong required raw waUSDC6 amount");

        uint256 snapshotId = vm.snapshotState();

        vm.prank(lp);
        vm.expectRevert(
            abi.encodeWithSelector(
                ICompositeLiquidityRouterErrors.RequiredWrapAmountTooSmall.selector,
                address(_waUSDC6),
                refusedTarget
            )
        );
        compositeLiquidityRouter.addLiquidityProportionalToERC4626Pool(
            pool,
            _setupTrueBoolArray(2),
            refusedMaxAmountsIn,
            refusedBptOut,
            false,
            bytes("")
        );

        vm.revertToState(snapshotId);

        // Roughly twice the stated minimum, which is where the underlying cost first reaches it.
        uint256 acceptedBptOut = _mintForRawWaUsdc6(19995);
        uint256[] memory acceptedRequired = _rawAmountsIn(acceptedBptOut);
        uint256[] memory acceptedMaxAmountsIn = _generousMaxAmountsIn(acceptedRequired);
        assertEq(acceptedRequired[_waUsdc6Idx], 19995, "Setup: wrong accepted raw waUSDC6 amount");

        vm.prank(lp);
        uint256[] memory amountsIn = compositeLiquidityRouter.addLiquidityProportionalToERC4626Pool(
            pool,
            _setupTrueBoolArray(2),
            acceptedMaxAmountsIn,
            acceptedBptOut,
            false,
            bytes("")
        );

        assertEq(amountsIn[_waUsdc6Idx], PRODUCTION_MIN_WRAP_AMOUNT, "The accepted amount cost the wrong underlying");
    }

    /**
     * @dev A rate above 1 goes the other way: the underlying cost is the larger number, so the check on it is slack
     * and the boundary is the stated minimum, which is where it also sits at a rate of 1.
     */
    function testRateAboveOneLeavesTheWrapBoundaryAtTheStatedMinimum() public {
        _waUSDC6.mockRate(2 * FixedPoint.ONE);
        assertGt(_waUSDC6.getRate(), FixedPoint.ONE, "Setup: the rate did not rise above one");

        uint256 refusedBptOut = _mintForRawWaUsdc6(PRODUCTION_MIN_WRAP_AMOUNT - 1);
        uint256 acceptedBptOut = _mintForRawWaUsdc6(PRODUCTION_MIN_WRAP_AMOUNT);

        uint256[] memory refusedMaxAmountsIn = _generousMaxAmountsIn(_rawAmountsIn(refusedBptOut));
        uint256[] memory acceptedMaxAmountsIn = _generousMaxAmountsIn(_rawAmountsIn(acceptedBptOut));

        uint256 snapshotId = vm.snapshotState();

        vm.prank(lp);
        vm.expectRevert(
            abi.encodeWithSelector(
                ICompositeLiquidityRouterErrors.RequiredWrapAmountTooSmall.selector,
                address(_waUSDC6),
                PRODUCTION_MIN_WRAP_AMOUNT - 1
            )
        );
        compositeLiquidityRouter.addLiquidityProportionalToERC4626Pool(
            pool,
            _setupTrueBoolArray(2),
            refusedMaxAmountsIn,
            refusedBptOut,
            false,
            bytes("")
        );

        vm.revertToState(snapshotId);

        vm.prank(lp);
        uint256[] memory amountsIn = compositeLiquidityRouter.addLiquidityProportionalToERC4626Pool(
            pool,
            _setupTrueBoolArray(2),
            acceptedMaxAmountsIn,
            acceptedBptOut,
            false,
            bytes("")
        );

        assertGt(amountsIn[_waUsdc6Idx], PRODUCTION_MIN_WRAP_AMOUNT, "The stated minimum was not accepted");
    }

    /**
     * @dev On the add path the buffer does hold the caller's limit, and tests it before applying the minimum to the
     * underlying cost. A `maxAmountsIn` below that cost is therefore reported as `SwapLimit`.
     */
    function testWrapLimitIsReportedFirst() public {
        _waUSDC6.mockRate(FixedPoint.ONE / 2);

        uint256 bptOut = _mintForRawWaUsdc6(PRODUCTION_MIN_WRAP_AMOUNT);
        uint256[] memory required = _rawAmountsIn(bptOut);

        // 10000 shares cost 5002 underlying at this rate, which is below the stated minimum.
        uint256[] memory maxAmountsIn = _generousMaxAmountsIn(required);
        maxAmountsIn[_waUsdc6Idx] = 5000;

        vm.prank(lp);
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.SwapLimit.selector, 5002, 5000));
        compositeLiquidityRouter.addLiquidityProportionalToERC4626Pool(
            pool,
            _setupTrueBoolArray(2),
            maxAmountsIn,
            bptOut,
            false,
            bytes("")
        );
    }

    /**
     * @dev The proportional add math rounds up, so a single token's required amount is zero only when every token's
     * is: when no pool tokens were requested. That makes no buffer call and moves nothing.
     */
    function testZeroPoolTokensOutIsANoOp() public {
        uint256[] memory maxAmountsIn = new uint256[](2);
        maxAmountsIn[_waUsdc6Idx] = 1e6;
        maxAmountsIn[_waDaiIdx] = 1e18;

        uint256 bptBefore = BalancerPoolToken(pool).balanceOf(lp);
        uint256 usdcBefore = usdc6Decimals.balanceOf(lp);
        uint256 daiBefore = dai.balanceOf(lp);

        vm.prank(lp);
        uint256[] memory amountsIn = compositeLiquidityRouter.addLiquidityProportionalToERC4626Pool(
            pool,
            _setupTrueBoolArray(2),
            maxAmountsIn,
            0,
            false,
            bytes("")
        );

        assertEq(amountsIn[_waUsdc6Idx], 0, "The wrapped token charged something");
        assertEq(amountsIn[_waDaiIdx], 0, "The other token charged something");
        assertEq(BalancerPoolToken(pool).balanceOf(lp), bptBefore, "Pool tokens were minted");
        assertEq(usdc6Decimals.balanceOf(lp), usdcBefore, "The underlying token was charged");
        assertEq(dai.balanceOf(lp), daiBefore, "The other underlying token was charged");
    }

    /// @dev The first accepted amount, and an ordinary amount above it. The wrap adds 2 wei.
    function testAcceptedAddsAreUnaffected() public {
        uint256[2] memory rawTargets = [PRODUCTION_MIN_WRAP_AMOUNT, uint256(20000)];

        for (uint256 i = 0; i < rawTargets.length; ++i) {
            uint256 bptOut = _mintForRawWaUsdc6(rawTargets[i]);
            uint256[] memory required = _rawAmountsIn(bptOut);
            assertEq(required[_waUsdc6Idx], rawTargets[i], "Setup: wrong required raw waUSDC6 amount");

            uint256 snapshotId = vm.snapshotState();

            uint256[] memory maxAmountsIn = _generousMaxAmountsIn(required);
            uint256 usdcBefore = usdc6Decimals.balanceOf(lp);

            vm.prank(lp);
            uint256[] memory amountsIn = compositeLiquidityRouter.addLiquidityProportionalToERC4626Pool(
                pool,
                _setupTrueBoolArray(2),
                maxAmountsIn,
                bptOut,
                false,
                bytes("")
            );

            assertEq(amountsIn[_waUsdc6Idx], rawTargets[i] + 2, "The wrapped token cost the wrong underlying");

            // The unused part of the limit comes back.
            assertEq(usdcBefore - usdc6Decimals.balanceOf(lp), rawTargets[i] + 2, "More than the cost was charged");

            vm.revertToState(snapshotId);
        }
    }

    /// @dev Clearing the wrap flag pays the wrapped token directly, with no buffer call.
    function testWrapFlagClearedIsUnaffected() public {
        uint256 rawTarget = PRODUCTION_MIN_WRAP_AMOUNT - 1;
        uint256 bptOut = _mintForRawWaUsdc6(rawTarget);
        uint256[] memory required = _rawAmountsIn(bptOut);

        // The pool init spent every share the sender held, so paying the wrapper needs some minted first.
        vm.prank(lp);
        _waUSDC6.deposit(2 * required[_waUsdc6Idx], lp);

        uint256 waUSDC6Before = _waUSDC6.balanceOf(lp);

        // Exact limits: nothing is wrapped, so the token costs precisely what the pool requires.
        vm.prank(lp);
        uint256[] memory amountsIn = compositeLiquidityRouter.addLiquidityProportionalToERC4626Pool(
            pool,
            new bool[](2),
            required,
            bptOut,
            false,
            bytes("")
        );

        assertEq(amountsIn[_waUsdc6Idx], rawTarget, "The wrapped token should be charged in full");
        assertEq(waUSDC6Before - _waUSDC6.balanceOf(lp), rawTarget, "The wrapped token was not taken");
    }

    /// @dev Any other buffer failure keeps the Vault's own error.
    function testAddOtherBufferFailuresAreNotReinterpreted() public {
        uint256 bptOut = _mintForRawWaUsdc6(20000);
        uint256[] memory required = _rawAmountsIn(bptOut);

        vm.prank(admin);
        IVaultAdmin(address(vault)).pauseVaultBuffers();

        vm.prank(lp);
        vm.expectRevert(IVaultErrors.VaultBuffersArePaused.selector);
        compositeLiquidityRouter.addLiquidityProportionalToERC4626Pool(
            pool,
            _setupTrueBoolArray(2),
            _generousMaxAmountsIn(required),
            bptOut,
            false,
            bytes("")
        );
    }

    /// @dev `maxAmountsIn` is denominated in what the caller pays, so a query result is directly reusable.
    function testAddQueryResultIsExecutableAsLimits() public {
        uint256 bptOut = _mintForRawWaUsdc6(20000);

        uint256 snapshotId = vm.snapshotState();
        _prankStaticCall();
        uint256[] memory queried = compositeLiquidityRouter.queryAddLiquidityProportionalToERC4626Pool(
            pool,
            _setupTrueBoolArray(2),
            bptOut,
            lp,
            bytes("")
        );
        vm.revertToState(snapshotId);

        vm.prank(lp);
        uint256[] memory amountsIn = compositeLiquidityRouter.addLiquidityProportionalToERC4626Pool(
            pool,
            _setupTrueBoolArray(2),
            queried,
            bptOut,
            false,
            bytes("")
        );

        assertEq(amountsIn[_waUsdc6Idx], queried[_waUsdc6Idx], "USDC-6 amount does not match the query");
        assertEq(amountsIn[_waDaiIdx], queried[_waDaiIdx], "DAI amount does not match the query");
    }

    /// @dev The prepaid variant shares this path; only how the tokens arrive differs.
    function testPrepaidRouterAddBehavesIdentically() public {
        uint256 rawTarget = PRODUCTION_MIN_WRAP_AMOUNT - 1;
        uint256 bptOut = _mintForRawWaUsdc6(rawTarget);
        uint256[] memory maxAmountsIn = _generousMaxAmountsIn(_rawAmountsIn(bptOut));

        vm.startPrank(lp);
        usdc6Decimals.transfer(address(vault), maxAmountsIn[_waUsdc6Idx]);
        dai.transfer(address(vault), maxAmountsIn[_waDaiIdx]);

        vm.expectRevert(
            abi.encodeWithSelector(
                ICompositeLiquidityRouterErrors.RequiredWrapAmountTooSmall.selector,
                address(_waUSDC6),
                rawTarget
            )
        );
        prepaidCompositeLiquidityRouter.addLiquidityProportionalToERC4626Pool(
            pool,
            _setupTrueBoolArray(2),
            maxAmountsIn,
            bptOut,
            false,
            bytes("")
        );
        vm.stopPrank();
    }

    /***************************************************************************
                                 Buffer call sites
    ***************************************************************************/

    /// @dev All three call sites that hand the buffer a pool-derived amount raise a router error, not the Vault's.
    function testEveryPoolDerivedCallSiteReportsARouterError() public {
        uint256 unwrapTarget = _FIRST_ACCEPTED_RAW - 1;
        uint256 wrapTarget = PRODUCTION_MIN_WRAP_AMOUNT - 1;

        bytes memory unwrapError = abi.encodeWithSelector(
            ICompositeLiquidityRouterErrors.UnwrapAmountTooSmall.selector,
            address(_waUSDC6),
            unwrapTarget
        );

        // Proportional remove from the ERC4626 pool.
        uint256 bptIn = _burnForRawWaUsdc6(unwrapTarget);
        uint256 snapshotId = vm.snapshotState();

        vm.prank(lp);
        vm.expectRevert(unwrapError);
        compositeLiquidityRouter.removeLiquidityProportionalFromERC4626Pool(
            pool,
            _setupTrueBoolArray(2),
            bptIn,
            new uint256[](2),
            false,
            bytes("")
        );

        vm.revertToState(snapshotId);

        // Proportional remove through the nested traversal, same pool and same burn.
        (address[] memory tokensOut, address[] memory tokensToUnwrap) = _tokenLists();

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
        uint256 bptOut = _mintForRawWaUsdc6(wrapTarget);
        uint256[] memory maxAmountsIn = _generousMaxAmountsIn(_rawAmountsIn(bptOut));

        vm.prank(lp);
        vm.expectRevert(
            abi.encodeWithSelector(
                ICompositeLiquidityRouterErrors.RequiredWrapAmountTooSmall.selector,
                address(_waUSDC6),
                wrapTarget
            )
        );
        compositeLiquidityRouter.addLiquidityProportionalToERC4626Pool(
            pool,
            _setupTrueBoolArray(2),
            maxAmountsIn,
            bptOut,
            false,
            bytes("")
        );
    }

    /**
     * @dev The other two call sites wrap an amount the caller named, so both keep the Vault's `WrapAmountTooSmall`.
     * 1 wei is below the minimum either way it is measured, so this does not depend on the wrapper's rate.
     */
    function testCallerNamedCallSitesKeepTheVaultError() public {
        bytes memory vaultError = abi.encodeWithSelector(IVaultErrors.WrapAmountTooSmall.selector, address(_waUSDC6));

        uint256[] memory exactAmountsIn = new uint256[](2);
        exactAmountsIn[_waUsdc6Idx] = 1;
        exactAmountsIn[_waDaiIdx] = 1e18;

        uint256 snapshotId = vm.snapshotState();

        // Unbalanced add to the ERC4626 pool: `_processTokenInExactIn` hands the buffer the caller's own amount.
        vm.prank(lp);
        vm.expectRevert(vaultError);
        compositeLiquidityRouter.addLiquidityUnbalancedToERC4626Pool(
            pool,
            _setupTrueBoolArray(2),
            exactAmountsIn,
            0,
            false,
            bytes("")
        );

        vm.revertToState(snapshotId);

        // Unbalanced add through the nested traversal: `_wrapExactInAndUpdateTokenInData` does the same.
        (uint256 usdc6Idx, uint256 daiIdx) = getSortedIndexes(address(usdc6Decimals), address(dai));

        address[] memory tokensIn = new address[](2);
        tokensIn[usdc6Idx] = address(usdc6Decimals);
        tokensIn[daiIdx] = address(dai);

        uint256[] memory nestedAmountsIn = new uint256[](2);
        nestedAmountsIn[usdc6Idx] = 1;
        nestedAmountsIn[daiIdx] = 1e18;

        address[] memory tokensToWrap = new address[](2);
        tokensToWrap[0] = address(_waUSDC6);
        tokensToWrap[1] = address(waDAI);

        vm.prank(lp);
        vm.expectRevert(vaultError);
        compositeLiquidityRouter.addLiquidityUnbalancedNestedPool(
            pool,
            tokensIn,
            nestedAmountsIn,
            tokensToWrap,
            0,
            false,
            bytes("")
        );
    }

    /***************************************************************************
                                     Helpers
    ***************************************************************************/

    /// @dev Raw pool-token amounts a proportional mint of `bptOut` would require, from the plain Router's query.
    function _rawAmountsIn(uint256 bptOut) private returns (uint256[] memory amountsIn) {
        uint256 snapshotId = vm.snapshotState();
        _prankStaticCall();
        amountsIn = router.queryAddLiquidityProportional(pool, bptOut, address(this), bytes(""));
        vm.revertToState(snapshotId);
    }

    /// @dev True when a proportional mint of `bptOut` clears the Vault's minimum trade amount for every token.
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

    /// @dev Largest `bptOut` whose required raw waUSDC6 amount is at most `targetRaw`.
    function _mintForRawWaUsdc6(uint256 targetRaw) private returns (uint256) {
        uint256 low = 1;
        uint256 high = 1e24;

        while (low < high) {
            uint256 mid = (low + high + 1) / 2;
            if (_mintIsReachable(mid) == false || _rawAmountsIn(mid)[_waUsdc6Idx] <= targetRaw) {
                low = mid;
            } else {
                high = mid - 1;
            }
        }

        return low;
    }

    /// @dev Limits well above what the tokens cost, so the caller's limit is never what fails.
    function _generousMaxAmountsIn(uint256[] memory required) private view returns (uint256[] memory maxAmountsIn) {
        maxAmountsIn = new uint256[](2);
        maxAmountsIn[_waUsdc6Idx] = required[_waUsdc6Idx] * 4 + 1e6;
        maxAmountsIn[_waDaiIdx] = required[_waDaiIdx] * 4 + 1e18;
    }

    /// @dev Raw amounts a recovery withdrawal of `bptIn` would return. It applies no minimum trade amount.
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
