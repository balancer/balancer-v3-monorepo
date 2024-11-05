// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { BaseVaultTest } from "../utils/BaseVaultTest.sol";

abstract contract ERC4626WrapperBaseTest is BaseVaultTest {
    using FixedPoint for uint256;
    using SafeERC20 for IERC20;

    // Variables to be defined by setUpForkTestVariables().
    string internal network;
    uint256 internal blockNumber;
    IERC4626 internal wrapper;
    address internal underlyingDonor;
    uint256 internal amountToDonate;

    IERC20 internal underlyingToken;
    uint256 internal underlyingToWrappedFactor;

    address internal user;
    uint256 internal userInitialUnderlying;
    uint256 internal userInitialShares;

    uint256 internal constant MIN_DEPOSIT = 100;
    // Tolerance of 1 wei difference between convert/preview and actual operation.
    uint256 internal constant TOLERANCE = 1;

    function setUp() public virtual override {
        setUpForkTestVariables();
        vm.label(address(wrapper), "wrapper");

        vm.createSelectFork({ blockNumber: blockNumber, urlOrAlias: network });

        underlyingToken = IERC20(wrapper.asset());
        vm.label(address(underlyingToken), "underlying");

        underlyingToWrappedFactor = 10 ** (wrapper.decimals() - IERC20Metadata(address(underlyingToken)).decimals());

        (user, ) = makeAddrAndKey("User");
        vm.label(user, "User");
        _initializeWallet(user);

        userInitialUnderlying = underlyingToken.balanceOf(user);
        userInitialShares = wrapper.balanceOf(user);

        super.setUp();

        _initializeWallet(lp);
        _setupAllowance(lp);
    }

    /**
     * @notice Defines network, blockNumber, wrapper, underlyingDonor and amountToDonate.
     * @dev Make sure the underlyingDonor has at least amountToDonate underlying tokens.
     */
    function setUpForkTestVariables() internal virtual;

    function testPreConditions() public view {
        assertEq(userInitialUnderlying, amountToDonate / 2, "User balance of underlying is wrong.");
        assertEq(userInitialShares, wrapper.balanceOf(user), "User balance of shares is wrong.");
    }

    function testDeposit__Fork__Fuzz(uint256 amountToDeposit) public {
        amountToDeposit = bound(amountToDeposit, MIN_DEPOSIT, userInitialUnderlying);

        uint256 convertedShares = wrapper.convertToShares(amountToDeposit);
        uint256 previewedShares = wrapper.previewDeposit(amountToDeposit);

        uint256 balanceUnderlyingBefore = underlyingToken.balanceOf(user);
        uint256 balanceSharesBefore = wrapper.balanceOf(user);

        vm.startPrank(user);
        underlyingToken.forceApprove(address(wrapper), amountToDeposit);
        uint256 mintedShares = wrapper.deposit(amountToDeposit, user);
        vm.stopPrank();

        uint256 balanceUnderlyingAfter = underlyingToken.balanceOf(user);
        uint256 balanceSharesAfter = wrapper.balanceOf(user);

        assertEq(balanceUnderlyingAfter, balanceUnderlyingBefore - amountToDeposit, "Deposit is not EXACT_IN");
        assertEq(balanceSharesAfter, balanceSharesBefore + mintedShares, "Deposit minted shares do not match");
        assertApproxEqAbs(
            convertedShares,
            mintedShares,
            TOLERANCE,
            "Convert and actual operation difference is higher than tolerance"
        );
        assertApproxEqAbs(
            previewedShares,
            mintedShares,
            TOLERANCE,
            "Preview and actual operation difference is higher than tolerance"
        );
    }

    function testMint__Fork__Fuzz(uint256 amountToMint) public {
        // When user mints, a round up may occur and add some wei in the amount of underlying required to deposit.
        // This can cause the user to not have enough tokens to deposit.
        // So, the maximum amountToMint must be the initialShares (which is exactly the initialUnderlying, converted to
        // shares) less a tolerance.
        amountToMint = bound(
            amountToMint,
            MIN_DEPOSIT * underlyingToWrappedFactor,
            userInitialShares - (TOLERANCE * underlyingToWrappedFactor)
        );

        uint256 convertedUnderlying = wrapper.convertToAssets(amountToMint);
        uint256 previewedUnderlying = wrapper.previewMint(amountToMint);

        uint256 balanceUnderlyingBefore = underlyingToken.balanceOf(user);
        uint256 balanceSharesBefore = wrapper.balanceOf(user);

        vm.startPrank(user);
        underlyingToken.forceApprove(address(wrapper), previewedUnderlying);
        uint256 depositedUnderlying = wrapper.mint(amountToMint, user);
        vm.stopPrank();

        uint256 balanceUnderlyingAfter = underlyingToken.balanceOf(user);
        uint256 balanceSharesAfter = wrapper.balanceOf(user);

        assertEq(balanceUnderlyingAfter, balanceUnderlyingBefore - depositedUnderlying, "Mint is not EXACT_OUT");
        assertEq(balanceSharesAfter, balanceSharesBefore + amountToMint, "Mint shares do not match");
        assertApproxEqAbs(
            convertedUnderlying,
            depositedUnderlying,
            TOLERANCE,
            "Convert and actual operation difference is higher than tolerance"
        );
        assertApproxEqAbs(
            previewedUnderlying,
            depositedUnderlying,
            TOLERANCE,
            "Preview and actual operation difference is higher than tolerance"
        );
    }

    function testWithdraw__Fork__Fuzz(uint256 amountToWithdraw) public {
        // When user deposited to underlying, a round down may occur and remove some wei. So, makes sure
        // amountToWithdraw does not pass the amount deposited - a wei tolerance.
        amountToWithdraw = bound(amountToWithdraw, MIN_DEPOSIT, userInitialUnderlying - TOLERANCE);

        uint256 convertedShares = wrapper.convertToShares(amountToWithdraw);
        uint256 previewedShares = wrapper.previewWithdraw(amountToWithdraw);

        uint256 balanceUnderlyingBefore = underlyingToken.balanceOf(user);
        uint256 balanceSharesBefore = wrapper.balanceOf(user);

        vm.startPrank(user);
        uint256 burnedShares = wrapper.withdraw(amountToWithdraw, user, user);
        vm.stopPrank();

        uint256 balanceUnderlyingAfter = underlyingToken.balanceOf(user);
        uint256 balanceSharesAfter = wrapper.balanceOf(user);

        assertEq(balanceUnderlyingAfter, balanceUnderlyingBefore + amountToWithdraw, "Withdraw is not EXACT_OUT");
        assertEq(balanceSharesAfter, balanceSharesBefore - burnedShares, "Withdraw burned shares do not match");
        assertApproxEqAbs(
            convertedShares,
            burnedShares,
            TOLERANCE,
            "Convert and actual operation difference is higher than tolerance"
        );
        assertApproxEqAbs(
            previewedShares,
            burnedShares,
            TOLERANCE,
            "Preview and actual operation difference is higher than tolerance"
        );
    }

    function testRedeem__Fork__Fuzz(uint256 amountToRedeem) public {
        // When user deposited to underlying, a round down may occur and remove some wei. So, makes sure
        // amountToWithdraw does not pass the amount deposited - a wei tolerance.
        amountToRedeem = bound(amountToRedeem, MIN_DEPOSIT * underlyingToWrappedFactor, userInitialShares - TOLERANCE);

        uint256 convertedAssets = wrapper.convertToAssets(amountToRedeem);
        uint256 previewedAssets = wrapper.previewRedeem(amountToRedeem);

        uint256 balanceUnderlyingBefore = underlyingToken.balanceOf(user);
        uint256 balanceSharesBefore = wrapper.balanceOf(user);

        vm.startPrank(user);
        uint256 withdrawnAssets = wrapper.redeem(amountToRedeem, user, user);
        vm.stopPrank();

        uint256 balanceUnderlyingAfter = underlyingToken.balanceOf(user);
        uint256 balanceSharesAfter = wrapper.balanceOf(user);

        assertEq(balanceUnderlyingAfter, balanceUnderlyingBefore + withdrawnAssets, "Redeem is not EXACT_IN");
        assertEq(balanceSharesAfter, balanceSharesBefore - amountToRedeem, "Redeem burned shares do not match");
        assertApproxEqAbs(
            convertedAssets,
            withdrawnAssets,
            TOLERANCE,
            "Convert and actual operation difference is higher than tolerance"
        );
        assertApproxEqAbs(
            previewedAssets,
            withdrawnAssets,
            TOLERANCE,
            "Preview and actual operation difference is higher than tolerance"
        );
    }

    function testAddLiquidityToBuffer__Fork__Fuzz(
        uint256 underlyingToInitialize,
        uint256 wrappedToInitialize,
        uint256 sharesToIssue
    ) public {
        underlyingToInitialize = bound(underlyingToInitialize, 1e6, underlyingToken.balanceOf(lp) / 10);
        wrappedToInitialize = bound(wrappedToInitialize, 1e6, wrapper.balanceOf(lp) / 10);
        sharesToIssue = bound(sharesToIssue, 1e6, underlyingToken.balanceOf(lp) / 2);

        vm.prank(lp);
        router.initializeBuffer(wrapper, underlyingToInitialize, wrappedToInitialize);
        // Since the buffer burns part of the shares, we measure the total shares in the vault instead of using the
        // value returned by initializeBuffer;
        uint256 totalShares = vault.getBufferTotalShares(wrapper);

        vm.prank(lp);
        (uint256 underlyingDeposited, uint256 wrappedDeposited) = router.addLiquidityToBuffer(wrapper, sharesToIssue);

        // Measures if the underlying and wrapped deposited on addLiquidityToBuffer are worth the same number of shares
        // than in initialized liquidity (or less).
        assertGe(
            underlyingDeposited,
            (sharesToIssue * underlyingToInitialize) / totalShares,
            "User spent less underlying tokens than it should"
        );
        assertGe(
            wrappedDeposited,
            (sharesToIssue * wrappedToInitialize) / totalShares,
            "User spent less wrapped tokens than it should"
        );
    }

    function testRemoveLiquidityFromBuffer__Fork__Fuzz(
        uint256 underlyingToInitialize,
        uint256 wrappedToInitialize,
        uint256 sharesToRemove
    ) public {
        underlyingToInitialize = bound(underlyingToInitialize, 1e6, underlyingToken.balanceOf(lp) / 10);
        wrappedToInitialize = bound(wrappedToInitialize, 1e6, wrapper.balanceOf(lp) / 10);

        vm.prank(lp);
        uint256 lpShares = router.initializeBuffer(wrapper, underlyingToInitialize, wrappedToInitialize);
        // Since the buffer burns part of the shares, we measure the total shares in the vault instead of using the
        // value returned by initializeBuffer;
        uint256 totalShares = vault.getBufferTotalShares(wrapper);

        sharesToRemove = bound(sharesToRemove, 0, lpShares);

        vm.prank(lp);
        (uint256 underlyingRemoved, uint256 wrappedRemoved) = vault.removeLiquidityFromBuffer(wrapper, sharesToRemove);

        // Measures if the underlying and wrapped received from `removeLiquidityFromBuffer` are worth the same number
        // of shares than in initialized liquidity (or less).
        assertLe(
            underlyingRemoved,
            (sharesToRemove * underlyingToInitialize) / totalShares,
            "User received more underlying tokens than it should"
        );
        assertLe(
            wrappedRemoved,
            (sharesToRemove * wrappedToInitialize) / totalShares,
            "User received more wrapped tokens than it should"
        );
    }

    function _initializeWallet(address receiver) private {
        uint256 initialDeposit = amountToDonate / 2;

        vm.prank(underlyingDonor);
        underlyingToken.safeTransfer(receiver, amountToDonate);

        vm.startPrank(receiver);
        underlyingToken.forceApprove(address(wrapper), initialDeposit);
        wrapper.deposit(initialDeposit, receiver);
        vm.stopPrank();
    }

    function _setupAllowance(address sender) private {
        vm.startPrank(sender);
        underlyingToken.forceApprove(address(permit2), type(uint256).max);
        wrapper.approve(address(permit2), type(uint256).max);

        permit2.approve(address(underlyingToken), address(router), type(uint160).max, type(uint48).max);
        permit2.approve(address(wrapper), address(router), type(uint160).max, type(uint48).max);
        vm.stopPrank();
    }
}
