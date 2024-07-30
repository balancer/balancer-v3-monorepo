// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

abstract contract ERC4626WrapperBaseTest is Test {
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

    function setUp() public virtual {
        setUpForkTestVariables();
        vm.label(address(wrapper), "wrapper");

        vm.createSelectFork({ blockNumber: blockNumber, urlOrAlias: network });

        underlyingToken = IERC20(wrapper.asset());
        vm.label(address(underlyingToken), "underlying");

        underlyingToWrappedFactor = 10 ** (wrapper.decimals() - IERC20Metadata(address(underlyingToken)).decimals());

        _initializeUserWallet();
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
        // This can cause the user to don't have enough tokens to deposit.
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

    function _initializeUserWallet() private {
        (user, ) = makeAddrAndKey("User");
        vm.label(user, "User");

        uint256 initialDeposit = amountToDonate / 2;

        vm.prank(underlyingDonor);
        underlyingToken.safeTransfer(user, amountToDonate);

        vm.startPrank(user);
        underlyingToken.forceApprove(address(wrapper), initialDeposit);
        userInitialShares = wrapper.deposit(initialDeposit, user);
        vm.stopPrank();

        userInitialUnderlying = underlyingToken.balanceOf(user);
    }
}
