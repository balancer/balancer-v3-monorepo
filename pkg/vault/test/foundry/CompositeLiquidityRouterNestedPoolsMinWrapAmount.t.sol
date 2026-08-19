// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {
    ICompositeLiquidityRouterErrors
} from "@balancer-labs/v3-interfaces/contracts/vault/ICompositeLiquidityRouterErrors.sol";
import { IVaultAdmin } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultAdmin.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { CompositeLiquidityRouterMinWrapAmountBase } from "./utils/CompositeLiquidityRouterMinWrapAmountBase.sol";
import { BalancerPoolToken } from "../../contracts/BalancerPoolToken.sol";

/**
 * @notice Nested-pool unwrap behavior at the Vault minimums the deployed Vaults actually report.
 * @dev The fixture is `CompositeLiquidityRouterMinWrapAmountBase`; this suite drives the nested remove entry point
 * across the band in which the buffer rejects a non-zero amount, and pins where that path changes behavior and
 * where it does not.
 *
 * At a redeem rate of exactly one, which is what this suite's wrapper carries, the first accepted raw amount is
 * two above the Vault's stated minimum rather than equal to it, because `erc4626BufferWrapOrUnwrap` applies that
 * minimum twice: once to the amount given, and once to the calculated output, which for an EXACT_IN unwrap is
 * `previewRedeem(amount - 1) - 1`. At a rate comfortably above one the second check is slack and the first
 * accepted amount falls back to the stated minimum; below one it rises well above it, which is exercised here.
 * The boundary is therefore a property of the wrapper rather than a constant, so never write a router-side check
 * against `getMinimumWrapAmount()` alone.
 *
 * The amount is the pool's rather than the caller's at both levels of the traversal, and the caller declares the
 * output tokens up front, so an amount the buffer will not unwrap fails with `UnwrapAmountTooSmall` naming the
 * token and that amount, which is what proportional removal from an ERC4626 pool reports for the same condition.
 * A parent pool is set up alongside the pool this suite removes from, so both of the traversal's unwrap call
 * sites are covered: the token in the pool the caller names, and the token in a child pool below it.
 */
