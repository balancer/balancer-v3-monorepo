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
 * @notice Nested-pool unwrap behavior at the production Vault minimums.
 * @dev The fixture is `CompositeLiquidityRouterMinWrapAmountBase`, with a parent pool added on top of it so that
 * both unwrap call sites are covered: the token in the pool the caller names, and the token in a child pool.
 */
contract CompositeLiquidityRouterNestedPoolsMinWrapAmountTest is CompositeLiquidityRouterMinWrapAmountBase {
    using ArrayHelpers for *;

    // Holds `pool` as a child, so an unwrap can happen at the child level.
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

    /// @dev A zero share reports zero and the withdrawal succeeds, at the production minimum as at the default.
    function testNestedZeroUnwrapAtProductionMinimum() public {
        uint256 bptIn = _burnForRawWaUsdc6(0);
        assertEq(_rawAmountsOut(bptIn)[_waUsdc6Idx], 0, "Setup: waUSDC6 share should be exactly zero");

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

        assertEq(amountsOut[usdc6Idx], 0, "Zero share should report zero");
        assertGt(amountsOut[daiIdx], 0, "DAI amount should be non-zero");
    }

    /**
     * @dev Sub-minimum waUSDC6 shares revert with `UnwrapAmountTooSmall(waUSDC6, amount)`, and no balance moves. The
     * sampled amounts cover both rejection paths: 1 and 9999 fail the Vault's check on the amount given, while the
     * two just below `_FIRST_ACCEPTED_RAW` clear that and fail the check on the underlying they redeem to. Unlike a
     * zero share (`testNestedZeroUnwrapAtProductionMinimum`), these carry a wrapped credit with no other consumer,
     * so the router cannot skip them.
     */
    function testNestedSubMinimumBandRevertsWithRouterError() public {
        uint256[4] memory rawTargets = [uint256(1), 9999, _FIRST_ACCEPTED_RAW - 2, _FIRST_ACCEPTED_RAW - 1];

        for (uint256 i = 0; i < rawTargets.length; ++i) {
            uint256 bptIn = _burnForRawWaUsdc6(rawTargets[i]);
            assertEq(_rawAmountsOut(bptIn)[_waUsdc6Idx], rawTargets[i], "Setup: wrong raw waUSDC6 amount");

            (address[] memory tokensOut, address[] memory tokensToUnwrap) = _tokenLists();

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
            compositeLiquidityRouter.removeLiquidityProportionalNestedPool(
                pool,
                bptIn,
                tokensOut,
                new uint256[](2),
                tokensToUnwrap,
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
    function testNestedSubMinimumQueryMatchesExecution() public {
        uint256[2] memory rawTargets = [uint256(1), _FIRST_ACCEPTED_RAW - 1];

        for (uint256 i = 0; i < rawTargets.length; ++i) {
            uint256 bptIn = _burnForRawWaUsdc6(rawTargets[i]);

            (address[] memory tokensOut, address[] memory tokensToUnwrap) = _tokenLists();

            uint256 snapshotId = vm.snapshotState();

            _prankStaticCall();
            vm.expectRevert(
                abi.encodeWithSelector(
                    ICompositeLiquidityRouterErrors.UnwrapAmountTooSmall.selector,
                    address(_waUSDC6),
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
     * @dev The boundary depends on the wrapper's rate, not on the Vault's constant alone. At a redeem rate of 0.5,
     * 15000 wrapped clears the stated minimum of 10000 but redeems to only ~7498 underlying, which does not, and the
     * Vault applies the minimum to both. A router-side pre-check against `getMinimumWrapAmount()` would let this
     * through, and the Vault would reject it anyway.
     */
    function testNestedBelowParRateRefusesAmountAboveTheStatedMinimum() public {
        _waUSDC6.mockRate(FixedPoint.ONE / 2);
        assertLt(_waUSDC6.getRate(), FixedPoint.ONE, "Setup: the rate did not fall below one");

        uint256 rawTarget = 15000;
        assertGt(rawTarget, vault.getMinimumWrapAmount(), "Setup: the target is not above the stated minimum");

        uint256 bptIn = _burnForRawWaUsdc6(rawTarget);
        assertEq(_rawAmountsOut(bptIn)[_waUsdc6Idx], rawTarget, "Setup: wrong raw waUSDC6 amount");

        (address[] memory tokensOut, address[] memory tokensToUnwrap) = _tokenLists();

        vm.prank(lp);
        vm.expectRevert(
            abi.encodeWithSelector(
                ICompositeLiquidityRouterErrors.UnwrapAmountTooSmall.selector,
                address(_waUSDC6),
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
     * @dev This test unwraps a token at the child level, which should revert with the same router error raised
     * when the unwrap happens in the parent pool (the pool parameter passed by the caller).
     */
    function testNestedChildLevelSubMinimumRevertsWithRouterError() public {
        uint256 rawTarget = _FIRST_ACCEPTED_RAW - 1;
        uint256 parentBptIn = _burnParentForRawWaUsdc6(rawTarget);
        assertEq(_childRawWaUsdc6Out(parentBptIn), rawTarget, "Setup: wrong raw waUSDC6 amount at the child level");

        (address[] memory tokensOut, address[] memory tokensToUnwrap) = _parentTokenLists();

        vm.prank(lp);
        vm.expectRevert(
            abi.encodeWithSelector(
                ICompositeLiquidityRouterErrors.UnwrapAmountTooSmall.selector,
                address(_waUSDC6),
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

    /// @dev Any other buffer failure keeps the Vault's own error.
    function testNestedOtherBufferFailuresAreNotReinterpreted() public {
        uint256 bptIn = _burnForRawWaUsdc6(20000);

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

    /// @dev The boundary itself, and an ordinary amount above it.
    function testNestedBoundaryAcceptedAmount() public {
        uint256[2] memory rawTargets = [_FIRST_ACCEPTED_RAW, uint256(20000)];

        (uint256 usdc6Idx, uint256 daiIdx) = getSortedIndexes(address(usdc6Decimals), address(dai));

        for (uint256 i = 0; i < rawTargets.length; ++i) {
            uint256 bptIn = _burnForRawWaUsdc6(rawTargets[i]);
            assertEq(_rawAmountsOut(bptIn)[_waUsdc6Idx], rawTargets[i], "Setup: wrong raw waUSDC6 amount");

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

            // The unwrap deducts 2 wei: 1 from the amount given, 1 from the preview result.
            assertEq(amountsOut[usdc6Idx], rawTargets[i] - 2, "USDC-6 amount is wrong");
            assertGt(amountsOut[daiIdx], 0, "DAI amount should be non-zero");
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

    /// @dev Raw waUSDC6 the child pool would produce for a proportional burn of `parentBptIn` of the parent pool.
    function _childRawWaUsdc6Out(uint256 parentBptIn) private returns (uint256) {
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

        return childAmountsOut[_waUsdc6Idx];
    }

    /// @dev Largest parent-pool `bptIn` whose child-level raw waUSDC6 output is at most `targetRaw`.
    function _burnParentForRawWaUsdc6(uint256 targetRaw) private returns (uint256) {
        uint256 low = PRODUCTION_MIN_TRADE_AMOUNT;
        uint256 high = BalancerPoolToken(_parentPool).balanceOf(lp);

        while (low < high) {
            uint256 mid = (low + high + 1) / 2;
            if (_childRawWaUsdc6Out(mid) <= targetRaw) {
                low = mid;
            } else {
                high = mid - 1;
            }
        }

        return low;
    }
}
