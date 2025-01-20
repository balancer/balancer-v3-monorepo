// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

import { IProtocolFeeSweeper } from "@balancer-labs/v3-interfaces/contracts/standalone-utils/IProtocolFeeSweeper.sol";
import { IProtocolFeeBurner } from "@balancer-labs/v3-interfaces/contracts/standalone-utils/IProtocolFeeBurner.sol";
import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import { IProtocolFeeController } from "@balancer-labs/v3-interfaces/contracts/vault/IProtocolFeeController.sol";

import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";

import { ProtocolFeeBurnerMock } from "../../contracts/test/ProtocolFeeBurnerMock.sol";
import { ProtocolFeeSweeper } from "../../contracts/ProtocolFeeSweeper.sol";

contract ProtocolFeeSweeperTest is BaseVaultTest {
    using CastingHelpers for address[];
    using Address for address payable;
    using ArrayHelpers for *;

    IProtocolFeeSweeper internal feeSweeper;

    IProtocolFeeBurner internal feeBurner;

    address internal feeRecipient;

    function setUp() public override {
        BaseVaultTest.setUp();

        (feeRecipient, ) = makeAddrAndKey("feeRecipient");

        feeSweeper = new ProtocolFeeSweeper(vault, feeRecipient);
        feeBurner = new ProtocolFeeBurnerMock();

        authorizer.grantRole(
            IAuthentication(address(feeSweeper)).getActionId(IProtocolFeeSweeper.setFeeRecipient.selector),
            admin
        );
        authorizer.grantRole(
            IAuthentication(address(feeSweeper)).getActionId(IProtocolFeeSweeper.setProtocolFeeBurner.selector),
            admin
        );
        authorizer.grantRole(
            IAuthentication(address(feeSweeper)).getActionId(IProtocolFeeSweeper.setTargetToken.selector),
            admin
        );
        authorizer.grantRole(
            IAuthentication(address(feeSweeper)).getActionId(IProtocolFeeSweeper.sweepProtocolFeesForToken.selector),
            admin
        );
        authorizer.grantRole(
            IAuthentication(address(feeSweeper)).getActionId(IProtocolFeeSweeper.sweepProtocolFees.selector),
            admin
        );

        // Allow the fee sweeper to withdraw protocol fees.
        authorizer.grantRole(
            IAuthentication(address(feeController)).getActionId(IProtocolFeeController.withdrawProtocolFees.selector),
            address(feeSweeper)
        );
        authorizer.grantRole(
            IAuthentication(address(feeController)).getActionId(
                IProtocolFeeController.withdrawProtocolFeesForToken.selector
            ),
            address(feeSweeper)
        );
    }

    function testGetProtocolFeeController() public view {
        assertEq(address(feeSweeper.getProtocolFeeController()), address(feeController), "Fee controller mismatch");
    }

    function testGetTargetToken() public view {
        assertEq(address(feeSweeper.getTargetToken()), ZERO_ADDRESS, "Initial target token non-zero");
    }

    function testGetFeeRecipient() public view {
        assertEq(feeSweeper.getFeeRecipient(), feeRecipient, "Wrong fee recipient");
    }

    function testGetProtocolFeeBurner() public view {
        assertEq(address(feeSweeper.getProtocolFeeBurner()), ZERO_ADDRESS, "Initial fee burner non-zero");
    }

    function testSetFeeRecipientNoPermission() public {
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        feeSweeper.setFeeRecipient(admin);
    }

    function testSetInvalidFeeRecipient() public {
        vm.expectRevert(IProtocolFeeSweeper.InvalidFeeRecipient.selector);

        vm.prank(admin);
        feeSweeper.setFeeRecipient(ZERO_ADDRESS);
    }

    function testSetFeeRecipient() public {
        vm.prank(admin);
        feeSweeper.setFeeRecipient(alice);

        assertEq(feeSweeper.getFeeRecipient(), alice, "Wrong fee recipient");
    }

    function testSetFeeRecipientEmitsEvent() public {
        vm.expectEmit();
        emit IProtocolFeeSweeper.FeeRecipientSet(alice);

        vm.prank(admin);
        feeSweeper.setFeeRecipient(alice);
    }

    function testSetFeeBurnerNoPermission() public {
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        feeSweeper.setProtocolFeeBurner(feeBurner);
    }

    function testSetFeeBurner() public {
        vm.prank(admin);
        feeSweeper.setProtocolFeeBurner(feeBurner);

        assertEq(address(feeSweeper.getProtocolFeeBurner()), address(feeBurner), "Wrong fee burner");
    }

    function testSetFeeBurnerEmitsEvent() public {
        vm.expectEmit();
        emit IProtocolFeeSweeper.ProtocolFeeBurnerSet(address(feeBurner));

        vm.prank(admin);
        feeSweeper.setProtocolFeeBurner(feeBurner);
    }

    function testSetTargetTokenNoPermission() public {
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        feeSweeper.setTargetToken(usdc);
    }

    function testSetTargetToken() public {
        vm.prank(admin);
        feeSweeper.setTargetToken(usdc);

        assertEq(address(feeSweeper.getTargetToken()), address(usdc), "Wrong target token");
    }

    function testSetTargetTokenEmitsEvent() public {
        vm.expectEmit();
        emit IProtocolFeeSweeper.TargetTokenSet(usdc);

        vm.prank(admin);
        feeSweeper.setTargetToken(usdc);
    }

    function testNoEth() public {
        vm.expectRevert(ProtocolFeeSweeper.CannotReceiveEth.selector);
        vm.prank(alice);
        payable(address(feeSweeper)).sendValue(1 ether);
    }

    function testFallbackNoEth() public {
        vm.expectRevert(ProtocolFeeSweeper.CannotReceiveEth.selector);
        (bool success, ) = address(feeSweeper).call{ value: 1 ether }(abi.encodeWithSignature("fish()"));
        assertTrue(success);
    }

    function testNoFallback() public {
        vm.expectRevert("Not implemented");
        (bool success, ) = address(feeSweeper).call(abi.encodeWithSignature("fish()"));
        assertTrue(success);
    }

    function testRecoverNoPermission() public {
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        feeSweeper.recoverProtocolFees(new IERC20[](0));
    }

    function testRecoverProtocolFees() public {
        IERC20[] memory feeTokens = [address(dai), address(usdc)].toMemoryArray().asIERC20();

        address feeSweeperAddress = address(feeSweeper);

        // Send some to the fee Sweeper
        vm.startPrank(alice);
        dai.transfer(feeSweeperAddress, DEFAULT_AMOUNT);
        usdc.transfer(feeSweeperAddress, DEFAULT_AMOUNT);
        vm.stopPrank();

        assertEq(dai.balanceOf(feeSweeperAddress), DEFAULT_AMOUNT, "DAI not transferred to sweeper");
        assertEq(usdc.balanceOf(feeSweeperAddress), DEFAULT_AMOUNT, "USDC not transferred to sweeper");

        vm.prank(feeRecipient);
        feeSweeper.recoverProtocolFees(feeTokens);

        assertEq(dai.balanceOf(feeRecipient), DEFAULT_AMOUNT, "DAI not recovered");
        assertEq(usdc.balanceOf(feeRecipient), DEFAULT_AMOUNT, "USDC not recovered");

        assertEq(dai.balanceOf(feeSweeperAddress), 0, "DAI not transferred from sweeper");
        assertEq(usdc.balanceOf(feeSweeperAddress), 0, "USDC not transferred from sweeper");
    }

    function testSweepProtocolFeesFallback() public {
        // Put some fees in the Vault.
        vault.manualSetAggregateSwapFeeAmount(pool, dai, DEFAULT_AMOUNT);
        vault.manualSetAggregateYieldFeeAmount(pool, usdc, DEFAULT_AMOUNT);

        // Collect them (i.e., send from the Vault to the controller).
        feeController.collectAggregateFees(pool);

        // Initial state has balances in the fee controller and none in the sweeper.
        assertEq(dai.balanceOf(address(feeController)), DEFAULT_AMOUNT, "DAI not collected");
        assertEq(usdc.balanceOf(address(feeController)), DEFAULT_AMOUNT, "USDC not collected");
        assertEq(dai.balanceOf(address(feeSweeper)), 0, "Initial sweeper DAI balance non-zero");
        assertEq(usdc.balanceOf(address(feeSweeper)), 0, "Initial sweeper USDC balance non-zero");
        assertEq(dai.balanceOf(address(feeRecipient)), 0, "Initial recipient DAI balance non-zero");
        assertEq(usdc.balanceOf(address(feeRecipient)), 0, "Initial recipient USDC balance non-zero");

        vm.expectEmit();
        emit IProtocolFeeSweeper.ProtocolFeeSwept(pool, dai, DEFAULT_AMOUNT, feeRecipient);
        vm.expectEmit();
        emit IProtocolFeeSweeper.ProtocolFeeSwept(pool, usdc, DEFAULT_AMOUNT, feeRecipient);

        vm.prank(admin);
        feeSweeper.sweepProtocolFees(pool);

        assertEq(dai.balanceOf(address(feeController)), 0, "DAI not withdrawn");
        assertEq(usdc.balanceOf(address(feeController)), 0, "USDC not withdrawn");
        assertEq(dai.balanceOf(address(feeSweeper)), 0, "Final sweeper DAI balance non-zero");
        assertEq(usdc.balanceOf(address(feeSweeper)), 0, "Final sweeper USDC balance non-zero");
        assertEq(dai.balanceOf(address(feeRecipient)), DEFAULT_AMOUNT, "DAI not forwarded");
        assertEq(usdc.balanceOf(address(feeRecipient)), DEFAULT_AMOUNT, "USDC not forwarded");
    }

    function testSweepProtocolFeesFallbackForToken() public {
        // Put some fees in the Vault.
        vault.manualSetAggregateSwapFeeAmount(pool, dai, DEFAULT_AMOUNT);
        vault.manualSetAggregateYieldFeeAmount(pool, usdc, DEFAULT_AMOUNT);

        // Collect them (i.e., send from the Vault to the controller).
        feeController.collectAggregateFees(pool);

        // Initial state has balances in the fee controller and none in the sweeper.
        assertEq(dai.balanceOf(address(feeController)), DEFAULT_AMOUNT, "DAI not collected");
        assertEq(usdc.balanceOf(address(feeController)), DEFAULT_AMOUNT, "USDC not collected");
        assertEq(dai.balanceOf(address(feeSweeper)), 0, "Initial sweeper DAI balance non-zero");
        assertEq(usdc.balanceOf(address(feeSweeper)), 0, "Initial sweeper USDC balance non-zero");
        assertEq(dai.balanceOf(address(feeRecipient)), 0, "Initial recipient DAI balance non-zero");
        assertEq(usdc.balanceOf(address(feeRecipient)), 0, "Initial recipient USDC balance non-zero");

        vm.startPrank(admin);
        vm.expectEmit();
        emit IProtocolFeeSweeper.ProtocolFeeSwept(pool, dai, DEFAULT_AMOUNT, feeRecipient);

        feeSweeper.sweepProtocolFeesForToken(pool, dai);

        vm.expectEmit();
        emit IProtocolFeeSweeper.ProtocolFeeSwept(pool, usdc, DEFAULT_AMOUNT, feeRecipient);

        feeSweeper.sweepProtocolFeesForToken(pool, usdc);
        vm.stopPrank();

        assertEq(dai.balanceOf(address(feeController)), 0, "DAI not withdrawn");
        assertEq(usdc.balanceOf(address(feeController)), 0, "USDC not withdrawn");
        assertEq(dai.balanceOf(address(feeSweeper)), 0, "Final sweeper DAI balance non-zero");
        assertEq(usdc.balanceOf(address(feeSweeper)), 0, "Final sweeper USDC balance non-zero");
        assertEq(dai.balanceOf(address(feeRecipient)), DEFAULT_AMOUNT, "DAI not forwarded");
        assertEq(usdc.balanceOf(address(feeRecipient)), DEFAULT_AMOUNT, "USDC not forwarded");
    }

    function testSweepProtocolFeesBurner() public {
        // Set up the sweeper to be able to burn.
        vm.startPrank(admin);
        feeSweeper.setProtocolFeeBurner(feeBurner);
        feeSweeper.setTargetToken(usdc);
        vm.stopPrank();

        // Put some fees in the Vault.
        vault.manualSetAggregateSwapFeeAmount(pool, dai, DEFAULT_AMOUNT);
        vault.manualSetAggregateYieldFeeAmount(pool, usdc, DEFAULT_AMOUNT);

        // Collect them (i.e., send from the Vault to the controller).
        feeController.collectAggregateFees(pool);

        // DAI is NOT the target token, so it should call burn.
        vm.expectEmit();
        emit IProtocolFeeBurner.ProtocolFeeBurned(pool, dai, DEFAULT_AMOUNT, usdc, DEFAULT_AMOUNT, feeRecipient);

        // USDC is the target token, so it should be transferred directly.
        vm.expectEmit();
        emit IProtocolFeeSweeper.ProtocolFeeSwept(pool, usdc, DEFAULT_AMOUNT, feeRecipient);

        vm.prank(admin);
        feeSweeper.sweepProtocolFees(pool);

        assertEq(dai.balanceOf(address(feeController)), 0, "DAI not withdrawn");
        assertEq(usdc.balanceOf(address(feeController)), 0, "USDC not withdrawn");
        assertEq(dai.balanceOf(address(feeSweeper)), 0, "Final sweeper DAI balance non-zero");
        assertEq(usdc.balanceOf(address(feeSweeper)), 0, "Final sweeper USDC balance non-zero");
        // DAI should have been converted to USDC, so we should have twice the DEFAULT_AMOUNT of it.
        assertEq(dai.balanceOf(address(feeRecipient)), 0, "DAI not burned");
        assertEq(usdc.balanceOf(address(feeRecipient)), DEFAULT_AMOUNT * 2, "USDC not forwarded");
    }

    function testSweepProtocolFeesForTokenBurner() public {
        // Set up the sweeper to be able to burn.
        vm.startPrank(admin);
        feeSweeper.setProtocolFeeBurner(feeBurner);
        feeSweeper.setTargetToken(usdc);
        vm.stopPrank();

        // Put some fees in the Vault.
        vault.manualSetAggregateSwapFeeAmount(pool, dai, DEFAULT_AMOUNT);
        vault.manualSetAggregateYieldFeeAmount(pool, usdc, DEFAULT_AMOUNT);

        // Collect them (i.e., send from the Vault to the controller).
        feeController.collectAggregateFees(pool);

        // DAI is NOT the target token, so it should call burn.
        vm.expectEmit();
        emit IProtocolFeeBurner.ProtocolFeeBurned(pool, dai, DEFAULT_AMOUNT, usdc, DEFAULT_AMOUNT, feeRecipient);

        vm.startPrank(admin);
        feeSweeper.sweepProtocolFeesForToken(pool, IERC20(address(dai)));

        // USDC is the target token, so it should be transferred directly.
        vm.expectEmit();
        emit IProtocolFeeSweeper.ProtocolFeeSwept(pool, usdc, DEFAULT_AMOUNT, feeRecipient);

        feeSweeper.sweepProtocolFeesForToken(pool, IERC20(address(usdc)));
        vm.stopPrank();

        assertEq(dai.balanceOf(address(feeController)), 0, "DAI not withdrawn");
        assertEq(usdc.balanceOf(address(feeController)), 0, "USDC not withdrawn");
        assertEq(dai.balanceOf(address(feeSweeper)), 0, "Final sweeper DAI balance non-zero");
        assertEq(usdc.balanceOf(address(feeSweeper)), 0, "Final sweeper USDC balance non-zero");
        // DAI should have been converted to USDC, so we should have twice the DEFAULT_AMOUNT of it.
        assertEq(dai.balanceOf(address(feeRecipient)), 0, "DAI not burned");
        assertEq(usdc.balanceOf(address(feeRecipient)), DEFAULT_AMOUNT * 2, "USDC not forwarded");
    }
}
