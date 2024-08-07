// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

import { EVMCallModeHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/EVMCallModeHelpers.sol";

import { ERC20MultiTokenMock } from "../../../contracts/test/ERC20MultiTokenMock.sol";
import { ERC20MultiToken } from "../../../contracts/token/ERC20MultiToken.sol";
import { BalancerPoolToken } from "../../../contracts/BalancerPoolToken.sol";

contract ERC20MultiTokenTest is Test, IERC20Errors, ERC20MultiToken {
    address internal constant ZERO_ADDRESS = address(0x00);
    address internal constant POOL = address(0x01);
    address internal constant OWNER = address(0x02);
    address internal constant OWNER2 = address(0x03);
    address internal constant SPENDER = address(0x04);
    uint256 internal constant DEFAULT_AMOUNT = 100;
    uint256 internal constant MINIMUM_TOTAL_SUPPLY = 1e6;

    ERC20MultiTokenMock token;

    function setUp() public {
        token = new ERC20MultiTokenMock();
    }

    // #region Init values
    function testBalanceOfWithZeroValue() public view {
        assertEq(token.balanceOf(POOL, OWNER), 0, "Unexpected balance");
    }

    function testTotalSupplyWithZeroValue() public view {
        assertEq(token.totalSupply(POOL), 0, "Unexpected total supply");
    }

    // #endregion

    // #region Approve & Allowance & SpendAllowance
    function testAllowanceForTokenContract() public view {
        assertEq(token.allowance(POOL, OWNER, address(token)), type(uint256).max, "Unexpected allowance");
    }

    function testAllowanceForNotTokenContractWithZeroValue() public view {
        assertEq(token.allowance(POOL, OWNER, SPENDER), 0, "Unexpected allowance");
    }

    function testApprove() public {
        vm.expectEmit();
        emit ERC20MultiToken.Approval(POOL, OWNER, SPENDER, DEFAULT_AMOUNT);

        _approveWithBPTEmitApprovalMock(POOL, OWNER, SPENDER, DEFAULT_AMOUNT);

        assertEq(token.allowance(POOL, OWNER, SPENDER), DEFAULT_AMOUNT, "Unexpected allowance");
    }

    function testApproveRevertIfOwnerIsZero() public {
        vm.expectRevert(abi.encodeWithSelector(ERC20InvalidApprover.selector, address(0x00)));
        token.manualApprove(POOL, ZERO_ADDRESS, SPENDER, DEFAULT_AMOUNT);
    }

    function testApproveRevertIfSpenderIsZero() public {
        vm.expectRevert(abi.encodeWithSelector(ERC20InvalidSpender.selector, ZERO_ADDRESS));
        token.manualApprove(POOL, OWNER, ZERO_ADDRESS, DEFAULT_AMOUNT);
    }

    function testSpendAllowance() public {
        uint256 initialAllowance = DEFAULT_AMOUNT;
        uint256 remainingAllowance = 1;
        uint256 spendAmount = initialAllowance - remainingAllowance;

        _approveWithBPTEmitApprovalMock(POOL, OWNER, SPENDER, initialAllowance);

        vm.expectEmit();
        emit ERC20MultiToken.Approval(POOL, OWNER, SPENDER, remainingAllowance);
        vm.mockCall(
            POOL,
            abi.encodeWithSelector(BalancerPoolToken.emitApproval.selector, OWNER, SPENDER, remainingAllowance),
            new bytes(0)
        );
        token.manualSpendAllowance(POOL, OWNER, SPENDER, spendAmount);

        assertEq(token.allowance(POOL, OWNER, SPENDER), remainingAllowance, "Unexpected allowance");
    }

    function testSpendAllowanceWhenAllowanceIsMax() public {
        _approveWithBPTEmitApprovalMock(POOL, OWNER, SPENDER, type(uint256).max);
        assertEq(token.allowance(POOL, OWNER, SPENDER), type(uint256).max, "Unexpected allowance (emit approval)");

        token.manualSpendAllowance(POOL, OWNER, SPENDER, 1);
        assertEq(token.allowance(POOL, OWNER, SPENDER), type(uint256).max, "Unexpected allowance (manual spend)");
    }

    function testSpendAllowanceWhenOwnerIsSender() public {
        assertEq(token.allowance(POOL, OWNER, OWNER), type(uint256).max, "Unexpected allowance (no manual spend)");

        token.manualSpendAllowance(POOL, OWNER, OWNER, 1);
        assertEq(token.allowance(POOL, OWNER, OWNER), type(uint256).max, "Unexpected allowance (manual spend)");
    }

    function testSpendAllowanceRevertIfInsufficientAllowance() public {
        uint256 initialAllowance = DEFAULT_AMOUNT;
        uint256 spendAmount = initialAllowance + 1;

        _approveWithBPTEmitApprovalMock(POOL, OWNER, SPENDER, initialAllowance);

        vm.expectRevert(
            abi.encodeWithSelector(ERC20InsufficientAllowance.selector, SPENDER, initialAllowance, spendAmount)
        );
        token.manualSpendAllowance(POOL, OWNER, SPENDER, spendAmount);
    }

    // #endregion

    // #region QueryModeBalanceIncrease
    function testQueryModeBalanceIncrease() public {
        // we prank here msg.sender to OWNER and tx.origin to address(0x00) to simulate a static call
        vm.prank(OWNER, address(0x00));
        token.manualQueryModeBalanceIncrease(POOL, OWNER, DEFAULT_AMOUNT);
        assertEq(token.balanceOf(POOL, OWNER), DEFAULT_AMOUNT, "Unexpected balance");
    }

    function testQueryModeBalanceIncreaseRevertIfCallIsNotStatic() public {
        // we prank here msg.sender and tx.origin to OWNER to simulate a non-static call
        vm.prank(OWNER, OWNER);
        vm.expectRevert(EVMCallModeHelpers.NotStaticCall.selector);
        token.manualQueryModeBalanceIncrease(POOL, OWNER, DEFAULT_AMOUNT);
    }

    // #endregion

    // #region Mint
    function testMint() public {
        vm.expectEmit();
        emit ERC20MultiToken.Transfer(POOL, ZERO_ADDRESS, OWNER, MINIMUM_TOTAL_SUPPLY);
        _mintWithBPTEmitTransferMock(POOL, OWNER, MINIMUM_TOTAL_SUPPLY);

        assertEq(token.balanceOf(POOL, OWNER), MINIMUM_TOTAL_SUPPLY, "Unexpected balance");
        assertEq(token.totalSupply(POOL), MINIMUM_TOTAL_SUPPLY, "Unexpected total supply");
    }

    function testDoubleMintToCheckTotalSupply() public {
        uint256 firstMintAmount = MINIMUM_TOTAL_SUPPLY;
        uint256 secondMintAmount = DEFAULT_AMOUNT;

        _mintWithBPTEmitTransferMock(POOL, OWNER, firstMintAmount);

        assertEq(token.balanceOf(POOL, OWNER), firstMintAmount, "Unexpected balance (first)");
        assertEq(token.totalSupply(POOL), firstMintAmount, "Unexpected total supply (first)");

        _mintWithBPTEmitTransferMock(POOL, OWNER2, secondMintAmount);
        assertEq(token.balanceOf(POOL, OWNER2), secondMintAmount, "Unexpected balance (second)");
        assertEq(token.totalSupply(POOL), firstMintAmount + secondMintAmount, "Unexpected total supply (second)");
    }

    function testMintRevertIfToIsZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(ERC20InvalidReceiver.selector, ZERO_ADDRESS));
        token.manualMint(POOL, ZERO_ADDRESS, DEFAULT_AMOUNT);
    }

    function testMintRevertIfTotalSupplyIsLessThanMinimum() public {
        vm.expectRevert(
            abi.encodeWithSelector(TotalSupplyTooLow.selector, MINIMUM_TOTAL_SUPPLY - 1, MINIMUM_TOTAL_SUPPLY)
        );
        token.manualMint(POOL, OWNER, MINIMUM_TOTAL_SUPPLY - 1);
    }

    // #endregion

    // #region MintMinimumSupplyReserve
    function testMintMinimumSupplyReserve() public {
        vm.expectEmit();
        emit ERC20MultiToken.Transfer(POOL, ZERO_ADDRESS, ZERO_ADDRESS, MINIMUM_TOTAL_SUPPLY);
        vm.mockCall(
            POOL,
            abi.encodeWithSelector(
                BalancerPoolToken.emitTransfer.selector,
                ZERO_ADDRESS,
                ZERO_ADDRESS,
                MINIMUM_TOTAL_SUPPLY
            ),
            new bytes(0)
        );
        token.manualMintMinimumSupplyReserve(POOL);

        assertEq(token.balanceOf(POOL, ZERO_ADDRESS), MINIMUM_TOTAL_SUPPLY, "Unexpected balance");
        assertEq(token.totalSupply(POOL), MINIMUM_TOTAL_SUPPLY, "Unexpected total supply");
    }

    // #endregion

    // #region Burn
    function testBurn() public {
        uint256 burnAmount = 1;
        uint256 balanceAfterBurn = MINIMUM_TOTAL_SUPPLY;
        uint256 mintAmount = balanceAfterBurn + burnAmount;

        _mintWithBPTEmitTransferMock(POOL, OWNER, mintAmount);

        vm.expectEmit();
        emit ERC20MultiToken.Transfer(POOL, OWNER, ZERO_ADDRESS, burnAmount);
        _burnWithBPTEmitTransferMock(POOL, OWNER, burnAmount);

        assertEq(token.balanceOf(POOL, OWNER), balanceAfterBurn, "Unexpected balance");
        assertEq(token.totalSupply(POOL), balanceAfterBurn, "Unexpected total supply");
    }

    function testDoubleBurnToCheckTotalSupply() public {
        uint256 firstMintAmount = token.getMinimumTotalSupply();
        uint256 secondMintAmount = DEFAULT_AMOUNT;
        uint256 burnAmount = 50;

        _mintWithBPTEmitTransferMock(POOL, OWNER, firstMintAmount);
        _mintWithBPTEmitTransferMock(POOL, OWNER2, secondMintAmount);

        _burnWithBPTEmitTransferMock(POOL, OWNER, burnAmount);
        assertEq(token.balanceOf(POOL, OWNER), firstMintAmount - burnAmount, "Unexpected balance (first)");

        uint256 totalSupplyAfterFirstBurn = (firstMintAmount + secondMintAmount) - burnAmount;
        assertEq(token.totalSupply(POOL), totalSupplyAfterFirstBurn, "Unexpected total supply (first)");

        uint256 totalSupplyAfterSecondBurn = totalSupplyAfterFirstBurn - burnAmount;
        _burnWithBPTEmitTransferMock(POOL, OWNER2, burnAmount);
        assertEq(token.balanceOf(POOL, OWNER2), secondMintAmount - burnAmount, "Unexpected balance (second)");
        assertEq(token.totalSupply(POOL), totalSupplyAfterSecondBurn, "Unexpected total supply (second)");
    }

    function testBurnRevertIfFromIsZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(ERC20InvalidSender.selector, ZERO_ADDRESS));
        token.manualBurn(POOL, ZERO_ADDRESS, DEFAULT_AMOUNT);
    }

    function testBurnRevertIfTotalSupplyIsLessThanMinimum() public {
        uint256 burnAmount = 1;

        _mintWithBPTEmitTransferMock(POOL, OWNER, MINIMUM_TOTAL_SUPPLY);

        vm.expectRevert(
            abi.encodeWithSelector(TotalSupplyTooLow.selector, MINIMUM_TOTAL_SUPPLY - burnAmount, MINIMUM_TOTAL_SUPPLY)
        );
        token.manualBurn(POOL, OWNER, burnAmount);
    }

    function testBurnRevertIfInsufficientBalance() public {
        uint256 mintAmount = token.getMinimumTotalSupply();
        uint256 burnAmount = mintAmount + 1;

        _mintWithBPTEmitTransferMock(POOL, OWNER, mintAmount);

        vm.expectRevert(abi.encodeWithSelector(ERC20InsufficientBalance.selector, OWNER, mintAmount, burnAmount));
        token.manualBurn(POOL, OWNER, burnAmount);
    }

    // #endregion

    // #region Transfer
    function testTransfer() public {
        _mintWithBPTEmitTransferMock(POOL, OWNER, MINIMUM_TOTAL_SUPPLY);

        vm.mockCall(
            POOL,
            abi.encodeWithSelector(BalancerPoolToken.emitTransfer.selector, OWNER, OWNER2, MINIMUM_TOTAL_SUPPLY),
            new bytes(0)
        );
        vm.expectEmit();
        emit ERC20MultiToken.Transfer(POOL, OWNER, OWNER2, MINIMUM_TOTAL_SUPPLY);
        token.manualTransfer(POOL, OWNER, OWNER2, MINIMUM_TOTAL_SUPPLY);

        assertEq(token.balanceOf(POOL, OWNER), 0, "Unexpected balance (owner)");
        assertEq(token.balanceOf(POOL, OWNER2), MINIMUM_TOTAL_SUPPLY, "Unexpected balance (owner2)");
    }

    function testTransferRevertIfFromIsZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(ERC20InvalidSender.selector, ZERO_ADDRESS));
        token.manualTransfer(POOL, ZERO_ADDRESS, OWNER, 100);
    }

    function testTransferRevertIfToIsZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(ERC20InvalidReceiver.selector, ZERO_ADDRESS));
        token.manualTransfer(POOL, OWNER, ZERO_ADDRESS, 100);
    }

    function testTransferRevertIfInsufficientBalance() public {
        uint256 transferAmount = MINIMUM_TOTAL_SUPPLY + 1;

        _mintWithBPTEmitTransferMock(POOL, OWNER, MINIMUM_TOTAL_SUPPLY);

        vm.expectRevert(
            abi.encodeWithSelector(ERC20InsufficientBalance.selector, OWNER, MINIMUM_TOTAL_SUPPLY, transferAmount)
        );
        token.manualTransfer(POOL, OWNER, OWNER2, transferAmount);
    }

    // #endregion

    // #region Private functions
    function _approveWithBPTEmitApprovalMock(address pool, address owner, address spender, uint256 amount) internal {
        vm.mockCall(
            pool,
            abi.encodeWithSelector(BalancerPoolToken.emitApproval.selector, owner, spender, amount),
            new bytes(0)
        );
        token.manualApprove(pool, owner, spender, amount);
    }

    function _mintWithBPTEmitTransferMock(address pool, address owner, uint256 amount) internal {
        vm.mockCall(
            pool,
            abi.encodeWithSelector(BalancerPoolToken.emitTransfer.selector, ZERO_ADDRESS, owner, amount),
            new bytes(0)
        );
        token.manualMint(pool, owner, amount);
    }

    function _burnWithBPTEmitTransferMock(address pool, address from, uint256 amount) internal {
        vm.mockCall(
            pool,
            abi.encodeWithSelector(BalancerPoolToken.emitTransfer.selector, from, ZERO_ADDRESS, amount),
            new bytes(0)
        );
        token.manualBurn(pool, from, amount);
    }
    // #endregion
}
