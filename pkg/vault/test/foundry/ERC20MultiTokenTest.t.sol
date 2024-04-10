// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { EVMCallModeHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/EVMCallModeHelpers.sol";
import { BalancerPoolToken } from "@balancer-labs/v3-vault/contracts/BalancerPoolToken.sol";
import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import { IERC20MultiToken } from "@balancer-labs/v3-interfaces/contracts/vault/IERC20MultiToken.sol";

import { ERC20MultiTokenMock } from "../../contracts/test/ERC20MultiTokenMock.sol";
import { ERC20MultiToken } from "../../contracts/token/ERC20MultiToken.sol";

contract ERC20MultiTokenTest is Test, IERC20Errors, IERC20MultiToken {
    address constant ZERO_ADDRESS = address(0x00);
    address constant POOL = address(0x01);
    address constant OWNER = address(0x02);
    address constant OWNER2 = address(0x03);
    address constant SPENDER = address(0x04);

    ERC20MultiTokenMock token;

    function setUp() public {
        token = new ERC20MultiTokenMock();
    }

    // #region Init values
    function testBalanceOfWithZeroValue() public {
        assertEq(token.balanceOf(POOL, OWNER), 0, "Unexpected balance");
    }

    function testTotalSupplyWithZeroValue() public {
        assertEq(token.totalSupply(POOL), 0, "Unexpected total supply");
    }
    // #endregion

    // #region Approve & Allowance & SpendAllowance
    function testAllowanceForTokenContract() public {
        assertEq(token.allowance(POOL, OWNER, address(token)), type(uint256).max, "Unexpected allowance");
    }

    function testAllowanceForNotTokenContractWithZeroValue() public {
        assertEq(token.allowance(POOL, OWNER, SPENDER), 0, "Unexpected allowance");
    }

    function testApprove() public {
        uint amount = 100;

        vm.expectEmit(true, true, true, true);
        emit ERC20MultiToken.Approval(POOL, OWNER, SPENDER, amount);
        _approveWithBPTEmitApprovalMock(POOL, OWNER, SPENDER, amount);

        assertEq(token.allowance(POOL, OWNER, SPENDER), amount, "Unexpected allowance");
    }

    function testApproveRevertIfOwnerIsZero() public {
        vm.expectRevert(abi.encodeWithSelector(ERC20InvalidApprover.selector, address(0x00)));
        token.manualApprove(POOL, ZERO_ADDRESS, SPENDER, 100);
    }

    function testApproveRevertIfSpenderIsZero() public {
        vm.expectRevert(abi.encodeWithSelector(ERC20InvalidSpender.selector, ZERO_ADDRESS));
        token.manualApprove(POOL, OWNER, ZERO_ADDRESS, 100);
    }

    function testSpendAllowance() public {
        uint initialAllowance = 200;
        uint spendAmount = initialAllowance - 1;
        uint remainingAllowance = initialAllowance - spendAmount;

        _approveWithBPTEmitApprovalMock(POOL, OWNER, SPENDER, initialAllowance);

        vm.expectEmit(true, true, true, true);
        emit ERC20MultiToken.Approval(POOL, OWNER, SPENDER, remainingAllowance);
        vm.mockCall(
            POOL,
            abi.encodeWithSelector(BalancerPoolToken.emitApproval.selector, OWNER, SPENDER, remainingAllowance),
            new bytes(0)
        );
        token.manualSpendAllowance(POOL, OWNER, SPENDER, spendAmount);

        assertEq(token.allowance(POOL, OWNER, SPENDER), initialAllowance - spendAmount, "Unexpected allowance");
    }

    function testSpendAllowanceRevertIfInsufficientAllowance() public {
        uint initialAllowance = 100;
        uint spendAmount = initialAllowance + 1;

        _approveWithBPTEmitApprovalMock(POOL, OWNER, SPENDER, initialAllowance);

        vm.expectRevert(
            abi.encodeWithSelector(ERC20InsufficientAllowance.selector, SPENDER, initialAllowance, spendAmount)
        );
        token.manualSpendAllowance(POOL, OWNER, SPENDER, spendAmount);
    }

    function testSpendAllowanceRevertIfAllowanceIsMax() public {
        _approveWithBPTEmitApprovalMock(POOL, OWNER, SPENDER, type(uint256).max);

        token.manualSpendAllowance(POOL, OWNER, SPENDER, 1);
    }
    // #endregion

    // #region QueryModeBalanceIncrease
    function testQueryModeBalanceIncrease() public {
        uint amount = 100;

        vm.prank(OWNER, address(0x00));
        token.manualQueryModeBalanceIncrease(POOL, OWNER, amount);
        assertEq(token.balanceOf(POOL, OWNER), amount, "Unexpected balance");
    }

    function testQueryModeBalanceIncreaseRevertIfCallIsNotStatic() public {
        vm.prank(OWNER, OWNER);
        vm.expectRevert(EVMCallModeHelpers.NotStaticCall.selector);
        token.manualQueryModeBalanceIncrease(POOL, OWNER, 300);
    }
    // #endregion

    // #region Mint
    function testMint() public {
        uint amount = token.getMinimumTotalSupply();

        vm.expectEmit(true, true, true, true);
        emit ERC20MultiToken.Transfer(POOL, ZERO_ADDRESS, OWNER, amount);
        _mintWithBPTEmitTransferMock(POOL, OWNER, amount);

        assertEq(token.balanceOf(POOL, OWNER), amount, "Unexpected balance");
        assertEq(token.totalSupply(POOL), amount, "Unexpected total supply");
    }

    function testDoubleMintToCheckTotalSupply() public {
        uint firstMintAmount = token.getMinimumTotalSupply();
        uint secondMintAmount = 100;

        _mintWithBPTEmitTransferMock(POOL, OWNER, firstMintAmount);

        assertEq(token.balanceOf(POOL, OWNER), firstMintAmount, "Unexpected balance");
        assertEq(token.totalSupply(POOL), firstMintAmount, "Unexpected total supply");

        _mintWithBPTEmitTransferMock(POOL, OWNER2, secondMintAmount);
        assertEq(token.balanceOf(POOL, OWNER2), secondMintAmount, "Unexpected balance");
        assertEq(token.totalSupply(POOL), firstMintAmount + secondMintAmount, "Unexpected total supply");
    }

    function testMintRevertIfToIsZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(ERC20InvalidReceiver.selector, ZERO_ADDRESS));
        token.manualMint(POOL, ZERO_ADDRESS, 100);
    }

    function testMintRevertIfTotalSupplyIsLessThanMinimum() public {
        uint minTotalSupply = token.getMinimumTotalSupply();
        uint amount = minTotalSupply - 1;
        vm.expectRevert(abi.encodeWithSelector(TotalSupplyTooLow.selector, amount, minTotalSupply));
        token.manualMint(POOL, OWNER, amount);
    }
    // #endregion

    // #region MintMinimumSupplyReserve
    function testMintMinimumSupplyReserve() public {
        uint amount = token.getMinimumTotalSupply();

        vm.expectEmit(true, true, true, true);
        emit ERC20MultiToken.Transfer(POOL, ZERO_ADDRESS, ZERO_ADDRESS, amount);
        vm.mockCall(
            POOL,
            abi.encodeWithSelector(BalancerPoolToken.emitTransfer.selector, ZERO_ADDRESS, ZERO_ADDRESS, amount),
            new bytes(0)
        );
        token.manualMintMinimumSupplyReserve(POOL);

        assertEq(token.balanceOf(POOL, ZERO_ADDRESS), amount, "Unexpected balance");
        assertEq(token.totalSupply(POOL), amount, "Unexpected total supply");
    }
    // #endregion

    // #region Burn
    function testBurn() public {
        uint burnAmount = 1;
        uint balanceAfterBurn = token.getMinimumTotalSupply();
        uint mintAmount = balanceAfterBurn + burnAmount;

        _mintWithBPTEmitTransferMock(POOL, OWNER, mintAmount);

        vm.expectEmit(true, true, true, true);
        emit ERC20MultiToken.Transfer(POOL, OWNER, ZERO_ADDRESS, burnAmount);
        _burnWithBPTEmitTransferMock(POOL, OWNER, burnAmount);

        assertEq(token.balanceOf(POOL, OWNER), balanceAfterBurn, "Unexpected balance");
        assertEq(token.totalSupply(POOL), balanceAfterBurn, "Unexpected total supply");
    }

    function testDoubleBurnToCheckTotalSupply() public {
        uint firstMintAmount = token.getMinimumTotalSupply();
        uint secondMintAmount = 100;

        uint burnAmount = 50;

        _mintWithBPTEmitTransferMock(POOL, OWNER, firstMintAmount);
        _mintWithBPTEmitTransferMock(POOL, OWNER2, secondMintAmount);

        _burnWithBPTEmitTransferMock(POOL, OWNER, burnAmount);
        assertEq(token.balanceOf(POOL, OWNER), firstMintAmount - burnAmount, "Unexpected balance");

        uint totalSupplyAfterFirstBurn = (firstMintAmount + secondMintAmount) - burnAmount;
        assertEq(token.totalSupply(POOL), totalSupplyAfterFirstBurn, "Unexpected total supply");

        uint totalSupplyAfterSecondBurn = totalSupplyAfterFirstBurn - burnAmount;
        _burnWithBPTEmitTransferMock(POOL, OWNER2, burnAmount);
        assertEq(token.balanceOf(POOL, OWNER2), secondMintAmount - burnAmount, "Unexpected balance");
        assertEq(token.totalSupply(POOL), totalSupplyAfterSecondBurn, "Unexpected total supply");
    }

    function testBurnRevertIfFromIsZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(ERC20InvalidSender.selector, ZERO_ADDRESS));
        token.manualBurn(POOL, ZERO_ADDRESS, 100);
    }

    function testBurnRevertIfTotalSupplyIsLessThanMinimum() public {
        uint minTotalSupply = token.getMinimumTotalSupply();
        uint burnAmount = minTotalSupply - 1;

        _mintWithBPTEmitTransferMock(POOL, OWNER, minTotalSupply);

        vm.expectRevert(
            abi.encodeWithSelector(TotalSupplyTooLow.selector, minTotalSupply - burnAmount, minTotalSupply)
        );
        token.manualBurn(POOL, OWNER, burnAmount);
    }

    function testBurnRevertIfInsufficientBalance() public {
        uint mintAmount = token.getMinimumTotalSupply();
        uint burnAmount = mintAmount + 1;

        _mintWithBPTEmitTransferMock(POOL, OWNER, mintAmount);

        vm.expectRevert(abi.encodeWithSelector(ERC20InsufficientBalance.selector, OWNER, mintAmount, burnAmount));
        token.manualBurn(POOL, OWNER, burnAmount);
    }
    // #endregion

    // #region Transfer
    function testTransfer() public {
        uint amount = token.getMinimumTotalSupply();

        _mintWithBPTEmitTransferMock(POOL, OWNER, amount);

        vm.mockCall(
            POOL,
            abi.encodeWithSelector(BalancerPoolToken.emitTransfer.selector, OWNER, OWNER2, amount),
            new bytes(0)
        );
        vm.expectEmit(true, true, true, true);
        emit ERC20MultiToken.Transfer(POOL, OWNER, OWNER2, amount);
        token.manualTransfer(POOL, OWNER, OWNER2, amount);

        assertEq(token.balanceOf(POOL, OWNER), 0, "Unexpected balance");
        assertEq(token.balanceOf(POOL, OWNER2), amount, "Unexpected balance");
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
        uint mintAmount = token.getMinimumTotalSupply();
        uint transferAmount = mintAmount + 1;

        _mintWithBPTEmitTransferMock(POOL, OWNER, mintAmount);

        vm.expectRevert(abi.encodeWithSelector(ERC20InsufficientBalance.selector, OWNER, mintAmount, transferAmount));
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