contract CompositeLiquidityRouterNestedPoolsMinWrapAmountTest is CompositeLiquidityRouterMinWrapAmountBase {
    using ArrayHelpers for *;

    // A parent pool holding `pool` as a child, so the traversal reaches the unwrap at the child level as well.
    address private _parentPool;

    function setUp() public override {
        CompositeLiquidityRouterMinWrapAmountBase.setUp();

        _createParentPool();
    }

    /// @dev `pool` becomes a child of `_parentPool`, whose other token is an ordinary ERC20.
    function _createParentPool() private {
        (_parentPool, ) = _createPool([pool, address(usdc)].toMemoryArray(), "parentPool");

        approveForPool(IERC20(pool));
        approveForPool(IERC20(_parentPool));

        uint256 childBptBalance = BalancerPoolToken(pool).balanceOf(lp);

        (uint256 childIdx, uint256 usdcIdx) = getSortedIndexes(pool, address(usdc));

        uint256[] memory amountsIn = new uint256[](2);
        amountsIn[childIdx] = childBptBalance / 2;
        amountsIn[usdcIdx] = poolInitAmount;

        vm.startPrank(lp);
        _initPool(_parentPool, amountsIn, 0);
        vm.stopPrank();
    }

    /// @dev Zero is the case the guard covers, and it is covered at the real minimum, not just the test default.
    function testNestedZeroUnwrapAtProductionMinimum() public {
        uint256 bptIn = _burnForRawWa6(0);
        assertEq(_rawAmountsOut(bptIn)[_wa6Idx], 0, "Setup: wa6 leg should be exactly zero");

        (address[] memory tokensOut, address[] memory tokensToUnwrap) = _tokenLists();
        (uint256 usdc6Idx, uint256 daiIdx) = getSortedIndexes(address(usdc6Decimals), address(dai));

        vm.prank(lp);
        uint256[] memory amountsOut = compositeLiquidityRouter.removeLiquidityProportionalNestedPool(
            pool,
            bptIn,
            tokensOut,
            new uint256[](2),
            tokensToUnwrap,
            false,
            bytes("")
        );

        assertEq(amountsOut[usdc6Idx], 0, "Zero leg should report zero");
        assertGt(amountsOut[daiIdx], 0, "DAI leg should be non-zero");
    }

    /**
     * @dev Everything between zero and the first accepted amount still reverts, and the zero guard does not change
     * that. Unlike zero, these amounts carry a wrapped credit that has no other consumer, so they cannot simply be
     * skipped. The failure is reported as `UnwrapAmountTooSmall`, naming the token and the amount the pool produced,
     * which is what the flat ERC4626 remove path reports for the same condition.
     */
    function testNestedSubMinimumBandRevertsWithRouterError() public {
        uint256[4] memory rawTargets = [uint256(1), 9999, _FIRST_ACCEPTED_RAW - 2, _FIRST_ACCEPTED_RAW - 1];

        for (uint256 i = 0; i < rawTargets.length; ++i) {
            uint256 bptIn = _burnForRawWa6(rawTargets[i]);
            assertEq(_rawAmountsOut(bptIn)[_wa6Idx], rawTargets[i], "Setup: wrong raw wa6 amount");

            (address[] memory tokensOut, address[] memory tokensToUnwrap) = _tokenLists();

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
            compositeLiquidityRouter.removeLiquidityProportionalNestedPool(
                pool,
                bptIn,
                tokensOut,
                new uint256[](2),
                tokensToUnwrap,
                false,
                bytes("")
            );

            // Nothing partial is left behind, and the wrapped token is not delivered in place of the underlying.
            assertEq(BalancerPoolToken(pool).balanceOf(lp), bptBefore, "BPT was burned");
            assertEq(_wa6.balanceOf(lp), wa6Before, "The wrapped token was delivered");
            assertEq(usdc6Decimals.balanceOf(lp), usdcBefore, "The underlying token was delivered");

            vm.revertToState(snapshotId);
        }
    }

    /// @dev The query reverts with the identical error, so a caller learns this without spending a transaction.
    function testNestedSubMinimumQueryMatchesExecution() public {
        uint256[2] memory rawTargets = [uint256(1), _FIRST_ACCEPTED_RAW - 1];

        for (uint256 i = 0; i < rawTargets.length; ++i) {
            uint256 bptIn = _burnForRawWa6(rawTargets[i]);

            (address[] memory tokensOut, address[] memory tokensToUnwrap) = _tokenLists();

            uint256 snapshotId = vm.snapshotState();

            _prankStaticCall();
            vm.expectRevert(
                abi.encodeWithSelector(
                    ICompositeLiquidityRouterErrors.UnwrapAmountTooSmall.selector,
                    address(_wa6),
                    rawTargets[i]
                )
            );
            compositeLiquidityRouter.queryRemoveLiquidityProportionalNestedPool(
                pool,
                bptIn,
                tokensOut,
                tokensToUnwrap,
                lp,
                bytes("")
            );

            vm.revertToState(snapshotId);
        }
    }

    /**
     * @dev This path's boundary is a property of the wrapper, exactly as the flat path's is. At a redeem rate of one
     * half a raw wrapped amount of 15000 clears the Vault's stated minimum of 10000 and is still refused, because the
     * minimum is applied again to the underlying it redeems to. A router-side check written against
     * `getMinimumWrapAmount()` would wave this through.
     */
    function testNestedBelowParRateRefusesAmountAboveTheStatedMinimum() public {
        _wa6.mockRate(FixedPoint.ONE / 2);
        assertLt(_wa6.getRate(), FixedPoint.ONE, "Setup: the rate did not fall below one");

        uint256 rawTarget = 15000;
        assertGt(rawTarget, vault.getMinimumWrapAmount(), "Setup: the target is not above the stated minimum");

        uint256 bptIn = _burnForRawWa6(rawTarget);
        assertEq(_rawAmountsOut(bptIn)[_wa6Idx], rawTarget, "Setup: wrong raw wa6 amount");

        (address[] memory tokensOut, address[] memory tokensToUnwrap) = _tokenLists();

        vm.prank(lp);
        vm.expectRevert(
            abi.encodeWithSelector(
                ICompositeLiquidityRouterErrors.UnwrapAmountTooSmall.selector,
                address(_wa6),
                rawTarget
            )
        );
        compositeLiquidityRouter.removeLiquidityProportionalNestedPool(
            pool,
            bptIn,
            tokensOut,
            new uint256[](2),
            tokensToUnwrap,
            false,
            bytes("")
        );
    }

    /**
     * @dev The traversal reaches this unwrap at two levels, and both report the same way. Here the wrapper sits in a
     * child pool rather than in the pool the caller names, so the amount is the child's share of what the parent's
     * own removal produced.
     */
    function testNestedChildLevelSubMinimumRevertsWithRouterError() public {
        uint256 rawTarget = _FIRST_ACCEPTED_RAW - 1;
        uint256 parentBptIn = _burnParentForRawWa6(rawTarget);
        assertEq(_childRawWa6Out(parentBptIn), rawTarget, "Setup: wrong raw wa6 amount at the child level");

        (address[] memory tokensOut, address[] memory tokensToUnwrap) = _parentTokenLists();

        vm.prank(lp);
        vm.expectRevert(
            abi.encodeWithSelector(
                ICompositeLiquidityRouterErrors.UnwrapAmountTooSmall.selector,
                address(_wa6),
                rawTarget
            )
        );
        compositeLiquidityRouter.removeLiquidityProportionalNestedPool(
            _parentPool,
            parentBptIn,
            tokensOut,
            new uint256[](3),
            tokensToUnwrap,
            false,
            bytes("")
        );
    }

    /// @dev A failure that is not this one keeps the Vault's own error rather than being reported as too small.
    function testNestedOtherBufferFailuresAreNotReinterpreted() public {
        uint256 bptIn = _burnForRawWa6(20000);

        (address[] memory tokensOut, address[] memory tokensToUnwrap) = _tokenLists();

        vm.prank(admin);
        IVaultAdmin(address(vault)).pauseVaultBuffers();

        vm.prank(lp);
        vm.expectRevert(IVaultErrors.VaultBuffersArePaused.selector);
        compositeLiquidityRouter.removeLiquidityProportionalNestedPool(
            pool,
            bptIn,
            tokensOut,
            new uint256[](2),
            tokensToUnwrap,
            false,
            bytes("")
        );
    }

    /// @dev The boundary itself, and an ordinary amount above it. Both unaffected by the zero handling.
    function testNestedBoundaryAcceptedAmount() public {
        uint256[2] memory rawTargets = [_FIRST_ACCEPTED_RAW, uint256(20000)];

        (uint256 usdc6Idx, uint256 daiIdx) = getSortedIndexes(address(usdc6Decimals), address(dai));

        for (uint256 i = 0; i < rawTargets.length; ++i) {
            uint256 bptIn = _burnForRawWa6(rawTargets[i]);
            assertEq(_rawAmountsOut(bptIn)[_wa6Idx], rawTargets[i], "Setup: wrong raw wa6 amount");

            (address[] memory tokensOut, address[] memory tokensToUnwrap) = _tokenLists();

            uint256 snapshotId = vm.snapshotState();
            vm.prank(lp);
            uint256[] memory amountsOut = compositeLiquidityRouter.removeLiquidityProportionalNestedPool(
                pool,
                bptIn,
                tokensOut,
                new uint256[](2),
                tokensToUnwrap,
                false,
                bytes("")
            );

            // The unwrap deducts two wei: one from the amount given, one from the preview result.
            assertEq(amountsOut[usdc6Idx], rawTargets[i] - 2, "USDC-6 leg is wrong");
            assertGt(amountsOut[daiIdx], 0, "DAI leg should be non-zero");
            vm.revertToState(snapshotId);
        }
    }

    /// @dev The parent adds its own ERC20 to the set the child produces.
    function _parentTokenLists() private view returns (address[] memory tokensOut, address[] memory tokensToUnwrap) {
        (address[] memory childTokensOut, address[] memory unwrapList) = _tokenLists();

        tokensOut = new address[](3);
        tokensOut[0] = childTokensOut[0];
        tokensOut[1] = childTokensOut[1];
        tokensOut[2] = address(usdc);

        tokensToUnwrap = unwrapList;
    }

    /// @dev Raw wa6 the child pool would produce for a proportional burn of `parentBptIn` of the parent pool.
    function _childRawWa6Out(uint256 parentBptIn) private returns (uint256) {
        uint256 snapshotId = vm.snapshotState();
        _prankStaticCall();
        uint256[] memory parentAmountsOut = router.queryRemoveLiquidityProportional(
            _parentPool,
            parentBptIn,
            address(this),
            bytes("")
        );
        (uint256 childIdx, ) = getSortedIndexes(pool, address(usdc));

        _prankStaticCall();
        uint256[] memory childAmountsOut = router.queryRemoveLiquidityProportional(
            pool,
            parentAmountsOut[childIdx],
            address(this),
            bytes("")
        );
        vm.revertToState(snapshotId);

        return childAmountsOut[_wa6Idx];
    }

    /// @dev Largest parent-pool `bptIn` whose child-level raw wa6 output is at most `targetRaw`.
    function _burnParentForRawWa6(uint256 targetRaw) private returns (uint256) {
        uint256 low = PRODUCTION_MIN_TRADE_AMOUNT;
        uint256 high = BalancerPoolToken(_parentPool).balanceOf(lp);

        while (low < high) {
            uint256 mid = (low + high + 1) / 2;
            if (_childRawWa6Out(mid) <= targetRaw) {
                low = mid;
            } else {
                high = mid - 1;
            }
        }

        return low;
    }
}
