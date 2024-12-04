// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { ERC4626TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC4626TestToken.sol";
import { ScalingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ScalingHelpers.sol";
import {
    BufferWrapOrUnwrapParams,
    SwapKind,
    WrappingDirection
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { IBatchRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IBatchRouter.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";

import { BaseVaultTest } from "../utils/BaseVaultTest.sol";

contract VaultBufferUnitTest is BaseVaultTest {
    using ScalingHelpers for uint256;

    ERC4626TestToken internal wDaiInitialized;
    ERC4626TestToken internal wUSDCNotInitialized;

    uint256 private constant _userAmount = 10e6 * 1e18;
    uint256 private constant _wrapAmount = _userAmount / 100;
    uint256 private _minWrapAmount;

    function setUp() public virtual override {
        BaseVaultTest.setUp();

        _createWrappedToken();
        _mintTokensToLpAndYBProtocol();
        _initializeBuffer();

        _minWrapAmount = vaultAdmin.getMinimumWrapAmount();
    }

    function testIsERC4626BufferInitialized() public view {
        assertTrue(vault.isERC4626BufferInitialized(IERC4626(address(wDaiInitialized))));
        assertFalse(vault.isERC4626BufferInitialized(IERC4626(address(wUSDCNotInitialized))));
    }

    function testGetERC4626BufferAsset() public view {
        assertEq(
            vault.getERC4626BufferAsset(IERC4626(address(wDaiInitialized))),
            IERC4626(address(wDaiInitialized)).asset()
        );
        assertEq(vault.getERC4626BufferAsset(IERC4626(address(wUSDCNotInitialized))), address(0));
    }

    function testUnderlyingImbalanceBalanceZero() public view {
        int256 imbalance = vault.internalGetBufferUnderlyingImbalance(IERC4626(address(wUSDCNotInitialized)));
        assertEq(imbalance, int256(0), "Wrong underlying imbalance");
    }

    function testUnderlyingImbalanceOfWrappedBalance() public {
        // Unbalances buffer so that buffer has less underlying than wrapped.
        IBatchRouter.SwapPathExactAmountIn[] memory paths = _exactInWrapUnwrapPath(
            _wrapAmount / 2,
            0,
            IERC20(address(wDaiInitialized)),
            dai,
            IERC20(address(wDaiInitialized))
        );

        vm.prank(lp);
        batchRouter.swapExactIn(paths, MAX_UINT256, false, bytes(""));

        (uint256 underlyingBalance, uint256 wrappedBalance) = vault.getBufferBalance(
            IERC4626(address(wDaiInitialized))
        );
        // The buffer takes some extra wei to compensate rounding.
        assertApproxEqAbs(underlyingBalance, _wrapAmount / 2 + 1, 1, "Wrong buffer underlying balance");
        assertEq(wrappedBalance, (3 * _wrapAmount) / 2, "Wrong wrapped underlying balance");

        int256 imbalance = vault.internalGetBufferUnderlyingImbalance(IERC4626(address(wDaiInitialized)));
        // The wrapped rate is 1. Buffer imbalance = `(underlyingBalance - wrappedBalance) / 2`, and it has more wrapped
        // than underlying, so the imbalance is negative.
        assertApproxEqAbs(imbalance, -int256(_wrapAmount / 2), 1, "Wrong underlying imbalance");
    }

    function testUnderlyingImbalanceOfUnderlyingBalance() public {
        // Unbalances buffer so that buffer has more underlying than wrapped.
        IBatchRouter.SwapPathExactAmountIn[] memory paths = _exactInWrapUnwrapPath(
            _wrapAmount / 2,
            0,
            dai,
            IERC20(address(wDaiInitialized)),
            IERC20(address(wDaiInitialized))
        );

        vm.startPrank(lp);
        batchRouter.swapExactIn(paths, MAX_UINT256, false, bytes(""));

        // Mock token rate to 2, so we can validate the calculation of imbalance taking the rate into consideration.
        wDaiInitialized.mockRate(2e18);
        vm.stopPrank();

        // Rounds up to make sure division is done properly.
        assertEq(wDaiInitialized.getRate().computeRateRoundUp(), 2e18, "Wrong wDAI rate");

        int256 imbalance = vault.internalGetBufferUnderlyingImbalance(IERC4626(address(wDaiInitialized)));
        // Before swap, buffer had _wrapAmount of underlying and wrapped.
        // After swap, buffer has 3/2 _wrapAmount of underlying and 1/2 _wrapAmount of wrapped.
        // imbalance = (3/2 _wrapAmount - (1/2 _wrapAmount* rate)) / 2 =
        // `1/4 _wrapAmount`.
        uint256 bufferUnderlyingBalance = (3 * _wrapAmount) / 2;
        uint256 bufferWrappedBalance = _wrapAmount / 2;
        uint256 bufferWrappedBalanceAsUnderlying = _vaultPreviewMint(wDaiInitialized, bufferWrappedBalance);
        uint256 exactUnderlyingImbalance = (bufferUnderlyingBalance - bufferWrappedBalanceAsUnderlying) / 2;
        assertEq(imbalance, int256(exactUnderlyingImbalance), "Underlying imbalance different than exact calculation");
        assertApproxEqAbs(
            imbalance,
            int256(_wrapAmount / 4),
            2,
            "Underlying imbalance different than theoretical value"
        );
    }

    function testWrappedImbalanceBalanceZero() public view {
        int256 imbalance = vault.internalGetBufferWrappedImbalance(IERC4626(address(wUSDCNotInitialized)));
        assertEq(imbalance, int256(0), "Wrong wrapped imbalance");
    }

    function testWrappedImbalanceOfUnderlyingBalance() public {
        // Unbalances buffer so that buffer has more underlying than wrapped.
        IBatchRouter.SwapPathExactAmountIn[] memory paths = _exactInWrapUnwrapPath(
            _wrapAmount / 2,
            0,
            dai,
            IERC20(address(wDaiInitialized)),
            IERC20(address(wDaiInitialized))
        );

        vm.prank(lp);
        batchRouter.swapExactIn(paths, MAX_UINT256, false, bytes(""));

        (uint256 underlyingBalance, uint256 wrappedBalance) = vault.getBufferBalance(
            IERC4626(address(wDaiInitialized))
        );
        assertEq(underlyingBalance, (3 * _wrapAmount) / 2, "Wrong buffer underlying balance");

        // The buffer takes some extra wei to compensate rounding.
        assertApproxEqAbs(wrappedBalance, _wrapAmount / 2 + 1, 1, "Wrong wrapped underlying balance");

        int256 imbalance = vault.internalGetBufferWrappedImbalance(IERC4626(address(wDaiInitialized)));
        // The wrapped rate is 1. Buffer imbalance = `(wrappedBalance - underlyingBalance) / 2`, and it has more
        // underlying than wrapped, so the imbalance is negative.
        assertApproxEqAbs(imbalance, -int256(_wrapAmount / 2), 1, "Wrong wrapped imbalance");
    }

    function testWrappedImbalanceOfWrappedBalance() public {
        // Unbalances buffer so that buffer has less underlying than wrapped (so it has an imbalance of wrapped).
        IBatchRouter.SwapPathExactAmountIn[] memory paths = _exactInWrapUnwrapPath(
            _wrapAmount / 2,
            0,
            IERC20(address(wDaiInitialized)),
            dai,
            IERC20(address(wDaiInitialized))
        );

        vm.startPrank(lp);
        batchRouter.swapExactIn(paths, MAX_UINT256, false, bytes(""));

        // rate = assets / supply. If we double the assets, we double the rate.
        // Donate to wrapped token to inflate rate to 2
        wDaiInitialized.mockRate(2e18);
        vm.stopPrank();

        // Rounds up to make sure division is done properly.
        assertEq(wDaiInitialized.getRate().computeRateRoundUp(), 2e18, "Wrong wDAI rate");

        int256 imbalance = vault.internalGetBufferWrappedImbalance(IERC4626(address(wDaiInitialized)));
        // Before swap, buffer had _wrapAmount of underlying and wrapped.
        // After swap, buffer has `1/2 _wrapAmount` of underlying and 3/2 _wrapAmount of wrapped.
        // imbalance = (3/2 _wrapAmount - (1/2 _wrapAmount / rate)) / 2 = `5/8 _wrapAmount`.
        uint256 bufferWrappedBalance = (3 * _wrapAmount) / 2;
        uint256 bufferUnderlyingBalance = _wrapAmount / 2;
        uint256 bufferUnderlyingBalanceAsWrapped = _vaultPreviewWithdraw(wDaiInitialized, bufferUnderlyingBalance);
        uint256 exactWrappedImbalance = (bufferWrappedBalance - bufferUnderlyingBalanceAsWrapped) / 2;
        assertEq(imbalance, int256(exactWrappedImbalance), "Wrapped imbalance different than exact calculation");
        assertApproxEqAbs(
            imbalance,
            int256((5 * _wrapAmount) / 8),
            1,
            "Wrapped imbalance different than theoretical value"
        );
    }

    function testSettleWrap() public {
        uint256 actualUnderlyingDeposited = 4e6;
        uint256 actualWrappedMinted = 2e5;

        _simulateWrapOperation(actualUnderlyingDeposited, actualWrappedMinted);

        uint256 wrappedReservesBefore = vault.getReservesOf(IERC20(address(wDaiInitialized)));
        uint256 underlyingReservesBefore = vault.getReservesOf(dai);

        vault.manualSettleWrap(dai, IERC20(address(wDaiInitialized)), actualUnderlyingDeposited, actualWrappedMinted);

        _checkVaultReservesAfterWrap(
            underlyingReservesBefore,
            wrappedReservesBefore,
            actualUnderlyingDeposited,
            actualWrappedMinted
        );
    }

    function testSettleWrapWithMoreUnderlyingDeposited() public {
        uint256 actualUnderlyingDeposited = 4e6;
        uint256 expectedUnderlyingDeposited = actualUnderlyingDeposited - 1;
        uint256 actualWrappedMinted = 2e5;

        _simulateWrapOperation(actualUnderlyingDeposited, actualWrappedMinted);

        uint256 underlyingReservesBefore = vault.getReservesOf(dai);

        // _settleWrap will revert because the wrap operation deposited more underlying tokens than expected.
        vm.expectRevert(
            abi.encodeWithSelector(
                IVaultErrors.NotEnoughUnderlying.selector,
                IERC4626(address(wDaiInitialized)),
                underlyingReservesBefore - expectedUnderlyingDeposited,
                underlyingReservesBefore - actualUnderlyingDeposited
            )
        );
        vault.manualSettleWrap(dai, IERC20(address(wDaiInitialized)), expectedUnderlyingDeposited, actualWrappedMinted);
    }

    function testSettleWrapWithLessUnderlyingDeposited() public {
        uint256 actualUnderlyingDeposited = 4e6;
        uint256 expectedUnderlyingDeposited = actualUnderlyingDeposited + 1;
        uint256 actualWrappedMinted = 2e5;

        _simulateWrapOperation(actualUnderlyingDeposited, actualWrappedMinted);

        uint256 wrappedReservesBefore = vault.getReservesOf(IERC20(address(wDaiInitialized)));
        uint256 underlyingReservesBefore = vault.getReservesOf(dai);

        vault.manualSettleWrap(dai, IERC20(address(wDaiInitialized)), expectedUnderlyingDeposited, actualWrappedMinted);

        _checkVaultReservesAfterWrap(
            underlyingReservesBefore,
            wrappedReservesBefore,
            actualUnderlyingDeposited,
            actualWrappedMinted
        );
    }

    function testSettleWrapWithMoreWrappedMinted() public {
        uint256 actualUnderlyingDeposited = 4e6;
        uint256 actualWrappedMinted = 2e5;
        uint256 expectedWrappedMinted = actualWrappedMinted - 1;

        _simulateWrapOperation(actualUnderlyingDeposited, actualWrappedMinted);

        uint256 wrappedReservesBefore = vault.getReservesOf(IERC20(address(wDaiInitialized)));
        uint256 underlyingReservesBefore = vault.getReservesOf(dai);

        vault.manualSettleWrap(dai, IERC20(address(wDaiInitialized)), actualUnderlyingDeposited, expectedWrappedMinted);

        _checkVaultReservesAfterWrap(
            underlyingReservesBefore,
            wrappedReservesBefore,
            actualUnderlyingDeposited,
            actualWrappedMinted
        );
    }

    function testSettleWrapWithLessWrappedMinted() public {
        uint256 actualUnderlyingDeposited = 4e6;
        uint256 actualWrappedMinted = 2e5;
        uint256 expectedWrappedMinted = actualWrappedMinted + 1;

        _simulateWrapOperation(actualUnderlyingDeposited, actualWrappedMinted);

        uint256 wrappedReservesBefore = vault.getReservesOf(IERC20(address(wDaiInitialized)));

        // _settleWrap will revert because the wrap operation minted less wrapped tokens than expected.
        vm.expectRevert(
            abi.encodeWithSelector(
                IVaultErrors.NotEnoughWrapped.selector,
                IERC4626(address(wDaiInitialized)),
                wrappedReservesBefore + expectedWrappedMinted,
                wrappedReservesBefore + actualWrappedMinted
            )
        );
        vault.manualSettleWrap(dai, IERC20(address(wDaiInitialized)), actualUnderlyingDeposited, expectedWrappedMinted);
    }

    function testSettleUnwrap() public {
        uint256 actualUnderlyingWithdrawn = 4e6;
        uint256 actualWrappedBurned = 2e5;

        _simulateUnwrapOperation(actualUnderlyingWithdrawn, actualWrappedBurned);

        uint256 wrappedReservesBefore = vault.getReservesOf(IERC20(address(wDaiInitialized)));
        uint256 underlyingReservesBefore = vault.getReservesOf(dai);

        vault.manualSettleUnwrap(dai, IERC20(address(wDaiInitialized)), actualUnderlyingWithdrawn, actualWrappedBurned);

        _checkVaultReservesAfterUnwrap(
            underlyingReservesBefore,
            wrappedReservesBefore,
            actualUnderlyingWithdrawn,
            actualWrappedBurned
        );
    }

    function testSettleUnwrapWithMoreUnderlyingWithdrawn() public {
        uint256 actualUnderlyingWithdrawn = 4e6;
        uint256 expectedUnderlyingWithdrawn = actualUnderlyingWithdrawn - 1;
        uint256 actualWrappedBurned = 2e5;

        _simulateUnwrapOperation(actualUnderlyingWithdrawn, actualWrappedBurned);

        uint256 wrappedReservesBefore = vault.getReservesOf(IERC20(address(wDaiInitialized)));
        uint256 underlyingReservesBefore = vault.getReservesOf(dai);

        vault.manualSettleUnwrap(
            dai,
            IERC20(address(wDaiInitialized)),
            expectedUnderlyingWithdrawn,
            actualWrappedBurned
        );

        _checkVaultReservesAfterUnwrap(
            underlyingReservesBefore,
            wrappedReservesBefore,
            actualUnderlyingWithdrawn,
            actualWrappedBurned
        );
    }

    function testSettleUnwrapWithLessUnderlyingWithdrawn() public {
        uint256 actualUnderlyingWithdrawn = 4e6;
        uint256 expectedUnderlyingWithdrawn = actualUnderlyingWithdrawn + 1;
        uint256 actualWrappedBurned = 2e5;

        _simulateUnwrapOperation(actualUnderlyingWithdrawn, actualWrappedBurned);

        uint256 underlyingReservesBefore = vault.getReservesOf(dai);

        // _settleUnwrap will revert because the unwrap operation has withdrawn less underlying tokens than expected.
        vm.expectRevert(
            abi.encodeWithSelector(
                IVaultErrors.NotEnoughUnderlying.selector,
                IERC4626(address(wDaiInitialized)),
                underlyingReservesBefore + expectedUnderlyingWithdrawn,
                underlyingReservesBefore + actualUnderlyingWithdrawn
            )
        );
        vault.manualSettleUnwrap(
            dai,
            IERC20(address(wDaiInitialized)),
            expectedUnderlyingWithdrawn,
            actualWrappedBurned
        );
    }

    function testSettleUnwrapWithMoreWrappedBurned() public {
        uint256 actualUnderlyingWithdrawn = 4e6;
        uint256 actualWrappedBurned = 2e5;
        uint256 expectedWrappedBurned = actualWrappedBurned - 1;

        _simulateUnwrapOperation(actualUnderlyingWithdrawn, actualWrappedBurned);

        uint256 wrappedReservesBefore = vault.getReservesOf(IERC20(address(wDaiInitialized)));

        // _settleUnwrap will revert because the unwrap operation has burned more wrapped tokens than expected.
        vm.expectRevert(
            abi.encodeWithSelector(
                IVaultErrors.NotEnoughWrapped.selector,
                IERC4626(address(wDaiInitialized)),
                wrappedReservesBefore - expectedWrappedBurned,
                wrappedReservesBefore - actualWrappedBurned
            )
        );
        vault.manualSettleUnwrap(
            dai,
            IERC20(address(wDaiInitialized)),
            actualUnderlyingWithdrawn,
            expectedWrappedBurned
        );
    }

    function testSettleUnwrapWithLessWrappedBurned() public {
        uint256 actualUnderlyingWithdrawn = 4e6;
        uint256 actualWrappedBurned = 2e5;
        uint256 expectedWrappedBurned = actualWrappedBurned + 1;

        _simulateUnwrapOperation(actualUnderlyingWithdrawn, actualWrappedBurned);

        uint256 wrappedReservesBefore = vault.getReservesOf(IERC20(address(wDaiInitialized)));
        uint256 underlyingReservesBefore = vault.getReservesOf(dai);

        vault.manualSettleUnwrap(
            dai,
            IERC20(address(wDaiInitialized)),
            actualUnderlyingWithdrawn,
            expectedWrappedBurned
        );

        _checkVaultReservesAfterUnwrap(
            underlyingReservesBefore,
            wrappedReservesBefore,
            actualUnderlyingWithdrawn,
            actualWrappedBurned
        );
    }

    function testWrapExactOutAmountInLessThanMin() public {
        uint256 rate = 10_000;
        wDaiInitialized.mockRate(rate);

        BufferWrapOrUnwrapParams memory params = BufferWrapOrUnwrapParams({
            kind: SwapKind.EXACT_OUT,
            direction: WrappingDirection.WRAP,
            wrappedToken: IERC4626(address(wDaiInitialized)),
            amountGivenRaw: (_minWrapAmount - 1) * rate,
            limitRaw: UINT256_MAX
        });

        vault.forceUnlock();

        vm.expectRevert(
            abi.encodeWithSelector(IVaultErrors.WrapAmountTooSmall.selector, IERC4626(address(wDaiInitialized)))
        );
        vault.erc4626BufferWrapOrUnwrap(params);
    }

    function testWrapExactInAmountInLessThanMin() public {
        BufferWrapOrUnwrapParams memory params = BufferWrapOrUnwrapParams({
            kind: SwapKind.EXACT_IN,
            direction: WrappingDirection.WRAP,
            wrappedToken: IERC4626(address(wDaiInitialized)),
            amountGivenRaw: (_minWrapAmount - 1),
            limitRaw: UINT256_MAX
        });

        vault.forceUnlock();

        vm.expectRevert(
            abi.encodeWithSelector(IVaultErrors.WrapAmountTooSmall.selector, IERC4626(address(wDaiInitialized)))
        );
        vault.erc4626BufferWrapOrUnwrap(params);
    }

    function testUnwrapExactOutAmountInLessThanMin() public {
        uint256 rate = 10_000;
        wDaiInitialized.mockRate(rate);

        BufferWrapOrUnwrapParams memory params = BufferWrapOrUnwrapParams({
            kind: SwapKind.EXACT_OUT,
            direction: WrappingDirection.UNWRAP,
            wrappedToken: IERC4626(address(wDaiInitialized)),
            amountGivenRaw: (_minWrapAmount - 1) * rate,
            limitRaw: UINT256_MAX
        });

        vault.forceUnlock();

        vm.expectRevert(
            abi.encodeWithSelector(IVaultErrors.WrapAmountTooSmall.selector, IERC4626(address(wDaiInitialized)))
        );
        vault.erc4626BufferWrapOrUnwrap(params);
    }

    function testUnwrapExactInAmountInLessThanMin() public {
        BufferWrapOrUnwrapParams memory params = BufferWrapOrUnwrapParams({
            kind: SwapKind.EXACT_IN,
            direction: WrappingDirection.UNWRAP,
            wrappedToken: IERC4626(address(wDaiInitialized)),
            amountGivenRaw: (_minWrapAmount - 1),
            limitRaw: UINT256_MAX
        });

        vault.forceUnlock();

        vm.expectRevert(
            abi.encodeWithSelector(IVaultErrors.WrapAmountTooSmall.selector, IERC4626(address(wDaiInitialized)))
        );
        vault.erc4626BufferWrapOrUnwrap(params);
    }

    function _checkVaultReservesAfterWrap(
        uint256 underlyingReservesBefore,
        uint256 wrappedReservesBefore,
        uint256 underlyingDeltaHint,
        uint256 wrappedDeltaHint
    ) private view {
        // Measure reserves after the wrap operation.
        uint256 wrappedReservesAfter = vault.getReservesOf(IERC20(address(wDaiInitialized)));
        uint256 underlyingReservesAfter = vault.getReservesOf(dai);

        // Assumes that the expected amount was deposited and discards any imbalance of underlying tokens.
        assertEq(
            underlyingReservesBefore - underlyingReservesAfter,
            underlyingDeltaHint,
            "Wrong reserves of underlying"
        );
        // Assumes that the expected amount was minted and discards any imbalance of wrapped tokens.
        assertEq(wrappedReservesAfter - wrappedReservesBefore, wrappedDeltaHint, "Wrong reserves of wrapped");
    }

    function _checkVaultReservesAfterUnwrap(
        uint256 underlyingReservesBefore,
        uint256 wrappedReservesBefore,
        uint256 underlyingDeltaHint,
        uint256 wrappedDeltaHint
    ) private view {
        // Measure reserves after the unwrap operation.
        uint256 wrappedReservesAfter = vault.getReservesOf(IERC20(address(wDaiInitialized)));
        uint256 underlyingReservesAfter = vault.getReservesOf(dai);

        // Assumes that the expected amount was withdrawn and discards any imbalance of underlying tokens.
        assertEq(
            underlyingReservesAfter - underlyingReservesBefore,
            underlyingDeltaHint,
            "Wrong reserves of underlying"
        );
        // Assumes that the expected amount was burned and discards any imbalance of wrapped tokens.
        assertEq(wrappedReservesBefore - wrappedReservesAfter, wrappedDeltaHint, "Wrong reserves of wrapped");
    }

    function _createWrappedToken() private {
        wDaiInitialized = new ERC4626TestToken(dai, "Wrapped DAI", "wDAI", 18);
        vm.label(address(wDaiInitialized), "wToken");

        // "USDC" is deliberately 18 decimals to test one thing at a time.
        wUSDCNotInitialized = new ERC4626TestToken(usdc, "Wrapped USDC", "wUSDC", 18);
        vm.label(address(wUSDCNotInitialized), "wUSDC");
    }

    function _mintTokensToLpAndYBProtocol() private {
        // Fund LP
        vm.startPrank(lp);

        dai.mint(lp, 3 * _userAmount);
        dai.approve(address(wDaiInitialized), _userAmount);
        wDaiInitialized.deposit(_userAmount, lp);

        usdc.mint(lp, 3 * _userAmount);
        usdc.approve(address(wUSDCNotInitialized), _userAmount);
        wUSDCNotInitialized.deposit(_userAmount, lp);

        wDaiInitialized.approve(address(permit2), MAX_UINT256);
        permit2.approve(address(wDaiInitialized), address(router), type(uint160).max, type(uint48).max);
        permit2.approve(address(wDaiInitialized), address(bufferRouter), type(uint160).max, type(uint48).max);
        permit2.approve(address(wDaiInitialized), address(batchRouter), type(uint160).max, type(uint48).max);
        wUSDCNotInitialized.approve(address(permit2), MAX_UINT256);
        permit2.approve(address(wUSDCNotInitialized), address(router), type(uint160).max, type(uint48).max);
        permit2.approve(address(wUSDCNotInitialized), address(bufferRouter), type(uint160).max, type(uint48).max);
        permit2.approve(address(wUSDCNotInitialized), address(batchRouter), type(uint160).max, type(uint48).max);
        vm.stopPrank();

        // Fund a yield-bearing protocol, in this case represented by Bob.
        vm.startPrank(bob);

        dai.mint(bob, 3 * _userAmount);
        dai.approve(address(wDaiInitialized), _userAmount);
        wDaiInitialized.deposit(_userAmount, bob);

        usdc.mint(bob, 3 * _userAmount);
        usdc.approve(address(wUSDCNotInitialized), _userAmount);
        wUSDCNotInitialized.deposit(_userAmount, bob);

        wDaiInitialized.approve(address(permit2), MAX_UINT256);
        permit2.approve(address(wDaiInitialized), address(router), type(uint160).max, type(uint48).max);
        permit2.approve(address(wDaiInitialized), address(batchRouter), type(uint160).max, type(uint48).max);
        wUSDCNotInitialized.approve(address(permit2), MAX_UINT256);
        permit2.approve(address(wUSDCNotInitialized), address(router), type(uint160).max, type(uint48).max);
        permit2.approve(address(wUSDCNotInitialized), address(batchRouter), type(uint160).max, type(uint48).max);
        vm.stopPrank();
    }

    function _initializeBuffer() private {
        vm.prank(lp);
        bufferRouter.initializeBuffer(IERC4626(address(wDaiInitialized)), _wrapAmount, _wrapAmount, 0);
    }

    function _simulateWrapOperation(uint256 underlyingToDeposit, uint256 wrappedToMint) private {
        // 1) Vault deposits underlying tokens into yield bearing protocol (a.k.a. Bob).
        vault.manualTransfer(dai, bob, underlyingToDeposit);

        vm.prank(bob);
        // 2) Yield bearing protocol transfers wrapped tokens to vault.
        IERC20(address(wDaiInitialized)).transfer(address(vault), wrappedToMint);
    }

    function _simulateUnwrapOperation(uint256 underlyingToWithdraw, uint256 wrappedToBurn) private {
        // 1) Vault burns wrapped tokens (simulated by depositing to Bob, the yield-bearing Protocol).
        vault.manualTransfer(IERC20(address(wDaiInitialized)), bob, wrappedToBurn);

        vm.prank(bob);
        // 2) Yield bearing protocol transfers underlying tokens to vault.
        dai.transfer(address(vault), underlyingToWithdraw);
    }

    function _exactInWrapUnwrapPath(
        uint256 exactAmountIn,
        uint256 minAmountOut,
        IERC20 tokenFrom,
        IERC20 tokenTo,
        IERC20 wrappedToken
    ) private pure returns (IBatchRouter.SwapPathExactAmountIn[] memory paths) {
        IBatchRouter.SwapPathStep[] memory steps = new IBatchRouter.SwapPathStep[](1);
        paths = new IBatchRouter.SwapPathExactAmountIn[](1);

        steps[0] = IBatchRouter.SwapPathStep({ pool: address(wrappedToken), tokenOut: tokenTo, isBuffer: true });

        paths[0] = IBatchRouter.SwapPathExactAmountIn({
            tokenIn: tokenFrom,
            steps: steps,
            exactAmountIn: exactAmountIn,
            minAmountOut: minAmountOut
        });
    }
}
